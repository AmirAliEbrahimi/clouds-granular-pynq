`timescale 1ns/1ps
// -----------------------------------------------------------------------------
// tb_iis_loopback - self-checking I2S serdes round-trip (no VHDL/GHDL needed).
// Wires iis_ser.SDATA -> iis_deser.SDATA with shared FPGA-mastered SCLK/LRCLK
// (the same clk_100/2^5, /2^11 divider audio_engine uses) and verifies the
// deserialized L/R exactly match what the serializer was given, sweeping a set
// of patterns (distinct L vs R to catch any channel swap).
// -----------------------------------------------------------------------------
module tb_iis_loopback;
  localparam N = 10;
  reg  clk = 0;  always #5 clk = ~clk;       // 100 MHz
  reg [31:0] cnt = 0;
  always @(posedge clk) cnt <= cnt + 1;
  wire SCLK  = cnt[4];                        // ~3.125 MHz
  wire LRCLK = cnt[10];                       // ~48.8 kHz

  reg [23:0] PL [0:N-1];
  reg [23:0] PR [0:N-1];
  initial begin
    PL[0]=24'h000001; PR[0]=24'h800000;
    PL[1]=24'h800000; PR[1]=24'h000001;
    PL[2]=24'h555555; PR[2]=24'hAAAAAA;
    PL[3]=24'hAAAAAA; PR[3]=24'h555555;
    PL[4]=24'h123456; PR[4]=24'h654321;
    PL[5]=24'hFEDCBA; PR[5]=24'hABCDEF;
    PL[6]=24'hFFFFFF; PR[6]=24'h000000;
    PL[7]=24'h000000; PR[7]=24'hFFFFFF;
    PL[8]=24'h0F0F0F; PR[8]=24'hF0F0F0;
    PL[9]=24'h7FFFFF; PR[9]=24'h800000;
  end

  reg [23:0] tl, tr;                          // driven to serializer
  wire sd;
  wire [23:0] dl, dr;  wire v, wv;
  iis_ser   u_ser (.CLK_100MHZ(clk), .SCLK(SCLK), .LRCLK(LRCLK), .SDATA(sd),
                   .EN(1'b1), .LDATA(tl), .RDATA(tr));
  iis_deser u_des (.CLK_100MHZ(clk), .SCLK(SCLK), .LRCLK(LRCLK), .SDATA(sd),
                   .EN(1'b1), .LDATA(dl), .RDATA(dr), .VALID(v), .WVALID(wv));

  integer idx = 0, checks = 0, fails = 0;
  initial begin tl = PL[0]; tr = PR[0]; end

  always @(posedge clk) if (v) begin
    // this frame serialized the currently-held tl/tr; it must round-trip
    checks = checks + 1;
    if (dl !== tl || dr !== tr) begin
      fails = fails + 1;
      if (fails <= 8)
        $display("  MISMATCH frame %0d: got l=%06h r=%06h  exp l=%06h r=%06h",
                 checks, dl, dr, tl, tr);
    end
    idx = (idx + 1) % N;                       // advance pattern for next frame
    tl <= PL[idx];
    tr <= PR[idx];
  end

  initial begin
    // run ~250 frames (each ~2048 clk); a frame is ~20.5 us
    #6_000_000;
    $display("\n==== I2S SERDES LOOPBACK ====");
    $display("frames checked : %0d", checks);
    $display("mismatches     : %0d", fails);
    $display("RESULT: %s", (fails==0 && checks>50) ? "PASS (ser<->deser round-trip)" : "FAIL");
    $finish;
  end
endmodule
