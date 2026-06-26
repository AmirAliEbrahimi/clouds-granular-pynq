# clouds-granular-pynq

A **granular audio processor** for the PYNQ-Z2 (Xilinx Zynq-7000, XC7Z020) with
the on-board ADAU1761 codec. It records line-in audio into a circular buffer and
replays a pool of overlapping, windowed *grains* with live control over position,
size, pitch, density, texture, and dry/wet mix, inspired by the granular mode of Mutable Instruments *Clouds*.

Everything synthesizable is **strict Verilog-2001**. Every block is
simulation-verified, and the design **closes timing at ~ +0.66 ns WNS @ 100 MHz**
on the XC7Z020.

> Status: v1.0.0. Mono granular core with stereo dry path. Stereo grains, reverb,
> and the spectral mode are not implemented (see [Roadmap](#roadmap)).

## Signal flow

```
                         AXI4-Lite (PS GP)
                               │
                        clouds_csr_axil ──► clouds_recip (SIZE → window slope)
                               │ knobs
  ADAU1761 ─► iis_deser ─► clouds_engine ─► iis_ser ─► ADAU1761
   (ADC)      (RX)          (granular)      (TX)       (DAC)
                         all in one 100 MHz fabric clock domain
```

The FPGA masters BCLK/LRCLK (codec is the subordinate), so deserializer, engine,
CSR, and serializer share a single clock.

## Build (Vivado)

One command from the repo root creates the whole project,
block design, and wrapper:

```sh
vivado -mode batch -source scripts/build_project.tcl
```
The block design wires `audio_engine` to a
PS GP AXI master (via SmartConnect), shares `FCLK_CLK0` (100 MHz) across
`clk_100`/`S_AXI_ACLK`, and brings the codec pins out to `constraints/audio.xdc`.
The design powers up in clean passthrough (`CTRL.enable = 0`); software turns the
effect on.

## Software

`sw/clouds` is a small bare-metal driver (Vitis / standalone BSP) plus an
interactive console.

```c
clouds_t cl;   clouds_init(&cl, XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR);
clouds_ui_t ui; clouds_ui_init(&ui, &cl);   // pushes defaults, prints the menu
clouds_ui_run(&ui);                          // tweak by ear over the terminal
```

Console keys (QWERTY inc/dec pairs):

```
 space  on/off      q/a position   w/s size     e/d density
 r/f texture (x2//2) t/g blend      y/h wet_shift u/j pitch (semitone)
 p print state       ? menu
```

## Tuning notes

- **Wet headroom.** Expected overlap is `ceil(SIZE/DENSITY)`. `WET_SHIFT`
  divides the summed grains; raise it if you crank density and hear clipping.
- **`gmem` should map to block RAM.** It's the canonical simple-dual-port
  template; if your tool infers distributed RAM on the 32768-deep array, add
  `(* ram_style = "block" *)` to the `gmem` declaration in `clouds_engine.v`.

## Roadmap

- Stereo grains (independent L/R grain positions for width)
- Optional diffusion / reverb tail
- Spectral (FFT) mode
- AXI-Stream variant for DMA-based capture/playback

## Acknowledgments

- I2S serdes converted from **wady101/PYNQ_Z2-Audio** (MIT); originally Digilent
  reference designs. See [`NOTICE`](NOTICE).
- Granular concept inspired by **Mutable Instruments Clouds** (Emilie Gillet, MIT).

## License

MIT, see [`LICENSE`](LICENSE).
