// -----------------------------------------------------------------------------
// clouds.h - bare-metal driver for the Clouds granular AXI4-Lite peripheral
//            (Zynq-7000 / PYNQ-Z2, Vitis). Single 32-bit register window.
//
// Usage:
//   clouds_t cl;
//   clouds_init(&cl, XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR);
//   if (clouds_id(&cl) != CLOUDS_ID_MAGIC) { /* wrong base / not mapped */ }
//   clouds_set_position(&cl, 16000);
//   clouds_set_size    (&cl, 2400);   // window slope (INV_HALF) computed in HW
//   clouds_set_density (&cl, 800);
//   clouds_set_blend   (&cl, 160);    // 0..256 wet
//   clouds_set_pitch_semitones(&cl, +7.0f);
//   clouds_enable      (&cl, 1);      // turn the effect on
// -----------------------------------------------------------------------------
#ifndef CLOUDS_H
#define CLOUDS_H
#include <stdint.h>

// ---- register offsets (bytes) ----
#define CLOUDS_CTRL        0x00u   // RW  [0] enable
#define CLOUDS_POSITION    0x04u   // RW  samples behind write head
#define CLOUDS_SIZE        0x08u   // RW  grain length (samples); retriggers slope calc
#define CLOUDS_INV_HALF    0x0Cu   // RO  65536/(size/2), hardware-computed
#define CLOUDS_PITCH       0x10u   // RW  16.16 playback rate (unity = 0x00010000)
#define CLOUDS_DENSITY     0x14u   // RW  samples between grain spawns
#define CLOUDS_TEXTURE     0x18u   // RW  jitter span (power of 2)
#define CLOUDS_BLEND       0x1Cu   // RW  0 = dry .. 256 = full wet
#define CLOUDS_WET_SHIFT   0x20u   // RW  wet normalisation shift
#define CLOUDS_STATUS      0x24u   // RO  [4:0] active grains, [8] slope-calc busy
#define CLOUDS_ID          0x28u   // RO  0x434C4F44 ("CLOD")

#define CLOUDS_ID_MAGIC    0x434C4F44u

// ---- CTRL bits ----
#define CLOUDS_CTRL_ENABLE (1u << 0)

// ---- STATUS fields ----
#define CLOUDS_STATUS_GRAINS(s) ((s) & 0x1Fu)
#define CLOUDS_STATUS_BUSY      (1u << 8)

// ---- PITCH helpers (16.16) ----
#define CLOUDS_PITCH_UNITY      0x00010000u

typedef struct { uintptr_t base; } clouds_t;

void     clouds_init(clouds_t *c, uintptr_t base);
uint32_t clouds_id(clouds_t *c);

void     clouds_enable(clouds_t *c, int on);
void     clouds_set_position(clouds_t *c, uint32_t samples);
void     clouds_set_size(clouds_t *c, uint32_t samples);        // HW recomputes window slope
void     clouds_set_pitch_q16(clouds_t *c, uint32_t q16_16);    // raw 16.16
void     clouds_set_pitch_semitones(clouds_t *c, float semis);  // needs -lm
void     clouds_set_density(clouds_t *c, uint32_t samples);
void     clouds_set_texture(clouds_t *c, uint32_t span_pow2);
void     clouds_set_blend(clouds_t *c, uint32_t wet_0_256);
void     clouds_set_wet_shift(clouds_t *c, uint32_t shift);

uint32_t clouds_status(clouds_t *c);
int      clouds_grains(clouds_t *c);
uint32_t clouds_inv_half(clouds_t *c);     // read back computed slope (debug)
void     clouds_wait_recip(clouds_t *c);   // spin until slope calc done (~17 cyc)

#endif // CLOUDS_H
