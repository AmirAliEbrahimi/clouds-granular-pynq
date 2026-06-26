// -----------------------------------------------------------------------------
// clouds_engine.v   (Verilog-2001, runtime-register version)
//
// Granular processor - core of Mutable Instruments "Clouds" (granular mode).
// The former compile-time knobs are now input ports, driven by an AXI-Lite CSR.
// Per-sample the live control inputs are latched into *_q shadows (at the start
// of each sample) so every sample is processed with a self-consistent set.
//
// inv_half_i is supplied by software:  inv_half = 65536 / (size/2) = 131072/size
// (avoids a hardware divider for the triangular-window slope).
//
// SAMPLE_W / BUF_AW / N_GRAINS stay parameters - they size memory/structure.
// -----------------------------------------------------------------------------
module clouds_engine #(
    parameter SAMPLE_W = 24,
    parameter BUF_AW   = 15,
    parameter N_GRAINS = 8
)(
    input                            clk,
    input                            sample_valid,
    // ---- live controls (from AXI-Lite CSR) ----
    input                            enable,
    input      [BUF_AW-1:0]          position_i,   // samples behind write head
    input      [15:0]                size_i,       // grain length (samples)
    input      [17:0]                inv_half_i,   // 131072 / size  (window slope)
    input      [31:0]                pitch_i,      // 16.16 playback rate
    input      [15:0]                density_i,    // samples between spawns
    input      [15:0]                texture_i,    // jitter span (power of 2)
    input      [8:0]                 blend_i,      // 0=dry .. 256=full wet
    input      [3:0]                 wet_shift_i,  // wet normalisation shift
    // ---- audio ----
    input      signed [SAMPLE_W-1:0] in_l,
    input      signed [SAMPLE_W-1:0] in_r,
    output reg signed [SAMPLE_W-1:0] out_l,
    output reg signed [SAMPLE_W-1:0] out_r,
    output reg                       out_valid,
    // ---- status ----
    output     [4:0]                 grain_count_o // active grains (0..N_GRAINS)
);
    function integer clogb2;
        input integer value; integer v;
        begin v=value-1; clogb2=0; while(v>0) begin v=v>>1; clogb2=clogb2+1; end end
    endfunction

    localparam DEPTH = (1 << BUF_AW);
    localparam MASK  = DEPTH - 1;
    localparam GI_W  = clogb2(N_GRAINS + 1);
    localparam FI_W  = clogb2(N_GRAINS);
    localparam signed [SAMPLE_W-1:0] SMAX =  (1 <<< (SAMPLE_W-1)) - 1;
    localparam signed [SAMPLE_W-1:0] SMIN = -(1 <<< (SAMPLE_W-1));

    localparam S_IDLE=4'd0, S_WRITE=4'd1, S_ADDR=4'd2, S_RD=4'd3,
               S_MUL=4'd4, S_ACC=4'd5, S_OUT1=4'd6, S_OUT2=4'd7,
               S_OUT3=4'd8, S_OUT4=4'd9;

    // ---- circular buffer (output-registered BRAM) ----
    reg signed [SAMPLE_W-1:0] gmem [0:DEPTH-1];
    reg                       wr_en;
    reg  [BUF_AW-1:0]         wr_addr, rd_addr;
    reg  signed [SAMPLE_W-1:0] wr_data, rd_data;
    always @(posedge clk) begin
        if (wr_en) gmem[wr_addr] <= wr_data;
        rd_data <= gmem[rd_addr];
    end

    reg [BUF_AW-1:0] write_ptr = 0;

    // ---- grain pool ----
    reg              g_active [0:N_GRAINS-1];
    reg [BUF_AW-1:0] g_base   [0:N_GRAINS-1];
    reg [31:0]       g_phase  [0:N_GRAINS-1];
    reg [15:0]       g_pos    [0:N_GRAINS-1];

    // ---- latched (shadow) controls, stable for the whole sample ----
    reg              enable_q;
    reg [BUF_AW-1:0] position_q;
    reg [15:0]       size_q, half_q, density_q, texture_q;
    reg [17:0]       inv_half_q;
    reg [31:0]       pitch_q;
    reg [8:0]        blend_q;
    reg [3:0]        wet_shift_q;

    reg  [15:0] spawn_cnt = 0;
    reg  [15:0] lfsr      = 16'hACE1;
    wire [15:0] jitter    = lfsr & (texture_q - 16'd1);

    // first-free-grain priority encoder (lowest free index wins)
    reg             free_avail;
    reg [FI_W-1:0]  free_idx;
    integer k;
    always @(*) begin
        free_avail = 1'b0;
        free_idx   = 0;
        for (k = N_GRAINS-1; k >= 0; k = k - 1)
            if (!g_active[k]) begin free_idx = k; free_avail = 1'b1; end
    end

    integer i;
    reg [3:0]          state = S_IDLE;
    reg signed [SAMPLE_W-1:0] in_l_q, in_r_q;
    reg signed [47:0]  acc;
    reg [GI_W-1:0]     gi;
    reg [16:0]         win_frac;
    reg signed [47:0]  prod;                 // registered DSP product (timing)
    reg signed [SAMPLE_W-1:0] wet_s_r;       // registered, clamped wet (timing)
    reg signed [25:0]  mdiff_l, mdiff_r;     // registered DSP input  (wet-dry, pre-add)
    reg signed [47:0]  mprod_l, mprod_r;     // registered DSP output (diff*blend)
    reg [GI_W-1:0]     grain_count = 0;
    assign grain_count_o = {{(5-GI_W){1'b0}}, grain_count};

    wire signed [47:0] wet_full = acc >>> wet_shift_q;

    function signed [SAMPLE_W-1:0] clamp24;
        input signed [47:0] x;
        begin
            if      (x > SMAX) clamp24 = SMAX;
            else if (x < SMIN) clamp24 = SMIN;
            else               clamp24 = x[SAMPLE_W-1:0];
        end
    endfunction

    always @(posedge clk) begin
        wr_en     <= 1'b0;
        out_valid <= 1'b0;

        case (state)
        S_IDLE: if (sample_valid) begin
            // latch a self-consistent control set for this sample
            enable_q    <= enable;
            position_q  <= position_i;
            size_q      <= size_i;
            half_q      <= size_i >> 1;
            inv_half_q  <= inv_half_i;
            pitch_q     <= pitch_i;
            density_q   <= density_i;
            texture_q   <= texture_i;
            blend_q     <= blend_i;
            wet_shift_q <= wet_shift_i;

            in_l_q  <= in_l;
            in_r_q  <= in_r;
            wr_data <= (in_l >>> 1) + (in_r >>> 1);
            wr_addr <= write_ptr;
            wr_en   <= 1'b1;
            lfsr    <= {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
            state   <= S_WRITE;
        end

        S_WRITE: begin
            write_ptr <= write_ptr + 1'b1;
            if (spawn_cnt == 0) begin
                spawn_cnt <= density_q;
                if (free_avail) begin
                    g_active[free_idx] <= 1'b1;
                    g_base[free_idx]   <= (write_ptr - position_q - jitter) & MASK;
                    g_phase[free_idx]  <= 32'd0;
                    g_pos[free_idx]    <= 16'd0;
                    grain_count        <= grain_count + 1'b1;
                end
            end else begin
                spawn_cnt <= spawn_cnt - 1'b1;
            end
            acc   <= 48'sd0;
            gi    <= 0;
            state <= S_ADDR;
        end

        S_ADDR: begin
            if (gi == N_GRAINS) begin
                state <= S_OUT1;
            end else if (g_active[gi]) begin
                rd_addr  <= (g_base[gi] + g_phase[gi][31:16]) & MASK;
                win_frac <= (g_pos[gi] < half_q)
                            ?  (g_pos[gi]            * inv_half_q)
                            : ((size_q - g_pos[gi])  * inv_half_q);
                state <= S_RD;
            end else begin
                gi <= gi + 1'b1;
            end
        end

        S_RD: state <= S_MUL;     // 2-cycle read latency (addr reg + data reg)

        // registered DSP multiply (fully registered in/out) + advance this grain
        S_MUL: begin
            prod        <= $signed(rd_data) * $signed({1'b0, win_frac});
            g_phase[gi] <= g_phase[gi] + pitch_q;
            if (g_pos[gi] + 1 >= size_q) begin
                g_active[gi] <= 1'b0;
                grain_count  <= grain_count - 1'b1;
            end
            g_pos[gi] <= g_pos[gi] + 1'b1;
            state <= S_ACC;
        end

        // isolated 48-bit accumulate (no multiply on this path)
        S_ACC: begin
            acc   <= acc + (prod >>> 16);
            gi    <= gi + 1'b1;
            state <= S_ADDR;
        end

        // out stage 1: 48-bit variable shift + clamp -> register
        S_OUT1: begin
            wet_s_r <= clamp24(wet_full);
            state   <= S_OUT2;
        end

        // out stage 2: pre-add (wet-dry) -> register  (DSP input register)
        S_OUT2: begin
            mdiff_l <= $signed(wet_s_r) - $signed(in_l_q);
            mdiff_r <= $signed(wet_s_r) - $signed(in_r_q);
            state   <= S_OUT3;
        end

        // out stage 3: multiply by blend -> register   (DSP output register)
        S_OUT3: begin
            mprod_l <= mdiff_l * $signed({1'b0, blend_q});
            mprod_r <= mdiff_r * $signed({1'b0, blend_q});
            state   <= S_OUT4;
        end

        // out stage 4: post-add (+dry) + clamp -> output register
        S_OUT4: begin
            out_l     <= enable_q ? clamp24($signed(in_l_q) + (mprod_l >>> 8)) : in_l_q;
            out_r     <= enable_q ? clamp24($signed(in_r_q) + (mprod_r >>> 8)) : in_r_q;
            out_valid <= 1'b1;
            state     <= S_IDLE;
        end
        endcase
    end

    initial begin
        for (i = 0; i < N_GRAINS; i = i + 1) g_active[i] = 1'b0;
    end
endmodule
