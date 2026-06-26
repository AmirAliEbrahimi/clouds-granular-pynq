// -----------------------------------------------------------------------------
// iis_ser.v  (Verilog-2001) - faithful translation of wady101 iis_ser.vhd
// I2S transmitter: loads L+R at the left-frame edge, shifts out MSB-first on
// SCLK falling edges. bit_cntr counts to 25 (24 data bits + trailing 0).
// -----------------------------------------------------------------------------
module iis_ser (
    input             CLK_100MHZ,
    input             SCLK,
    input             LRCLK,
    output            SDATA,
    input             EN,
    input      [23:0] LDATA,
    input      [23:0] RDATA
);
    localparam [4:0] BIT_CNTR_MAX = 5'd25;   // 24 data bits + 1 (drive 0 after)
    localparam [2:0] RESET=3'd0, WAIT_LEFT=3'd1, WRITE_LEFT=3'd2,
                     WAIT_RIGHT=3'd3, WRITE_RIGHT=3'd4;

    reg        sclk_d1  = 1'b0;
    reg        lrclk_d1 = 1'b0;
    reg [4:0]  bit_cntr = 5'd0;
    reg [23:0] ldata_reg = 24'd0;
    reg [23:0] rdata_reg = 24'd0;
    reg        sdata_reg = 1'b0;
    reg [2:0]  iis_state = RESET;

    always @(posedge CLK_100MHZ) begin
        sclk_d1  <= SCLK;
        lrclk_d1 <= LRCLK;
    end

    wire start_left  =  lrclk_d1 & ~LRCLK;   // LRCLK falling edge
    wire start_right = ~lrclk_d1 &  LRCLK;   // LRCLK rising edge
    wire write_bit   =  sclk_d1  & ~SCLK;    // SCLK falling edge

    // next-state logic
    always @(posedge CLK_100MHZ) begin
        case (iis_state)
            RESET:       if (EN) iis_state <= WAIT_LEFT;
            WAIT_LEFT:   if (!EN) iis_state <= RESET; else if (start_left)            iis_state <= WRITE_LEFT;
            WRITE_LEFT:  if (!EN) iis_state <= RESET; else if (bit_cntr==BIT_CNTR_MAX) iis_state <= WAIT_RIGHT;
            WAIT_RIGHT:  if (!EN) iis_state <= RESET; else if (start_right)           iis_state <= WRITE_RIGHT;
            WRITE_RIGHT: if (!EN) iis_state <= RESET; else if (bit_cntr==BIT_CNTR_MAX) iis_state <= WAIT_LEFT;
            default:     iis_state <= RESET;
        endcase
    end

    // bit counter
    always @(posedge CLK_100MHZ) begin
        if (iis_state==WRITE_RIGHT || iis_state==WRITE_LEFT) begin
            if (write_bit) bit_cntr <= bit_cntr + 5'd1;
        end else begin
            bit_cntr <= 5'd0;
        end
    end

    // data shift registers (load at left frame, shift MSB-first)
    always @(posedge CLK_100MHZ) begin
        if (iis_state==RESET) begin
            ldata_reg <= 24'd0;
            rdata_reg <= 24'd0;
        end else if (iis_state==WAIT_LEFT && start_left) begin
            ldata_reg <= LDATA;
            rdata_reg <= RDATA;
        end else begin
            if (iis_state==WRITE_LEFT  && write_bit) ldata_reg <= {ldata_reg[22:0], 1'b0};
            if (iis_state==WRITE_RIGHT && write_bit) rdata_reg <= {rdata_reg[22:0], 1'b0};
        end
    end

    // serial output bit
    always @(posedge CLK_100MHZ) begin
        if (iis_state==RESET)                              sdata_reg <= 1'b0;
        else if (iis_state==WRITE_LEFT  && write_bit)      sdata_reg <= ldata_reg[23];
        else if (iis_state==WRITE_RIGHT && write_bit)      sdata_reg <= rdata_reg[23];
    end

    assign SDATA = sdata_reg;
endmodule
