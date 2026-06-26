// -----------------------------------------------------------------------------
// clouds_console.c - interactive UART console for live Clouds tweaking.
// -----------------------------------------------------------------------------
#include "clouds_console.h"
#include "xparameters.h"
#include "xuartps_hw.h"     // low-level RX poll on the stdout UART; no driver instance

// ---- UART glue (the PS UART is already initialised for xil_printf) ----
static int  uart_avail(void) { return XUartPs_IsReceiveData(STDIN_BASEADDRESS); }
static char uart_getc (void) { return (char)XUartPs_RecvByte(STDIN_BASEADDRESS); }

// ---- limits / steps ----
#define CL_POS_MIN 0
#define CL_POS_MAX 32000
#define CL_POS_STEP 500
#define CL_SIZE_MIN 64
#define CL_SIZE_MAX 16000
#define CL_SIZE_STEP 100
#define CL_DEN_MIN 50
#define CL_DEN_MAX 8000
#define CL_DEN_STEP 100
#define CL_TEX_MIN 1
#define CL_TEX_MAX 8192
#define CL_BLEND_STEP 16
#define CL_WS_MIN 0
#define CL_WS_MAX 8
#define CL_SEMI_MIN -24
#define CL_SEMI_MAX 24

static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

void clouds_ui_help(void) {
    xil_printf("\r\n=============== Clouds live control ===============\r\n");
    xil_printf("  space : effect on/off (bypass)\r\n");
    xil_printf("  q / a : position   + / -   (%d samples)\r\n", CL_POS_STEP);
    xil_printf("  w / s : size       + / -   (%d samples, slope auto)\r\n", CL_SIZE_STEP);
    xil_printf("  e / d : density    + / -   (%d samples; smaller=denser)\r\n", CL_DEN_STEP);
    xil_printf("  r / f : texture    x2 / /2 (jitter, power of 2)\r\n");
    xil_printf("  t / g : blend      + / -   (%d of 256 wet)\r\n", CL_BLEND_STEP);
    xil_printf("  y / h : wet_shift  + / -   (gain trim)\r\n");
    xil_printf("  u / j : pitch      + / -   (semitone)\r\n");
    xil_printf("  p     : print state     ? : this menu\r\n");
    xil_printf("==================================================\r\n");
}

void clouds_ui_print(clouds_ui_t *u) {
    xil_printf("[clouds] %s pos=%d size=%d invh=%d den=%d tex=%d blend=%d/256 ws=%d pitch=%dst\r\n",
               u->enabled ? "ON " : "off",
               u->position, u->size, (int)clouds_inv_half(u->cl),
               u->density, u->texture, u->blend, u->wet_shift, u->pitch_semi);
}

void clouds_ui_init(clouds_ui_t *u, clouds_t *cl) {
    u->cl = cl;
    u->position = 16000; u->size = 2400; u->density = 800; u->texture = 2048;
    u->blend = 160; u->wet_shift = 1; u->pitch_semi = 0; u->enabled = 0;

    clouds_set_position(cl, u->position);
    clouds_set_size(cl, u->size);           // hardware recomputes the window slope
    clouds_wait_recip(cl);
    clouds_set_density(cl, u->density);
    clouds_set_texture(cl, u->texture);
    clouds_set_blend(cl, u->blend);
    clouds_set_wet_shift(cl, u->wet_shift);
    clouds_set_pitch_semitones(cl, 0.0f);
    clouds_enable(cl, u->enabled);

    clouds_ui_help();
    clouds_ui_print(u);
}

static void handle(clouds_ui_t *u, char ch) {
    switch (ch) {
    case ' ': u->enabled = !u->enabled; clouds_enable(u->cl, u->enabled); break;

    case 'q': u->position = clampi(u->position + CL_POS_STEP, CL_POS_MIN, CL_POS_MAX);
              clouds_set_position(u->cl, u->position); break;
    case 'a': u->position = clampi(u->position - CL_POS_STEP, CL_POS_MIN, CL_POS_MAX);
              clouds_set_position(u->cl, u->position); break;

    case 'w': u->size = clampi(u->size + CL_SIZE_STEP, CL_SIZE_MIN, CL_SIZE_MAX);
              clouds_set_size(u->cl, u->size); clouds_wait_recip(u->cl); break;
    case 's': u->size = clampi(u->size - CL_SIZE_STEP, CL_SIZE_MIN, CL_SIZE_MAX);
              clouds_set_size(u->cl, u->size); clouds_wait_recip(u->cl); break;

    case 'e': u->density = clampi(u->density + CL_DEN_STEP, CL_DEN_MIN, CL_DEN_MAX);
              clouds_set_density(u->cl, u->density); break;
    case 'd': u->density = clampi(u->density - CL_DEN_STEP, CL_DEN_MIN, CL_DEN_MAX);
              clouds_set_density(u->cl, u->density); break;

    case 'r': u->texture = clampi(u->texture * 2, CL_TEX_MIN, CL_TEX_MAX);
              clouds_set_texture(u->cl, u->texture); break;
    case 'f': u->texture = clampi(u->texture / 2, CL_TEX_MIN, CL_TEX_MAX);
              clouds_set_texture(u->cl, u->texture); break;

    case 't': u->blend = clampi(u->blend + CL_BLEND_STEP, 0, 256);
              clouds_set_blend(u->cl, u->blend); break;
    case 'g': u->blend = clampi(u->blend - CL_BLEND_STEP, 0, 256);
              clouds_set_blend(u->cl, u->blend); break;

    case 'y': u->wet_shift = clampi(u->wet_shift + 1, CL_WS_MIN, CL_WS_MAX);
              clouds_set_wet_shift(u->cl, u->wet_shift); break;
    case 'h': u->wet_shift = clampi(u->wet_shift - 1, CL_WS_MIN, CL_WS_MAX);
              clouds_set_wet_shift(u->cl, u->wet_shift); break;

    case 'u': u->pitch_semi = clampi(u->pitch_semi + 1, CL_SEMI_MIN, CL_SEMI_MAX);
              clouds_set_pitch_semitones(u->cl, (float)u->pitch_semi); break;
    case 'j': u->pitch_semi = clampi(u->pitch_semi - 1, CL_SEMI_MIN, CL_SEMI_MAX);
              clouds_set_pitch_semitones(u->cl, (float)u->pitch_semi); break;

    case 'p': clouds_ui_print(u); return;
    case '?': clouds_ui_help();   return;
    case '\r': case '\n': return;          // ignore line endings silently
    default: return;                       // unknown key: no echo, no reprint
    }
    clouds_ui_print(u);                     // any change -> show new state
}

int clouds_ui_poll(clouds_ui_t *u) {
    int n = 0;
    while (uart_avail()) { handle(u, uart_getc()); n++; }
    return n;
}

void clouds_ui_run(clouds_ui_t *u) {
    for (;;) {
        if (uart_avail()) handle(u, uart_getc());
    }
}
