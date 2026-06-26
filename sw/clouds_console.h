// -----------------------------------------------------------------------------
// clouds_console.h - interactive UART console for live Clouds tweaking.
// Uses the PS UART that already backs xil_printf/stdout (no extra setup).
//
//   clouds_t cl;       clouds_init(&cl, XPAR_AUDIO_ENGINE_0_S_AXI_BASEADDR);
//   clouds_ui_t ui;    clouds_ui_init(&ui, &cl);     // syncs HW + prints menu
//   clouds_ui_run(&ui);                              // blocking key loop
//   // ...or poll it inside your own loop:  while (1) { clouds_ui_poll(&ui); ... }
// -----------------------------------------------------------------------------
#ifndef CLOUDS_CONSOLE_H
#define CLOUDS_CONSOLE_H
#include "clouds.h"

typedef struct {
    clouds_t *cl;
    int position;
    int size;
    int density;
    int texture;
    int blend;
    int wet_shift;
    int pitch_semi;   // semitones, -24..+24
    int enabled;
} clouds_ui_t;

void clouds_ui_init (clouds_ui_t *u, clouds_t *cl); // push defaults, print help+state
void clouds_ui_help (void);
void clouds_ui_print(clouds_ui_t *u);               // one-line current state
int  clouds_ui_poll (clouds_ui_t *u);               // handle pending keys, non-blocking
void clouds_ui_run  (clouds_ui_t *u);               // blocking key loop (never returns)

#endif // CLOUDS_CONSOLE_H
