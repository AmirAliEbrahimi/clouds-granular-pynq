// -----------------------------------------------------------------------------
// clouds_recip.v  (Verilog-2001)
// Sequential reciprocal for the triangular-window slope:
//     inv_half = floor( 65536 / (size>>1) )           (== 131072/size for even size)
// ~17-cycle restoring divider; dividend is the constant 65536 (bit16).
// Triggered on each SIZE change; result is stable long before the next audio
// sample (samples are ~2048 cycles apart at 100 MHz).
// -----------------------------------------------------------------------------
module clouds_recip (
    input             clk,
    input             rstn,
    input             start,
    input      [15:0] size_in,        // grain size in samples
    output reg [17:0] inv_half,       // 65536 / (size_in>>1), clamped
    output reg        busy
);
    localparam IDLE=2'd0, RUN=2'd1, FIN=2'd2;
    reg  [1:0]  st;
    reg  [16:0] dvsr;                 // half (>=1)
    reg  [17:0] rem, quo;
    reg  [4:0]  idx;

    wire [16:0] half_w = (size_in >> 1);
    wire [17:0] rshift = (rem << 1) | ((idx == 5'd16) ? 18'd1 : 18'd0); // dividend=2^16
    wire [17:0] dsub   = {1'b0, dvsr};

    always @(posedge clk) begin
        if (!rstn) begin
            st <= IDLE; busy <= 1'b0; inv_half <= 18'd54;   // default for size=2400
        end else begin
            case (st)
            IDLE: if (start) begin
                dvsr <= (half_w == 0) ? 17'd1 : half_w;     // guard /0 (tiny grains)
                rem  <= 18'd0; quo <= 18'd0; idx <= 5'd16;
                busy <= 1'b1;  st <= RUN;
            end
            RUN: begin
                if (rshift >= dsub) begin rem <= rshift - dsub; quo[idx] <= 1'b1; end
                else                      rem <= rshift;
                if (idx == 5'd0) st <= FIN; else idx <= idx - 1'b1;
            end
            FIN: begin inv_half <= quo; busy <= 1'b0; st <= IDLE; end
            endcase
        end
    end
endmodule
