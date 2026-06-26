// -----------------------------------------------------------------------------
// iis_deser.v  (Verilog-2001) - faithful translation of wady101 iis_deser.vhd
// I2S receiver: FPGA-master timing (SCLK/LRCLK are logic inputs, sampled in the
// CLK_100MHZ domain). Skips the I2S 1-bit delay, shifts 24 bits MSB-first.
// VALID pulses at end of the right word; WVALID pulses at end of each word.
// -----------------------------------------------------------------------------
module iis_deser (
    input             CLK_100MHZ,
    input             SCLK,
    input             LRCLK,
    input             SDATA,
    input             EN,
    output     [23:0] LDATA,
    output     [23:0] RDATA,
    output            VALID,
    output            WVALID
);
    localparam [4:0] BIT_CNTR_MAX = 5'd24;
    localparam [2:0] RESET=3'd0, WAIT_LEFT=3'd1, SKIP_LEFT=3'd2, READ_LEFT=3'd3,
                     WAIT_RIGHT=3'd4, SKIP_RIGHT=3'd5, READ_RIGHT=3'd6;

    reg        sclk_d1  = 1'b0;
    reg        lrclk_d1 = 1'b0;
    reg [4:0]  bit_cntr = 5'd0;
    reg [23:0] ldata_reg = 24'd0;
    reg [23:0] rdata_reg = 24'd0;
    reg [2:0]  iis_state = RESET;

    always @(posedge CLK_100MHZ) begin
        sclk_d1  <= SCLK;
        lrclk_d1 <= LRCLK;
    end

    wire start_left  =  lrclk_d1 & ~LRCLK;   // LRCLK falling edge
    wire start_right = ~lrclk_d1 &  LRCLK;   // LRCLK rising edge
    wire bit_rdy     = ~sclk_d1  &  SCLK;    // SCLK rising edge

    // next-state logic
    always @(posedge CLK_100MHZ) begin
        case (iis_state)
            RESET:      if (EN) iis_state <= WAIT_LEFT;
            WAIT_LEFT:  if (!EN) iis_state <= RESET; else if (start_left)              iis_state <= SKIP_LEFT;
            SKIP_LEFT:  if (!EN) iis_state <= RESET; else if (bit_rdy)                  iis_state <= READ_LEFT;
            READ_LEFT:  if (!EN) iis_state <= RESET; else if (bit_cntr==BIT_CNTR_MAX)   iis_state <= WAIT_RIGHT;
            WAIT_RIGHT: if (!EN) iis_state <= RESET; else if (start_right)              iis_state <= SKIP_RIGHT;
            SKIP_RIGHT: if (!EN) iis_state <= RESET; else if (bit_rdy)                  iis_state <= READ_RIGHT;
            READ_RIGHT: if (!EN) iis_state <= RESET; else if (bit_cntr==BIT_CNTR_MAX)   iis_state <= WAIT_LEFT;
            default:    iis_state <= RESET;
        endcase
    end

    // bit counter
    always @(posedge CLK_100MHZ) begin
        if (iis_state==READ_RIGHT || iis_state==READ_LEFT) begin
            if (bit_rdy) bit_cntr <= bit_cntr + 5'd1;
        end else begin
            bit_cntr <= 5'd0;
        end
    end

    // data shift registers (MSB-first)
    always @(posedge CLK_100MHZ) begin
        if (iis_state==RESET) begin
            ldata_reg <= 24'd0;
            rdata_reg <= 24'd0;
        end else begin
            if (iis_state==READ_LEFT  && bit_rdy) ldata_reg <= {ldata_reg[22:0], SDATA};
            if (iis_state==READ_RIGHT && bit_rdy) rdata_reg <= {rdata_reg[22:0], SDATA};
        end
    end

    assign VALID  = (iis_state==READ_RIGHT && bit_cntr==BIT_CNTR_MAX);
    assign WVALID = ((iis_state==READ_RIGHT && bit_cntr==BIT_CNTR_MAX) ||
                     (iis_state==READ_LEFT  && bit_cntr==BIT_CNTR_MAX));
    assign LDATA  = ldata_reg;
    assign RDATA  = rdata_reg;
endmodule
