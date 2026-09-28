`timescale 1ns/1ps
`default_nettype none

module spi_wb_bridge_sameframe_tb;

    reg clk = 1'b0;
    reg rst = 1'b1;
    reg spi_sclk = 1'b0;
    reg spi_cs_n = 1'b1;
    reg spi_mosi = 1'b0;
    wire spi_miso;

    wire        wb_cyc;
    wire        wb_stb;
    wire        wb_we;
    wire [3:0]  wb_sel;
    wire [31:0] wb_adr;
    wire [31:0] wb_dat_o;
    reg  [31:0] wb_dat_i = 32'h0;
    reg         wb_ack = 1'b0;

    reg [31:0] last_write_data = 32'h0;
    reg [31:0] spi_read_data = 32'h0;
    reg sampled_miso;
    integer i;

    localparam [31:0] EXPECTED_READ  = 32'hCAFE_BABE;
    localparam [31:0] EXPECTED_WRITE = 32'h1234_5678;

    spi_wb_bridge_sameframe dut (
        .clk      (clk),
        .rst      (rst),
        .spi_sclk (spi_sclk),
        .spi_cs_n (spi_cs_n),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .wb_cyc_o (wb_cyc),
        .wb_stb_o (wb_stb),
        .wb_we_o  (wb_we),
        .wb_sel_o (wb_sel),
        .wb_adr_o (wb_adr),
        .wb_dat_o (wb_dat_o),
        .wb_dat_i (wb_dat_i),
        .wb_ack_i (wb_ack)
    );

    // 20 MHz system clock.
    always #25 clk = ~clk;

    // One-cycle-latency Wishbone slave model.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_ack          <= 1'b0;
            wb_dat_i        <= 32'h0;
            last_write_data <= 32'h0;
        end else begin
            wb_ack <= 1'b0;
            if (wb_cyc && wb_stb && !wb_ack) begin
                wb_ack <= 1'b1;
                if (wb_we)
                    last_write_data <= wb_dat_o;
                else
                    wb_dat_i <= EXPECTED_READ;
            end
        end
    end

    task spi_transfer_bit;
        input  tx_bit;
        output rx_bit;
        begin
            spi_mosi = tx_bit;
            #100;
            spi_sclk = 1'b1;
            #1;
            rx_bit = spi_miso;
            #99;
            spi_sclk = 1'b0;
        end
    endtask

    task spi_send_byte;
        input [7:0] value;
        begin
            for (i = 7; i >= 0; i = i - 1)
                spi_transfer_bit(value[i], sampled_miso);
        end
    endtask

    task spi_read_byte;
        output [7:0] value;
        integer bit_index;
        begin
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1)
                spi_transfer_bit(1'b0, value[bit_index]);
        end
    endtask

    initial begin
        #200;
        rst = 1'b0;
        #200;

        // WRITE: 0x60 followed by 0x12345678.
        spi_cs_n = 1'b0;
        spi_send_byte(8'h60);
        spi_send_byte(8'h12);
        spi_send_byte(8'h34);
        spi_send_byte(8'h56);
        spi_send_byte(8'h78);
        spi_cs_n = 1'b1;

        #500;
        if (last_write_data !== EXPECTED_WRITE) begin
            $display("FAIL: write data %08x, expected %08x",
                     last_write_data, EXPECTED_WRITE);
            $finish;
        end

        // READ: 0x40 followed by 32 dummy bits.
        #500;
        spi_cs_n = 1'b0;
        spi_send_byte(8'h40);
        spi_read_byte(spi_read_data[31:24]);
        spi_read_byte(spi_read_data[23:16]);
        spi_read_byte(spi_read_data[15:8]);
        spi_read_byte(spi_read_data[7:0]);
        spi_cs_n = 1'b1;

        #200;
        if (spi_read_data !== EXPECTED_READ) begin
            $display("FAIL: read data %08x, expected %08x",
                     spi_read_data, EXPECTED_READ);
            $finish;
        end

        $display("PASS: SPI write and same-frame read completed correctly.");
        $finish;
    end

endmodule

`default_nettype wire
