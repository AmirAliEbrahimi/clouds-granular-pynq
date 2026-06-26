// -----------------------------------------------------------------------------
// clouds_csr_axil.v   (Verilog-2001)  -- AXI4-Lite slave register file for Clouds
//
// Register map (32-bit, byte offsets):
//   0x00 CTRL      [0]   enable (1=granular, 0=clean passthrough)  RW  (rst 0)
//   0x04 POSITION  [14:0] samples behind write head                RW  (rst 16000)
//   0x08 SIZE      [15:0] grain length in samples                  RW  (rst 2400)
//   0x0C INV_HALF  [17:0] 65536/(SIZE>>1)  -- HW-computed           RO
//   0x10 PITCH     [31:0] 16.16 playback rate (unity=0x00010000)   RW  (rst 0x10000)
//   0x14 DENSITY   [15:0] samples between grain spawns             RW  (rst 800)
//   0x18 TEXTURE   [15:0] jitter span (power of 2)                 RW  (rst 2048)
//   0x1C BLEND     [8:0]  0=dry .. 256=full wet                    RW  (rst 160)
//   0x20 WET_SHIFT [3:0]  wet normalisation shift                  RW  (rst 1)
//   0x24 STATUS    [4:0] active grains, [8] recip busy             RO
//   0x28 ID        0x434C4F44 ("CLOD")                             RO
//
// INV_HALF is derived in hardware: writing SIZE retriggers a ~17-cycle divider
// (clouds_recip) that recomputes the window slope. Software only writes SIZE.
// Single clock domain: drive S_AXI_ACLK from the same 100 MHz net as the engine.
// -----------------------------------------------------------------------------
module clouds_csr_axil #(
    parameter C_S_AXI_DATA_WIDTH = 32,
    parameter C_S_AXI_ADDR_WIDTH = 6
)(
    output [31:0] ctrl_o,
    output [31:0] position_o,
    output [31:0] size_o,
    output [31:0] inv_half_o,        // HW-computed
    output [31:0] pitch_o,
    output [31:0] density_o,
    output [31:0] texture_o,
    output [31:0] blend_o,
    output [31:0] wet_shift_o,
    input  [4:0]  grain_count_i,

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
    localparam ADDR_LSB = 2;

    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_awaddr;
    reg                          axi_awready, axi_wready, axi_bvalid;
    reg [1:0]                    axi_bresp;
    reg [C_S_AXI_ADDR_WIDTH-1:0] axi_araddr;
    reg                          axi_arready, axi_rvalid;
    reg [1:0]                    axi_rresp;
    reg [C_S_AXI_DATA_WIDTH-1:0] axi_rdata;

    assign S_AXI_AWREADY = axi_awready;
    assign S_AXI_WREADY  = axi_wready;
    assign S_AXI_BRESP   = axi_bresp;
    assign S_AXI_BVALID  = axi_bvalid;
    assign S_AXI_ARREADY = axi_arready;
    assign S_AXI_RDATA   = axi_rdata;
    assign S_AXI_RRESP   = axi_rresp;
    assign S_AXI_RVALID  = axi_rvalid;

    // ---- RW register storage (INV_HALF is NOT here - it is HW-computed) ----
    reg [31:0] reg_ctrl, reg_position, reg_size, reg_pitch;
    reg [31:0] reg_density, reg_texture, reg_blend, reg_wetshift;

    // ---- hardware reciprocal: inv_half = 65536/(size>>1) ----
    wire [17:0] recip_inv;
    wire        recip_busy;
    reg         recompute, recompute_d;

    assign ctrl_o      = reg_ctrl;
    assign position_o  = reg_position;
    assign size_o      = reg_size;
    assign inv_half_o  = {14'd0, recip_inv};
    assign pitch_o     = reg_pitch;
    assign density_o   = reg_density;
    assign texture_o   = reg_texture;
    assign blend_o     = reg_blend;
    assign wet_shift_o = reg_wetshift;

    wire wr_en   = axi_awready & S_AXI_AWVALID & axi_wready & S_AXI_WVALID;
    wire rd_en   = axi_arready & S_AXI_ARVALID & ~axi_rvalid;
    wire size_wr = wr_en & (axi_awaddr[ADDR_LSB+3:ADDR_LSB] == 4'd2);
    integer b;

    clouds_recip u_recip (
        .clk(S_AXI_ACLK), .rstn(S_AXI_ARESETN), .start(recompute_d),
        .size_in(reg_size[15:0]), .inv_half(recip_inv), .busy(recip_busy));

    // recompute trigger: once after reset (default SIZE), and on each SIZE write.
    // recompute pulses on the write cycle; recompute_d fires the divider one cycle
    // later, by which time reg_size holds the new value.
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin recompute <= 1'b1; recompute_d <= 1'b0; end
        else begin
            recompute   <= size_wr;
            recompute_d <= recompute;
        end
    end

    // ---- write address / data ready ----
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin axi_awready<=1'b0; axi_awaddr<=0; end
        else if (~axi_awready & S_AXI_AWVALID & S_AXI_WVALID) begin
            axi_awready<=1'b1; axi_awaddr<=S_AXI_AWADDR;
        end else axi_awready<=1'b0;
    end
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) axi_wready<=1'b0;
        else if (~axi_wready & S_AXI_WVALID & S_AXI_AWVALID) axi_wready<=1'b1;
        else axi_wready<=1'b0;
    end

    // ---- register write (byte strobes) + reset defaults ----
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            reg_ctrl    <= 32'd0;          // effect OFF at power-on
            reg_position<= 32'd16000;
            reg_size    <= 32'd2400;
            reg_pitch   <= 32'h0001_0000;
            reg_density <= 32'd800;
            reg_texture <= 32'd2048;
            reg_blend   <= 32'd160;
            reg_wetshift<= 32'd1;
        end else if (wr_en) begin
            case (axi_awaddr[ADDR_LSB+3:ADDR_LSB])
              4'd0: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_ctrl    [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd1: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_position[b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd2: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_size    [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              // 4'd3 (INV_HALF) is read-only / HW-computed - writes ignored
              4'd4: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_pitch   [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd5: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_density [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd6: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_texture [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd7: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_blend   [b*8+:8]<=S_AXI_WDATA[b*8+:8];
              4'd8: for(b=0;b<4;b=b+1) if(S_AXI_WSTRB[b]) reg_wetshift[b*8+:8]<=S_AXI_WDATA[b*8+:8];
              default: ;
            endcase
        end
    end

    // ---- write response ----
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin axi_bvalid<=1'b0; axi_bresp<=2'b0; end
        else if (axi_awready & S_AXI_AWVALID & ~axi_bvalid & axi_wready & S_AXI_WVALID) begin
            axi_bvalid<=1'b1; axi_bresp<=2'b00;
        end else if (S_AXI_BREADY & axi_bvalid) axi_bvalid<=1'b0;
    end

    // ---- read address ----
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin axi_arready<=1'b0; axi_araddr<=0; end
        else if (~axi_arready & S_AXI_ARVALID) begin
            axi_arready<=1'b1; axi_araddr<=S_AXI_ARADDR;
        end else axi_arready<=1'b0;
    end

    // ---- read data mux ----
    always @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin axi_rvalid<=1'b0; axi_rresp<=2'b0; axi_rdata<=0; end
        else if (rd_en) begin
            axi_rvalid<=1'b1; axi_rresp<=2'b00;
            case (axi_araddr[ADDR_LSB+3:ADDR_LSB])
              4'd0:  axi_rdata<=reg_ctrl;
              4'd1:  axi_rdata<=reg_position;
              4'd2:  axi_rdata<=reg_size;
              4'd3:  axi_rdata<={14'd0, recip_inv};               // INV_HALF (RO)
              4'd4:  axi_rdata<=reg_pitch;
              4'd5:  axi_rdata<=reg_density;
              4'd6:  axi_rdata<=reg_texture;
              4'd7:  axi_rdata<=reg_blend;
              4'd8:  axi_rdata<=reg_wetshift;
              4'd9:  axi_rdata<={23'd0, recip_busy, 3'd0, grain_count_i}; // STATUS
              4'd10: axi_rdata<=32'h434C4F44;                     // ID
              default: axi_rdata<=32'd0;
            endcase
        end else if (axi_rvalid & S_AXI_RREADY) axi_rvalid<=1'b0;
    end
endmodule
