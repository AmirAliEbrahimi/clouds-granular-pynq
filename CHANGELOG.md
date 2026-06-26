# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [1.0.0] - 2026-06-23
### Added
- Granular `clouds_engine` (Verilog-2001): circular buffer, 8-grain pool,
  triangular-windowed playback, position/size/pitch/density/texture/dry-wet.
- `clouds_csr_axil` AXI4-Lite register file with all knobs as live registers.
- `clouds_recip` hardware reciprocal so software writes only `SIZE`
  (window slope derived in hardware).
- `audio_engine` top splicing the engine into the I2S RX->TX path.
- `iis_deser` / `iis_ser` I2S SerDes.
- Bare-metal driver (`sw/clouds`) and interactive PS-UART console.
- Hardware build flow: `constraints/audio.xdc`, `bd/soc_bd.tcl`, and
  `scripts/build_project.tcl`

### Verified
- Read path, granular function, reciprocal, and AXI CSR all self-checking.
- Timing closes at ~ +0.66 ns WNS @ 100 MHz on XC7Z020 (post-pipelining).
