# Constraints

`audio.xdc` pins the ADAU1761 codec interface for the TUL PYNQ-Z2
(XC7Z020-clg400). Port names match the block-design wrapper produced by
`bd/soc_bd.tcl`.

The I2S `BCLK`/`LRCLK` are derived by dividing the 100 MHz fabric clock inside
`audio_engine`, so they are plain logic outputs. **Do not** add
`create_generated_clock` on them. The codec link runs at ~3.1 MHz BCLK /
~48.8 kHz LRCLK, well within the I/O timing budget, so no extra
input/output-delay constraints are required.

`scripts/build_project.tcl` adds this file to the project automatically.
