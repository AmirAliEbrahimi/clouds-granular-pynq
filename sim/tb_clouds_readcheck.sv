`timescale 1ns/1ps
module tb_readcheck;
  localparam SAMPLE_W=24, BUF_AW=8, DEPTH=(1<<BUF_AW);
  localparam S_ACC = 4; // now S_MUL (cycle rd_data is consumed)
  logic clk=0, sv=0; logic signed [SAMPLE_W-1:0] il, ir, ol, orr; logic ov;
  logic [4:0] gc;
  always #5 clk=~clk;
  clouds_engine #(.SAMPLE_W(SAMPLE_W), .BUF_AW(BUF_AW), .N_GRAINS(4)) dut (
    .clk(clk), .sample_valid(sv), .enable(1'b1),
    .position_i(8'd64), .size_i(16'd40), .inv_half_i(18'd3276),
    .pitch_i(32'h0001_0000), .density_i(16'd12), .texture_i(16'd1),
    .blend_i(9'd160), .wet_shift_i(4'd1),
    .in_l(il), .in_r(ir), .out_l(ol), .out_r(orr), .out_valid(ov), .grain_count_o(gc));
  logic signed [SAMPLE_W-1:0] ref_mem [0:DEPTH-1];
  always @(posedge clk) if (dut.wr_en) ref_mem[dut.wr_addr] <= dut.wr_data;
  integer acc_checks=0, mism=0; logic signed [SAMPLE_W-1:0] expected;
  always @(posedge clk) if (dut.state==S_ACC) begin
    acc_checks=acc_checks+1; expected=ref_mem[dut.rd_addr];
    if (dut.rd_data!==expected) mism=mism+1;
  end
  task push(input integer val);
    begin @(posedge clk); il<=val; ir<=val; sv<=1; @(posedge clk); sv<=0;
          wait(ov==1); @(posedge clk); end
  endtask
  integer k;
  initial begin il=0; ir=0; repeat(4) @(posedge clk);
    for(k=1;k<=1500;k=k+1) push(2*k);
    $display("\n==== READ-PATH CHECK (register engine) ====");
    $display("S_ACC accumulations checked : %0d", acc_checks);
    $display("buffer-word mismatches      : %0d", mism);
    $display("RESULT: %s", (mism==0)?"read path OK":"BROKEN");
    $finish; end
  initial begin #5_000_000; $display("TIMEOUT"); $finish; end
endmodule
