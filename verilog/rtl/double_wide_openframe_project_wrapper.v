`default_nettype none

// Keep this module name and port list identical to the current
// double_wide_openframe harness wrapper.

`ifdef USE_POWER_PINS
    // The existing Neuromorphic stub may use USE_PG_PIN internally.
    `ifndef USE_PG_PIN
        `define USE_PG_PIN
    `endif
`endif

module double_wide_openframe_project_wrapper (
`ifdef USE_POWER_PINS
    inout wire vddio,
    inout wire vssio,
    inout wire vccd,
    inout wire vssd,
    inout wire vdda,
    inout wire vssa,
    inout wire vdda1,
    inout wire vssa1,
    inout wire vccd1,
    inout wire vssd1,
    inout wire vdda2,
    inout wire vssa2,
    inout wire vccd2,
    inout wire vssd2,
`endif
    input  wire        porb_h,
    input  wire        por_l,
    input  wire        porb_l,
    input  wire        resetb_h,
    input  wire        resetb_l,

    input  wire [62:0] gpio_in,
    input  wire [62:0] gpio_in_h,
    input  wire [62:0] gpio_loopback_one,
    input  wire [62:0] gpio_loopback_zero,

    output reg  [62:0] gpio_out,
    output reg  [62:0] gpio_oeb,
    output reg  [62:0] gpio_inp_dis,
    output reg  [62:0] gpio_ib_mode_sel,
    output reg  [62:0] gpio_vtrip_sel,
    output reg  [62:0] gpio_slow_sel,
    output reg  [62:0] gpio_holdover,
    output reg  [62:0] gpio_analog_en,
    output reg  [62:0] gpio_analog_sel,
    output reg  [62:0] gpio_analog_pol,
    output reg  [62:0] gpio_dm0,
    output reg  [62:0] gpio_dm1,
    output reg  [62:0] gpio_dm2,

    inout  wire [62:0] analog_io,
    inout  wire [62:0] analog_noesd_io
);

    // ------------------------------------------------------------------
    // External clocks and reset
    // ------------------------------------------------------------------

    wire sys_clk  = gpio_in[14];
    wire spi_sclk = gpio_in[15];
    wire spi_cs_n = gpio_in[16];
    wire spi_mosi = gpio_in[17];

    // Assert reset when either the POR or dedicated external reset is active.
    wire sys_rst = ~(porb_l & resetb_l);

    // ------------------------------------------------------------------
    // SPI-to-Wishbone bridge
    // ------------------------------------------------------------------

    wire        spi_miso;
    wire        wb_cyc;
    wire        wb_stb;
    wire        wb_we;
    wire [3:0]  wb_sel;
    wire [31:0] wb_addr;
    wire [31:0] wb_wdata;
    wire [31:0] wb_rdata;
    wire        wb_ack;

    spi_wb_bridge_sameframe #(
        .WB_ADDRESS       (32'h3000_0004),
        .WB_TIMEOUT_CYCLES(8'd255)
    ) spi_bridge (
        .clk      (sys_clk),
        .rst      (sys_rst),
        .spi_sclk (spi_sclk),
        .spi_cs_n (spi_cs_n),
        .spi_mosi (spi_mosi),
        .spi_miso (spi_miso),
        .wb_cyc_o (wb_cyc),
        .wb_stb_o (wb_stb),
        .wb_we_o  (wb_we),
        .wb_sel_o (wb_sel),
        .wb_adr_o (wb_addr),
        .wb_dat_o (wb_wdata),
        .wb_dat_i (wb_rdata),
        .wb_ack_i (wb_ack)
    );

    // ------------------------------------------------------------------
    // Neuromorphic hard macro
    // ------------------------------------------------------------------

    wire scan_out;

    Neuromorphic_X1_wb neuro_inst (
`ifdef USE_POWER_PINS
        .VDDC1(vccd1),
        .VDDC2(vccd2),
        .VDDA1(vdda1),
        .VDDA2(vdda2),
        .VSS  (vssd1),
`endif
        .user_clk(sys_clk),
        .user_rst(sys_rst),
        .wb_clk_i(sys_clk),
        .wb_rst_i(sys_rst),

        .wbs_stb_i(wb_stb),
        .wbs_cyc_i(wb_cyc),
        .wbs_we_i (wb_we),
        .wbs_sel_i(wb_sel),
        .wbs_dat_i(wb_wdata),
        .wbs_adr_i(wb_addr),
        .wbs_dat_o(wb_rdata),
        .wbs_ack_o(wb_ack),

        .ScanInCC (gpio_in[35]),
        .ScanInDL (gpio_in[22]),
        .ScanInDR (gpio_in[21]),
        .TM       (gpio_in[36]),
        .ScanOutCC(scan_out),

        // In OpenFrame, analog_io[n] maps directly to GPIO n.
        .dc_bias      (analog_io[25]),
        .Vcc_wl_read  (analog_io[26]),
        .Vcc_set      (analog_io[27]),
        .Vcc_wl_reset (analog_io[28]),
        .Vbias        (analog_io[29]),
        .Vcc_wl_set   (analog_io[30]),
        .Bias_comp2   (analog_io[31]),
        .Vcomp        (analog_io[32]),
        .Vcc_read     (analog_io[33]),
        .Iref         (analog_io[34])
    );

    // ------------------------------------------------------------------
    // GPIO pad configuration
    // ------------------------------------------------------------------
    // Digital input : dm[2:0] = 3'b001, oeb = 1.
    // Digital output: dm[2:0] = 3'b110, oeb = 0.
    // Analog        : dm[2:0] = 3'b000, oeb = 1, inp_dis = 1.

    integer pad_index;
    always @* begin
        // Safe default: all pads are ordinary digital inputs. Use the
        // per-pad loopback constants supplied by the frame so each constant
        // connection remains local to its boundary pin instead of creating
        // large chip-wide constant nets.
        gpio_out         = gpio_loopback_zero;
        gpio_oeb         = gpio_loopback_one;
        gpio_inp_dis     = gpio_loopback_zero;
        gpio_ib_mode_sel = gpio_loopback_zero;
        gpio_vtrip_sel   = gpio_loopback_zero;
        gpio_slow_sel    = gpio_loopback_zero;
        gpio_holdover    = gpio_loopback_zero;
        gpio_analog_en   = gpio_loopback_zero;
        gpio_analog_sel  = gpio_loopback_zero;
        gpio_analog_pol  = gpio_loopback_zero;
        gpio_dm0         = gpio_loopback_one;
        gpio_dm1         = gpio_loopback_zero;
        gpio_dm2         = gpio_loopback_zero;

        // GPIO18: SPI MISO. Disable output whenever CS is inactive.
        gpio_out[18]     = spi_miso;
        gpio_oeb[18]     = spi_cs_n;
        gpio_inp_dis[18] = gpio_loopback_one[18];
        gpio_dm0[18]     = gpio_loopback_zero[18];
        gpio_dm1[18]     = gpio_loopback_one[18];
        gpio_dm2[18]     = gpio_loopback_one[18];

        // GPIO23: scan output.
        gpio_out[23]     = scan_out;
        gpio_oeb[23]     = gpio_loopback_zero[23];
        gpio_inp_dis[23] = gpio_loopback_one[23];
        gpio_dm0[23]     = gpio_loopback_zero[23];
        gpio_dm1[23]     = gpio_loopback_one[23];
        gpio_dm2[23]     = gpio_loopback_one[23];

        // GPIO25..34: direct analog connections to the hard macro.
        for (pad_index = 25; pad_index <= 34; pad_index = pad_index + 1) begin
            gpio_oeb[pad_index]     = gpio_loopback_one[pad_index];
            gpio_inp_dis[pad_index] = gpio_loopback_one[pad_index];
            gpio_dm0[pad_index]     = gpio_loopback_zero[pad_index];
            gpio_dm1[pad_index]     = gpio_loopback_zero[pad_index];
            gpio_dm2[pad_index]     = gpio_loopback_zero[pad_index];
        end
    end

    // Intentionally unused by this project:
    // porb_h, por_l, resetb_h, gpio_in_h and analog_noesd_io.

endmodule

`default_nettype wire

