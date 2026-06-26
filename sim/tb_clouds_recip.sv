`timescale 1ns/1ps
module tb_recip;
  logic clk=0, rstn=0, start=0; logic [15:0] sz; logic [17:0] iv; logic busy;
  always #5 clk=~clk;
  clouds_recip dut(.clk(clk), .rstn(rstn), .start(start), .size_in(sz), .inv_half(iv), .busy(busy));
  integer fails=0;
  task run(input [15:0] s, input [17:0] exp); begin
    @(posedge clk); sz<=s; start<=1; @(posedge clk); start<=0;
    wait(busy==1'b1); wait(busy==1'b0); @(posedge clk);
    if(iv!==exp) begin fails=fails+1; $display("  FAIL size=%0d half=%0d inv=%0d exp=%0d",s,s>>1,iv,exp); end
    else $display("  ok   size=%0d -> inv_half=%0d", s, iv);
  end endtask
  initial begin
    rstn=0; repeat(4) @(posedge clk); rstn=1; repeat(2) @(posedge clk);
    run(2400, 18'd54);    // 65536/1200
    run(600,  18'd218);   // 65536/300
    run(4096, 18'd32);    // 65536/2048
    run(1000, 18'd131);   // 65536/500 = 131.07
    run(40,   18'd3276);  // 65536/20
    run(2,    18'd65536); // 65536/1
    $display("\n==== RECIP TEST: %s (%0d fails) ====", (fails==0)?"PASS":"FAIL", fails);
    $finish;
  end
  initial begin #1_000_000; $display("TIMEOUT"); $finish; end
endmodule
