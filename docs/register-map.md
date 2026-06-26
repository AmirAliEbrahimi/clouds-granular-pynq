# Register map

AXI4-Lite slave, 32-bit registers, byte-addressed. Base address is whatever your
Vivado address editor assigns to the `audio_engine` `S_AXI` interface
(`XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR`).

| Offset | Name      | Access | Bits   | Reset      | Description                                   |
|--------|-----------|--------|--------|------------|-----------------------------------------------|
| 0x00   | CTRL      | RW     | [0]    | 0          | `enable`: 1 = granular, 0 = clean passthrough |
| 0x04   | POSITION  | RW     | [14:0] | 16000      | samples behind the write head                 |
| 0x08   | SIZE      | RW     | [15:0] | 2400       | grain length in samples; write retriggers the slope calc |
| 0x0C   | INV_HALF  | RO     | [17:0] | 54         | `65536 / (SIZE/2)`, computed in hardware      |
| 0x10   | PITCH     | RW     | [31:0] | 0x00010000 | 16.16 playback rate; unity = 0x00010000       |
| 0x14   | DENSITY   | RW     | [15:0] | 800        | samples between grain spawns (smaller = denser)|
| 0x18   | TEXTURE   | RW     | [15:0] | 2048       | grain-start jitter span (power of 2)          |
| 0x1C   | BLEND     | RW     | [8:0]  | 160        | dry/wet: 0 = dry .. 256 = full wet            |
| 0x20   | WET_SHIFT | RW     | [3:0]  | 1          | wet normalisation right-shift                 |
| 0x24   | STATUS    | RO     | [4:0],[8] | -       | [4:0] active grain count; [8] slope-calc busy |
| 0x28   | ID        | RO     | [31:0] | 0x434C4F44 | magic "CLOD",  sanity-check the base address  |

## INV_HALF is hardware-computed

The triangular-window slope is `inv_half = 65536 / (SIZE >> 1)`. Earlier revisions
made software compute and write it; now `clouds_recip` derives it from `SIZE` in
~17 cycles. **Software writes only `SIZE`.** Writes to `INV_HALF` are ignored.

`STATUS[8]` is high while the divider runs (far shorter than one 48 kHz sample,
so polling is rarely needed). To read back the computed value, read `INV_HALF`.

## Power-on behaviour

`CTRL` resets to 0, so a fresh bitstream is a clean passthrough identical to the
input. Configure the knobs, then set `CTRL.enable = 1`:

```c
*(volatile uint32_t*)(BASE + 0x04) = 16000;        // POSITION
*(volatile uint32_t*)(BASE + 0x08) = 2400;         // SIZE  (INV_HALF follows)
*(volatile uint32_t*)(BASE + 0x14) = 800;          // DENSITY
*(volatile uint32_t*)(BASE + 0x1C) = 160;          // BLEND
*(volatile uint32_t*)(BASE + 0x00) = 1;            // enable
```
