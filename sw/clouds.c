// -----------------------------------------------------------------------------
// clouds.c - bare-metal driver for the Clouds granular AXI4-Lite peripheral
// -----------------------------------------------------------------------------
#include "clouds.h"
#include <math.h>

static inline void     reg_wr(uintptr_t a, uint32_t v) { *(volatile uint32_t *)a = v; }
static inline uint32_t reg_rd(uintptr_t a)             { return *(volatile uint32_t *)a; }

void clouds_init(clouds_t *c, uintptr_t base) { c->base = base; }

uint32_t clouds_id(clouds_t *c) { return reg_rd(c->base + CLOUDS_ID); }

void clouds_enable(clouds_t *c, int on) {
    uint32_t v = reg_rd(c->base + CLOUDS_CTRL);
    if (on) v |=  CLOUDS_CTRL_ENABLE;
    else    v &= ~CLOUDS_CTRL_ENABLE;
    reg_wr(c->base + CLOUDS_CTRL, v);
}

void clouds_set_position(clouds_t *c, uint32_t s)  { reg_wr(c->base + CLOUDS_POSITION, s); }

// Writing SIZE retriggers the hardware reciprocal; INV_HALF follows automatically.
void clouds_set_size(clouds_t *c, uint32_t s)      { reg_wr(c->base + CLOUDS_SIZE, s); }

void clouds_set_pitch_q16(clouds_t *c, uint32_t q) { reg_wr(c->base + CLOUDS_PITCH, q); }

void clouds_set_pitch_semitones(clouds_t *c, float semis) {
    float ratio = powf(2.0f, semis / 12.0f);
    uint32_t q  = (uint32_t)(ratio * 65536.0f + 0.5f);
    clouds_set_pitch_q16(c, q);
}

void clouds_set_density(clouds_t *c, uint32_t s)   { reg_wr(c->base + CLOUDS_DENSITY, s); }
void clouds_set_texture(clouds_t *c, uint32_t s)   { reg_wr(c->base + CLOUDS_TEXTURE, s); }
void clouds_set_blend(clouds_t *c, uint32_t b)     { reg_wr(c->base + CLOUDS_BLEND, b); }
void clouds_set_wet_shift(clouds_t *c, uint32_t sh){ reg_wr(c->base + CLOUDS_WET_SHIFT, sh); }

uint32_t clouds_status(clouds_t *c)   { return reg_rd(c->base + CLOUDS_STATUS); }
int      clouds_grains(clouds_t *c)   { return (int)CLOUDS_STATUS_GRAINS(clouds_status(c)); }
uint32_t clouds_inv_half(clouds_t *c) { return reg_rd(c->base + CLOUDS_INV_HALF); }

void clouds_wait_recip(clouds_t *c) {
    while (clouds_status(c) & CLOUDS_STATUS_BUSY) { /* ~17 cycles, returns fast */ }
}
