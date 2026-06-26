# Architecture

## Clock domain

The FPGA masters the I2S clocks: `audio_engine` divides `clk_100`
(`FCLK_CLK0`) to make `sclk = clk_cntr[4]` and `lrclk = clk_cntr[10]`
(≈48.8 kHz frame). The codec is the subordinate. Deserializer, granular engine,
AXI CSR, reciprocal, and serializer all run on `clk_100`.

## Granular engine

A per-sample sequential FSM with one shared multiplier path and one buffer read
port. There are ~2048 clocks per audio sample, of which the engine uses ~40, so
the datapath is pipelined freely for timing.

### Buffer

`gmem` is a 32768x24 circular buffer (`BUF_AW = 15`, ~0.68 s at 48 kHz),
written once per sample with the mono sum of L+R. Inferred as a simple
dual-port block RAM with a registered read (`rd_data <= gmem[rd_addr]`).

### Grain pool

Up to `N_GRAINS = 8` grains. A grain stores a base address, a 16.16 read phase
(for pitch), and a position counter. A spawn scheduler fires a new grain every
`DENSITY` samples into the first free slot, at `POSITION` samples behind the
write head plus an LFSR `TEXTURE` jitter.

### Per-grain FSM

```
S_IDLE  ─ latch controls, write buffer
S_WRITE ─ advance write ptr, maybe spawn a grain
  ┌────────────────────── for each active grain ──────────────────────┐
S_ADDR  ─ issue rd_addr, compute triangular window slope (registered)
S_RD    ─ wait (registered addr + registered BRAM output = 2-cycle read)
S_MUL   ─ prod <= rd_data * window     (registered DSP product)
S_ACC   ─ acc  <= acc + (prod >>> 16)  (isolated 48-bit accumulate)
  └────────────────────────────────────────────────────────────────────┘
S_OUT1  ─ wet  = clamp(acc >>> WET_SHIFT)     (48-bit barrel shift)
S_OUT2  ─ diff = wet - dry                    (registered DSP input/pre-add)
S_OUT3  ─ prod = diff * BLEND                 (registered DSP output)
S_OUT4  ─ out  = clamp(dry + (prod >>> 8))    (post-add + clamp)
```

The two-cycle read latency (`S_ADDR → S_RD → S_MUL`) is deliberate: both the
address and the BRAM output are registered. Reading one cycle earlier made every
grain accumulate the previous request's word which is caught by `tb_clouds_readcheck`.

### Timing

All four multipliers (window slope, grain MAC, and the dry/wet mix) have
registered inputs and a registered output, so each maps to a single DSP48 with
short surrounding logic. After this pipelining the design closes at
**~ +0.66 ns WNS @ 100 MHz** on the XC7Z020.
## Window slope reciprocal

`clouds_recip` is a ~17-cycle restoring divider computing
`inv_half = floor(65536 / (size >> 1))`. It is retriggered on each `SIZE`
register write (and once at reset for the default), so software never computes
the slope. Result feeds the engine's window multiply.

## I2S serdes

`iis_deser` and `iis_ser` are faithful Verilog-2001 conversions of the ADAU1761
IP VHDL from wady101/PYNQ_Z2-Audio. They sample `SCLK`/`LRCLK` as logic in the
`clk_100` domain (edge-detected), shift 24 bits MSB-first, and implement the
standard I2S one-bit delay. The deserializer's `VALID` is a combinational decode
that pulses at the end of the right word; `audio_engine` rising-edge-detects
it into a clean one-cycle `sample_valid` for the engine.