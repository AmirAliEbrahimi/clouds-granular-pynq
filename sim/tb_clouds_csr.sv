`timescale 1ns/1ps
module tb_csr;
  localparam AW=6, DW=32, BUF_AW=12;
  logic clk=0, rstn=0; always #5 clk=~clk;

  // AXI master signals
  logic [AW-1:0] AWADDR, ARADDR; logic [2:0] AWPROT=0, ARPROT=0;
  logic AWVALID=0, WVALID=0, BREADY=0, ARVALID=0, RREADY=0;
  logic [DW-1:0] WDATA; logic [3:0] WSTRB;
  wire  AWREADY, WREADY, BVALID, ARREADY, RVALID;
  wire [1:0] BRESP, RRESP; wire [DW-1:0] RDATA;

  // CSR <-> engine
  wire [31:0] ctrl,pos,sz,ivh,pit,den,tex,bln,wsh; wire [4:0] gc;

  clouds_csr_axil #(.C_S_AXI_ADDR_WIDTH(AW)) csr (
    .ctrl_o(ctrl), .position_o(pos), .size_o(sz), .inv_half_o(ivh), .pitch_o(pit),
    .density_o(den), .texture_o(tex), .blend_o(bln), .wet_shift_o(wsh), .grain_count_i(gc),
    .S_AXI_ACLK(clk), .S_AXI_ARESETN(rstn),
    .S_AXI_AWADDR(AWADDR), .S_AXI_AWPROT(AWPROT), .S_AXI_AWVALID(AWVALID), .S_AXI_AWREADY(AWREADY),
    .S_AXI_WDATA(WDATA), .S_AXI_WSTRB(WSTRB), .S_AXI_WVALID(WVALID), .S_AXI_WREADY(WREADY),
    .S_AXI_BRESP(BRESP), .S_AXI_BVALID(BVALID), .S_AXI_BREADY(BREADY),
    .S_AXI_ARADDR(ARADDR), .S_AXI_ARPROT(ARPROT), .S_AXI_ARVALID(ARVALID), .S_AXI_ARREADY(ARREADY),
    .S_AXI_RDATA(RDATA), .S_AXI_RRESP(RRESP), .S_AXI_RVALID(RVALID), .S_AXI_RREADY(RREADY));

  logic sv=0; logic signed [23:0] il, ir, ol, orr; logic ov;
  clouds_engine #(.SAMPLE_W(24), .BUF_AW(BUF_AW), .N_GRAINS(8)) eng (
    .clk(clk), .sample_valid(sv), .enable(ctrl[0]),
    .position_i(pos[BUF_AW-1:0]), .size_i(sz[15:0]), .inv_half_i(ivh[17:0]),
    .pitch_i(pit), .density_i(den[15:0]), .texture_i(tex[15:0]),
    .blend_i(bln[8:0]), .wet_shift_i(wsh[3:0]),
    .in_l(il), .in_r(ir), .out_l(ol), .out_r(orr), .out_valid(ov), .grain_count_o(gc));

  task axi_write(input [AW-1:0] a, input [31:0] d); begin
    @(posedge clk); AWADDR<=a; AWVALID<=1; WDATA<=d; WSTRB<=4'hF; WVALID<=1; BREADY<=1;
    while(!(AWVALID&&AWREADY&&WVALID&&WREADY)) @(posedge clk);  // hold until handshake
    @(posedge clk); AWVALID<=0; WVALID<=0;                       // write captured at prev edge
    while(!BVALID) @(posedge clk);
    @(posedge clk); BREADY<=0; end
  endtask
  task axi_read(input [AW-1:0] a, output [31:0] d); begin
    @(posedge clk); ARADDR<=a; ARVALID<=1; RREADY<=1;
    while(!(ARVALID&&ARREADY)) @(posedge clk);                   // hold until AR handshake
    @(posedge clk); ARVALID<=0;                                  // rd_en fired -> rvalid next
    while(!RVALID) @(posedge clk);
    d=RDATA;
    @(posedge clk); RREADY<=0; end
  endtask
  task push(input integer val); begin
    @(posedge clk); il<=val; ir<=val; sv<=1; @(posedge clk); sv<=0;
    wait(ov==1); @(posedge clk); end
  endtask

  integer fails=0; logic [31:0] rd; integer n,v;
  task chk(input [8*16-1:0] nm, input [31:0] got, input [31:0] exp); begin
    if(got!==exp) begin fails=fails+1; $display("  FAIL %0s got=%h exp=%h",nm,got,exp); end
    else $display("  ok   %0s = %h", nm, got); end
  endtask

  initial begin
    il=0; ir=0; rstn=0; repeat(6) @(posedge clk); rstn=1; repeat(40) @(posedge clk);

    $display("\n-- reset defaults / ID --");
    axi_read(6'h28,rd); chk("ID",      rd,32'h434C4F44);
    axi_read(6'h00,rd); chk("CTRL",    rd,32'd0);        // effect OFF by default
    axi_read(6'h04,rd); chk("POSITION",rd,32'd16000);
    axi_read(6'h08,rd); chk("SIZE",    rd,32'd2400);
    axi_read(6'h0C,rd); chk("INV_HALF",rd,32'd54);
    axi_read(6'h10,rd); chk("PITCH",   rd,32'h00010000);
    axi_read(6'h14,rd); chk("DENSITY", rd,32'd800);
    axi_read(6'h1C,rd); chk("BLEND",   rd,32'd160);

    $display("\n-- INV_HALF is HW-computed from SIZE (software never writes it) --");
    axi_read(6'h0C,rd); chk("INV_HALF default (size 2400)", rd, 32'd54);
    // change SIZE -> divider retriggers; poll STATUS[8]=busy, then read computed slope
    axi_write(6'h08,32'd600);   axi_read(6'h08,rd); chk("SIZE'", rd,32'd600);
    do axi_read(6'h24,rd); while(rd[8]); // wait recip busy clear
    axi_read(6'h0C,rd); chk("INV_HALF computed (size 600 ->218)", rd, 32'd218);
    axi_write(6'h08,32'd4096);  do axi_read(6'h24,rd); while(rd[8]);
    axi_read(6'h0C,rd); chk("INV_HALF computed (size 4096->32)", rd, 32'd32);
    // restore size for the run below
    axi_write(6'h08,32'd600);   do axi_read(6'h24,rd); while(rd[8]);
    axi_write(6'h04,32'd512);   axi_read(6'h04,rd); chk("POSITION'",rd,32'd512);
    axi_write(6'h14,32'd200);   axi_read(6'h14,rd); chk("DENSITY'", rd,32'd200);
    axi_write(6'h18,32'd64);    axi_read(6'h18,rd); chk("TEXTURE'", rd,32'd64);
    // confirm INV_HALF is read-only: writing it must NOT change the computed value
    axi_write(6'h0C,32'd9999);  axi_read(6'h0C,rd); chk("INV_HALF still computed (RO)", rd, 32'd218);

    $display("\n-- effect OFF: output must equal input (bypass) --");
    begin integer mm; mm=0;
      for(n=0;n<300;n=n+1) begin v=$rtoi(3000000.0*$sin(2.0*3.1415926*600.0*n/48000.0));
        push(v); if(ol!==v) mm=mm+1; end
      if(mm==0) $display("  ok   bypass bit-exact (300 samples)");
      else begin fails=fails+1; $display("  FAIL bypass mismatches=%0d",mm); end
    end

    $display("\n-- enable effect, run, confirm grains via STATUS --");
    axi_write(6'h00,32'd1);     // CTRL.enable = 1
    for(n=0;n<2000;n=n+1) begin v=$rtoi(4000000.0*$sin(2.0*3.1415926*600.0*n/48000.0)); push(v); end
    axi_read(6'h24,rd);
    if(rd[4:0]>0 && rd[4:0]<=8) $display("  ok   STATUS active grains = %0d", rd[4:0]);
    else begin fails=fails+1; $display("  FAIL STATUS grains=%0d",rd[4:0]); end

    $display("\n==== CSR TEST: %s (%0d failures) ====", (fails==0)?"PASS":"FAIL", fails);
    $finish;
  end
  initial begin #200_000_000; $display("TIMEOUT"); $finish; end
endmodule
