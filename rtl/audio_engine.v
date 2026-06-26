// -----------------------------------------------------------------------------
// audio_engine.v  (Verilog-2001, Vivado Block Design)
//
// FPGA-master I2S passthrough with the Clouds granular engine + AXI4-Lite CSR.
// Codec subordinate; FPGA divides 100 MHz to make SCLK/LRCLK, so deser, engine,
// CSR and ser all share one clock domain. Drive S_AXI_ACLK from the SAME 100 MHz
// net as clk_100 (FCLK_CLK0) -> no clock-domain crossing on the register path.
//
//   PS GP AXI --(AXI4-Lite)--> clouds_csr_axil --(knobs)--> clouds_engine
//   iis_deser --(valid,l/r)--> clouds_engine  --(out)--> sampL/R --> iis_ser
// -----------------------------------------------------------------------------
module audio_engine # (
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)(
    // ---- audio / codec ----
    input  clk_100,     // 100 MHz (FCLK_CLK0)
    output sclk,        // I2S bit clock  (FPGA -> codec)
    output lrclk,       // I2S word clock (FPGA -> codec)
    input  sdata_adc,   // ADC data from codec
    output sdata_dac,   // DAC data to codec

    // ---- AXI4-Lite control (tie S_AXI_ACLK to clk_100 in the BD) ----
    input                                S_AXI_ACLK,
    input                                S_AXI_ARESETN,
    input  [C_S_AXI_ADDR_WIDTH-1:0]      S_AXI_AWADDR,
    input  [2:0]                         S_AXI_AWPROT,
    input                                S_AXI_AWVALID,
    output                               S_AXI_AWREADY,
    input  [C_S_AXI_DATA_WIDTH-1:0]      S_AXI_WDATA,
    input  [(C_S_AXI_DATA_WIDTH/8)-1:0]  S_AXI_WSTRB,
    input                                S_AXI_WVALID,
    output                               S_AXI_WREADY,
    output [1:0]                         S_AXI_BRESP,
    output                               S_AXI_BVALID,
    input                                S_AXI_BREADY,
    input  [C_S_AXI_ADDR_WIDTH-1:0]      S_AXI_ARADDR,
    input  [2:0]                         S_AXI_ARPROT,
    input                                S_AXI_ARVALID,
    output                               S_AXI_ARREADY,
    output [C_S_AXI_DATA_WIDTH-1:0]      S_AXI_RDATA,
    output [1:0]                         S_AXI_RRESP,
    output                               S_AXI_RVALID,
    input                                S_AXI_RREADY
);
    localparam BUF_AW   = 15;
    localparam N_GRAINS = 8;

    // ---- clock divider ----
    reg [31:0] clk_cntr = 32'd0;
    always @(posedge clk_100) clk_cntr <= clk_cntr + 1;
    assign sclk  = clk_cntr[4];
    assign lrclk = clk_cntr[10];

    // ---- audio data signals ----
    wire [23:0] ldata, rdata;
    wire        valid, wvalid;
    reg  [23:0] sampL = 24'd0;
    reg  [23:0] sampR = 24'd0;

    // ---- I2S receiver ----
    iis_deser u_deser (
        .CLK_100MHZ(clk_100), .SCLK(sclk), .LRCLK(lrclk), .SDATA(sdata_adc),
        .EN(1'b1), .LDATA(ldata), .RDATA(rdata), .VALID(valid), .WVALID(wvalid));

    // ---- valid -> single-cycle sample strobe ----
    reg valid_d = 1'b0;
    always @(posedge clk_100) valid_d <= valid;
    wire sample_valid = valid & ~valid_d;

    // ---- AXI4-Lite CSR ----
    wire [31:0] ctrl_w, pos_w, size_w, invh_w, pitch_w, den_w, tex_w, bln_w, wsh_w;
    wire [4:0]  grain_cnt_w;

    clouds_csr_axil #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH)
    ) u_csr (
        .ctrl_o(ctrl_w), .position_o(pos_w), .size_o(size_w), .inv_half_o(invh_w),
        .pitch_o(pitch_w), .density_o(den_w), .texture_o(tex_w), .blend_o(bln_w),
        .wet_shift_o(wsh_w), .grain_count_i(grain_cnt_w),
        .S_AXI_ACLK(S_AXI_ACLK), .S_AXI_ARESETN(S_AXI_ARESETN),
        .S_AXI_AWADDR(S_AXI_AWADDR), .S_AXI_AWPROT(S_AXI_AWPROT), .S_AXI_AWVALID(S_AXI_AWVALID), .S_AXI_AWREADY(S_AXI_AWREADY),
        .S_AXI_WDATA(S_AXI_WDATA), .S_AXI_WSTRB(S_AXI_WSTRB), .S_AXI_WVALID(S_AXI_WVALID), .S_AXI_WREADY(S_AXI_WREADY),
        .S_AXI_BRESP(S_AXI_BRESP), .S_AXI_BVALID(S_AXI_BVALID), .S_AXI_BREADY(S_AXI_BREADY),
        .S_AXI_ARADDR(S_AXI_ARADDR), .S_AXI_ARPROT(S_AXI_ARPROT), .S_AXI_ARVALID(S_AXI_ARVALID), .S_AXI_ARREADY(S_AXI_ARREADY),
        .S_AXI_RDATA(S_AXI_RDATA), .S_AXI_RRESP(S_AXI_RRESP), .S_AXI_RVALID(S_AXI_RVALID), .S_AXI_RREADY(S_AXI_RREADY));

    // ---- Clouds granular engine (knobs from CSR) ----
    wire signed [23:0] eng_l, eng_r;
    wire               eng_valid;

    clouds_engine #(.SAMPLE_W(24), .BUF_AW(BUF_AW), .N_GRAINS(N_GRAINS)) u_clouds (
        .clk(clk_100), .sample_valid(sample_valid),
        .enable     (ctrl_w[0]),
        .position_i (pos_w [BUF_AW-1:0]),
        .size_i     (size_w[15:0]),
        .inv_half_i (invh_w[17:0]),
        .pitch_i    (pitch_w),
        .density_i  (den_w [15:0]),
        .texture_i  (tex_w [15:0]),
        .blend_i    (bln_w [8:0]),
        .wet_shift_i(wsh_w [3:0]),
        .in_l(ldata), .in_r(rdata),
        .out_l(eng_l), .out_r(eng_r), .out_valid(eng_valid),
        .grain_count_o(grain_cnt_w));

    // ---- hold processed output for the serializer ----
    always @(posedge clk_100) if (eng_valid) begin
        sampL <= eng_l;
        sampR <= eng_r;
    end

    // ---- I2S transmitter ----
    iis_ser u_ser (
        .CLK_100MHZ(clk_100), .SCLK(sclk), .LRCLK(lrclk), .SDATA(sdata_dac),
        .EN(1'b1), .LDATA(sampL), .RDATA(sampR));
endmodule
