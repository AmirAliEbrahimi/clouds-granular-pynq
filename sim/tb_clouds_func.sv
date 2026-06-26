`timescale 1ns/1ps
module tb_func;
  localparam SAMPLE_W=24, S_WRITE=1, S_OUT=6;
  localparam signed [SAMPLE_W-1:0] SMAX=(1<<<(SAMPLE_W-1))-1, SMIN=-(1<<<(SAMPLE_W-1));
  logic clk=0, sv=0, en=1; logic signed [SAMPLE_W-1:0] il, ir, ol, orr; logic ov;
  logic [4:0] gc;
  always #5 clk=~clk;
  clouds_engine #(.SAMPLE_W(SAMPLE_W), .BUF_AW(12), .N_GRAINS(8)) dut (
    .clk(clk), .sample_valid(sv), .enable(en),
    .position_i(12'd512), .size_i(16'd600), .inv_half_i(18'd218),
    .pitch_i(32'h0001_0000), .density_i(16'd200), .texture_i(16'd64),
    .blend_i(9'd160), .wet_shift_i(4'd1),
    .in_l(il), .in_r(ir), .out_l(ol), .out_r(orr), .out_valid(ov), .grain_count_o(gc));
  integer spawns=0, samples=0, wet_clamps=0, cur=0, maxcc=0, j;
  real sumsq=0.0; integer peak=0;
  always @(posedge clk) begin
    if (dut.state==S_WRITE && dut.spawn_cnt==0 && dut.free_avail) spawns=spawns+1;
    if (dut.state==S_OUT) begin
      cur=0; for(j=0;j<8;j=j+1) cur=cur+dut.g_active[j];
      if(cur>maxcc) maxcc=cur;
      if(dut.wet_full>SMAX || dut.wet_full<SMIN) wet_clamps=wet_clamps+1;
    end
  end
  task push(input integer val);
    begin @(posedge clk); il<=val; ir<=val; sv<=1; @(posedge clk); sv<=0;
          wait(ov==1); @(posedge clk); end
  endtask
  integer n,v,aol; real ph;
  initial begin il=0; ir=0; repeat(4) @(posedge clk);
    for(n=0;n<6000;n=n+1) begin
      ph=2.0*3.141592653589793*1000.0*n/48000.0; v=$rtoi(4000000.0*$sin(ph));
      push(v); samples=samples+1; aol=(ol<0)?-ol:ol;
      if(aol>peak) peak=aol; sumsq=sumsq+(1.0*ol)*(1.0*ol);
    end
    $display("\n==== FUNCTIONAL SIM (register engine) ====");
    $display("output samples              : %0d", samples);
    $display("grain spawns                : %0d", spawns);
    $display("max concurrent grains       : %0d / 8", maxcc);
    $display("grain_count_o at end        : %0d", gc);
    $display("wet clamp events            : %0d", wet_clamps);
    $display("output peak |sample|        : %0d", peak);
    $display("output RMS                  : %.0f", $sqrt(sumsq/samples));
    en=0; #1; begin integer mm; mm=0;
      for(n=0;n<200;n=n+1) begin
        v=$rtoi(3000000.0*$sin(2.0*3.141592653589793*777.0*n/48000.0));
        push(v); if(ol!==v||orr!==v) mm=mm+1; end
      $display("bypass mismatches           : %0d / 200 -> %s", mm, (mm==0)?"BIT-EXACT":"BROKEN");
    end
    $finish; end
  initial begin #50_000_000; $display("TIMEOUT"); $finish; end
endmodule
