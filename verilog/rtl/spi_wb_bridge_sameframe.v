`timescale 1ns/1ps
`default_nettype none

// SPI mode-0 to Wishbone Classic single-master bridge.
//
// SPI protocol, MSB first:
//   WRITE: 0x6x followed by 32 payload bits.
//   READ : 0x4x followed by 32 dummy bits. Read data is returned on MISO.
//
// The read request is launched after the upper command nibble. This preserves
// the existing same-frame protocol and gives the 20 MHz Wishbone side most of
// the command byte to complete before the 5 MHz SPI data phase starts.
//
// Request and response crossings use toggle mailboxes. The 32-bit mailbox is
// held stable while its toggle is synchronized into the destination domain.

module spi_wb_bridge_sameframe #(
    parameter [31:0] WB_ADDRESS = 32'h3000_0004,
    parameter [7:0]  WB_TIMEOUT_CYCLES = 8'd255
) (
    input  wire        clk,
    input  wire        rst,

    input  wire        spi_sclk,
    input  wire        spi_cs_n,
    input  wire        spi_mosi,
    output reg         spi_miso,

    output reg         wb_cyc_o,
    output reg         wb_stb_o,
    output reg         wb_we_o,
    output reg  [3:0]  wb_sel_o,
    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    input  wire [31:0] wb_dat_i,
    input  wire        wb_ack_i
);

    localparam [1:0] CMD_NONE  = 2'd0;
    localparam [1:0] CMD_WRITE = 2'd1;
    localparam [1:0] CMD_READ  = 2'd2;

    localparam [31:0] WB_TIMEOUT_DATA = 32'hDEAD_C0DE;

    // ------------------------------------------------------------------
    // SPI receive domain
    // ------------------------------------------------------------------

    reg [7:0]  command_shift_spi;
    reg [31:0] write_shift_spi;
    reg [5:0]  bit_count_spi;
    reg [1:0]  command_type_spi;

    reg         write_request_toggle_spi;
    reg         read_request_toggle_spi;
    reg [31:0]  write_data_mailbox_spi;

    wire spi_frame_reset = rst | spi_cs_n;

    // Frame-local state resets whenever chip select is released.
    always @(posedge spi_sclk or posedge spi_frame_reset) begin
        if (spi_frame_reset) begin
            command_shift_spi <= 8'h00;
            write_shift_spi   <= 32'h0000_0000;
            bit_count_spi     <= 6'd0;
            command_type_spi  <= CMD_NONE;
        end else begin
            if (bit_count_spi < 6'd8) begin
                command_shift_spi <= {command_shift_spi[6:0], spi_mosi};

                if (bit_count_spi == 6'd3) begin
                    case ({command_shift_spi[2:0], spi_mosi})
                        4'h6: command_type_spi <= CMD_WRITE;
                        4'h4: command_type_spi <= CMD_READ;
                        default: command_type_spi <= CMD_NONE;
                    endcase
                end
            end else if ((bit_count_spi < 6'd40) &&
                         (command_type_spi == CMD_WRITE)) begin
                write_shift_spi <= {write_shift_spi[30:0], spi_mosi};
            end

            if (bit_count_spi < 6'd40)
                bit_count_spi <= bit_count_spi + 6'd1;
        end
    end

    // Request toggles must persist across chip-select boundaries.
    always @(posedge spi_sclk or posedge rst) begin
        if (rst) begin
            write_request_toggle_spi <= 1'b0;
            read_request_toggle_spi  <= 1'b0;
            write_data_mailbox_spi   <= 32'h0000_0000;
        end else if (!spi_cs_n) begin
            // Decode the read from the first four command bits.
            if ((bit_count_spi == 6'd3) &&
                ({command_shift_spi[2:0], spi_mosi} == 4'h4)) begin
                read_request_toggle_spi <= ~read_request_toggle_spi;
            end

            // Publish write data when all 40 frame bits have arrived.
            if ((bit_count_spi == 6'd39) &&
                (command_type_spi == CMD_WRITE)) begin
                write_data_mailbox_spi   <= {write_shift_spi[30:0], spi_mosi};
                write_request_toggle_spi <= ~write_request_toggle_spi;
            end
        end
    end

    // ------------------------------------------------------------------
    // Request toggle synchronizers into the Wishbone domain
    // ------------------------------------------------------------------

    (* ASYNC_REG = "TRUE" *) reg write_request_sync1_wb;
    (* ASYNC_REG = "TRUE" *) reg write_request_sync2_wb;
    (* ASYNC_REG = "TRUE" *) reg read_request_sync1_wb;
    (* ASYNC_REG = "TRUE" *) reg read_request_sync2_wb;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_request_sync1_wb <= 1'b0;
            write_request_sync2_wb <= 1'b0;
            read_request_sync1_wb  <= 1'b0;
            read_request_sync2_wb  <= 1'b0;
        end else begin
            write_request_sync1_wb <= write_request_toggle_spi;
            write_request_sync2_wb <= write_request_sync1_wb;
            read_request_sync1_wb  <= read_request_toggle_spi;
            read_request_sync2_wb  <= read_request_sync1_wb;
        end
    end

    // ------------------------------------------------------------------
    // Wishbone engine and read-response mailbox
    // ------------------------------------------------------------------

    reg        write_request_seen_wb;
    reg        read_request_seen_wb;
    reg        active_transaction_is_read_wb;
    reg [7:0]  timeout_count_wb;
    reg [31:0] read_data_mailbox_wb;
    reg        read_response_toggle_wb;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            write_request_seen_wb         <= 1'b0;
            read_request_seen_wb          <= 1'b0;
            active_transaction_is_read_wb <= 1'b0;
            timeout_count_wb              <= 8'd0;
            read_data_mailbox_wb          <= 32'h0000_0000;
            read_response_toggle_wb       <= 1'b0;

            wb_cyc_o <= 1'b0;
            wb_stb_o <= 1'b0;
            wb_we_o  <= 1'b0;
            wb_sel_o <= 4'h0;
            wb_adr_o <= WB_ADDRESS;
            wb_dat_o <= 32'h0000_0000;
        end else begin
            if (!wb_cyc_o) begin
                wb_stb_o         <= 1'b0;
                wb_we_o          <= 1'b0;
                wb_sel_o         <= 4'h0;
                timeout_count_wb <= 8'd0;

                // Read has priority if both requests are pending.
                if (read_request_sync2_wb != read_request_seen_wb) begin
                    read_request_seen_wb          <= read_request_sync2_wb;
                    active_transaction_is_read_wb <= 1'b1;

                    wb_cyc_o <= 1'b1;
                    wb_stb_o <= 1'b1;
                    wb_we_o  <= 1'b0;
                    wb_sel_o <= 4'hF;
                    wb_adr_o <= WB_ADDRESS;
                    wb_dat_o <= 32'h0000_0000;
                end else if (write_request_sync2_wb != write_request_seen_wb) begin
                    write_request_seen_wb         <= write_request_sync2_wb;
                    active_transaction_is_read_wb <= 1'b0;

                    wb_cyc_o <= 1'b1;
                    wb_stb_o <= 1'b1;
                    wb_we_o  <= 1'b1;
                    wb_sel_o <= 4'hF;
                    wb_adr_o <= WB_ADDRESS;
                    wb_dat_o <= write_data_mailbox_spi;
                end
            end else if (wb_ack_i) begin
                if (active_transaction_is_read_wb) begin
                    read_data_mailbox_wb    <= wb_dat_i;
                    read_response_toggle_wb <= ~read_response_toggle_wb;
                end

                wb_cyc_o         <= 1'b0;
                wb_stb_o         <= 1'b0;
                wb_we_o          <= 1'b0;
                wb_sel_o         <= 4'h0;
                timeout_count_wb <= 8'd0;
            end else if (timeout_count_wb == WB_TIMEOUT_CYCLES) begin
                // Release a stalled bus. A timed-out read returns a marker.
                if (active_transaction_is_read_wb) begin
                    read_data_mailbox_wb    <= WB_TIMEOUT_DATA;
                    read_response_toggle_wb <= ~read_response_toggle_wb;
                end

                wb_cyc_o         <= 1'b0;
                wb_stb_o         <= 1'b0;
                wb_we_o          <= 1'b0;
                wb_sel_o         <= 4'h0;
                timeout_count_wb <= 8'd0;
            end else begin
                timeout_count_wb <= timeout_count_wb + 8'd1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Read response synchronization back to the SPI domain
    // ------------------------------------------------------------------

    (* ASYNC_REG = "TRUE" *) reg read_response_sync1_spi;
    (* ASYNC_REG = "TRUE" *) reg read_response_sync2_spi;

    always @(posedge spi_sclk or posedge rst) begin
        if (rst) begin
            read_response_sync1_spi <= 1'b0;
            read_response_sync2_spi <= 1'b0;
        end else begin
            read_response_sync1_spi <= read_response_toggle_wb;
            read_response_sync2_spi <= read_response_sync1_spi;
        end
    end

    reg [31:0] read_shift_spi;
    reg        read_data_loaded_spi;
    reg        read_response_seen_spi;

    wire read_response_event_spi =
        read_response_sync2_spi != read_response_seen_spi;

    // Consume each mailbox response once. This state persists between frames.
    always @(negedge spi_sclk or posedge rst) begin
        if (rst) begin
            read_response_seen_spi <= 1'b0;
        end else if (!spi_cs_n && read_response_event_spi) begin
            read_response_seen_spi <= read_response_sync2_spi;
        end
    end

    // SPI mode 0: change MISO on falling edges, sample on rising edges.
    always @(negedge spi_sclk or posedge spi_frame_reset) begin
        if (spi_frame_reset) begin
            spi_miso             <= 1'b0;
            read_shift_spi       <= 32'h0000_0000;
            read_data_loaded_spi <= 1'b0;
        end else begin
            if ((command_type_spi == CMD_READ) && read_response_event_spi) begin
                read_data_loaded_spi <= 1'b1;

                // Handle a response that arrives on the first data edge.
                if ((bit_count_spi >= 6'd8) && (bit_count_spi < 6'd40)) begin
                    spi_miso       <= read_data_mailbox_wb[31];
                    read_shift_spi <= {read_data_mailbox_wb[30:0], 1'b0};
                end else begin
                    spi_miso       <= 1'b0;
                    read_shift_spi <= read_data_mailbox_wb;
                end
            end else if (bit_count_spi < 6'd8) begin
                spi_miso <= 1'b0;
            end else if ((bit_count_spi < 6'd40) &&
                         (command_type_spi == CMD_READ)) begin
                if (read_data_loaded_spi) begin
                    spi_miso       <= read_shift_spi[31];
                    read_shift_spi <= {read_shift_spi[30:0], 1'b0};
                end else begin
                    spi_miso <= 1'b0;
                end
            end else begin
                spi_miso <= 1'b0;
            end
        end
    end

endmodule

`default_nettype wire
