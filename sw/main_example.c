/*
 * PYNQ-Z2 audio pass-through - bare-metal
 * ADAU1761 codec configured over AXI IIC (PL), I2S RX -> I2S TX loopback.
 *
 * Driver note: codec I2C is in the PL here, so we use the XIic driver
 * (xiic.h), NOT XIicPs. That is the main departure from the Snickerdoodle
 * (TLV320 / PS-I2C) example.
 *
 * Adjust the XPAR_* names below to match YOUR xparameters.h - the exact
 * instance names depend on your block design.
 */

#include "xparameters.h"
#include "xiic.h"
#include "xil_printf.h"
#include "sleep.h"
#include <string.h>

#include "clouds.h"
#include "clouds_console.h"

/* ---- base address (SDT flow, Vitis 2023.2+; match xparameters.h) ---- */
#define IIC_BASEADDR     XPAR_AXI_IIC_0_BASEADDR

/* ---- ADAU1761 7-bit I2C address ----
 * Address = 011 1 0 ADDR1 ADDR0 (datasheet Table 21), set by pin strapping.
 * Try 0x3B first; if the read-back at the end NAKs, try 0x38 (both ADDR low).
 */
#define ADAU1761_ADDR   0x3B

static XIic   Iic;

/* =========================== I2C helpers =========================== */
/* ADAU1761 uses 16-bit register addresses, 8-bit data. */

static int adau_write(u16 reg, u8 val)
{
    u8 buf[3] = { (u8)(reg >> 8), (u8)(reg & 0xFF), val };
    int n = XIic_Send(Iic.BaseAddress, ADAU1761_ADDR, buf, 3, XIIC_STOP);
    return (n == 3) ? XST_SUCCESS : XST_FAILURE;
}

static int adau_write_n(u16 reg, const u8 *data, int len)
{
    u8 buf[8];
    buf[0] = (u8)(reg >> 8);
    buf[1] = (u8)(reg & 0xFF);
    memcpy(&buf[2], data, len);
    int n = XIic_Send(Iic.BaseAddress, ADAU1761_ADDR, buf, len + 2, XIIC_STOP);
    return (n == len + 2) ? XST_SUCCESS : XST_FAILURE;
}

static int adau_read(u16 reg, u8 *val)
{
    u8 a[2] = { (u8)(reg >> 8), (u8)(reg & 0xFF) };
    XIic_Send(Iic.BaseAddress, ADAU1761_ADDR, a, 2, XIIC_REPEATED_START);
    int n = XIic_Recv(Iic.BaseAddress, ADAU1761_ADDR, val, 1, XIIC_STOP);
    return (n == 1) ? XST_SUCCESS : XST_FAILURE;
}

/* =========================== IIC init =========================== */
static int iic_init(void)
{
    XIic_Config *cfg = XIic_LookupConfig(IIC_BASEADDR);
    if (cfg == NULL) return XST_FAILURE;
    if (XIic_CfgInitialize(&Iic, cfg, cfg->BaseAddress) != XST_SUCCESS)
        return XST_FAILURE;
    XIic_Start(&Iic);
    return XST_SUCCESS;
}

/* =========================== ADAU1761 init =========================== */
/*
 * Verified against ADAU1761 Rev. F datasheet. 48 kHz, I2S subordinate,
 * line-in (LAUX/RAUX) -> ADC -> serial out, serial in -> DAC -> headphone.
 * Startup order per datasheet p.22-23: lock PLL, enable core clock, then
 * load the rest. Only R0/R1 are writable until COREN + lock are set.
 */
static int adau_init(void)
{
    u8 rb = 0;
    int i;

    /* ---- 1. PLL: 10 MHz -> 49.152 MHz, FRACTIONAL (R + N/M = 4.9152) ----
     * R=4, X=1, M=625 (0x0271), N=572 (0x023C), fractional -> byte4=0x21.
     * 10 MHz is an exact /10 of the 100 MHz PS clock and within the PLL's
     * 8-27 MHz range. As master the codec makes BCLK/LRCLK from its 49.152 MHz
     * core, so MCLK rate has no effect on framing - it's just the PLL ref.
     */
    const u8 pll[6] = { 0x02, 0x71, 0x02, 0x3C, 0x21, 0x01 };
    adau_write_n(0x4002, pll, 6);

    /* ---- 2. Poll PLL lock (R1 byte5 bit1) and REPORT it ---- */
    int locked = 0;
    u8 r1[6] = {0};
    for (i = 0; i < 200; i++) {
        u8 a[2] = { 0x40, 0x02 };
        XIic_Send(Iic.BaseAddress, ADAU1761_ADDR, a, 2, XIIC_REPEATED_START);
        XIic_Recv(Iic.BaseAddress, ADAU1761_ADDR, r1, 6, XIIC_STOP);
        if (r1[5] & 0x02) { locked = 1; break; }
        usleep(1000);
    }
    if (locked) {
        xil_printf("ADAU1761 PLL LOCKED after %d ms\r\n", i + 1);
    } else {
        xil_printf("ADAU1761 PLL NOT LOCKED - R1 readback = "
                   "%02x %02x %02x %02x %02x %02x\r\n",
                   r1[0], r1[1], r1[2], r1[3], r1[4], r1[5]);
        xil_printf("  (check MCLK freq vs PLL M/N/R; target must be 41-54 MHz)\r\n");
        return XST_FAILURE;   /* other registers are invalid until locked */
    }

    /* ---- 3. Core clock: source = PLL, enable. INFREQ auto-set to 1024*fs. */
    adau_write(0x4000, 0x09);

    /* ---- 4. Enable digital clock engines ---- */
    adau_write(0x40F9, 0x7F);   /* Clock Enable 0: serial port, routing, dejitter */
    adau_write(0x40FA, 0x03);   /* Clock Enable 1: CLK0 + CLK1 */

    /* ---- 5. Serial port: I2S, codec = SUBORDINATE, stereo, 64 BCLK ----
     * wady101 architecture: the FPGA (audio_passthrough.sv) generates BCLK and
     * LRCLK by dividing the 100 MHz clock and drives them into the codec, so
     * the codec is the subordinate. au_bclk/au_wclk are FPGA OUTPUTS in the BD.
     */
    adau_write(0x4015, 0x00);   /* SP0: I2S, MS=0 (subordinate) */
    adau_write(0x4016, 0x00);   /* SP1: BPF=64, MSB first, 1 BCLK data delay */
    adau_write(0x4036, 0x03);   /* dejitter window=3 (ON; required in subordinate mode) */

    /* ---- 6. Converter sample rate = fs (48 kHz), 128x oversampling ---- */
    adau_write(0x4017, 0x00);

    /* ---- 7. ADC: high-pass filter on, both ADCs enabled ---- */
    adau_write(0x4019, 0x33);

    /* ---- 8. Record path: line-in (LAUX/RAUX) -> record mixers -> ADC ----
     * PYNQ-Z2 line-in lands on the aux pins, so use MX1AUXG/MX2AUXG (0 dB).
     * (Mic path would instead be LINP/RINP via the differential PGA, R8/R9.)
     */
    adau_write(0x400A, 0x01);   /* Rec Mixer L (Mixer1) enable */
    adau_write(0x400B, 0x05);   /* LAUX -> Mixer1 at 0 dB */
    adau_write(0x400C, 0x01);   /* Rec Mixer R (Mixer2) enable */
    adau_write(0x400D, 0x05);   /* RAUX -> Mixer2 at 0 dB */

    /* ---- 9. Playback path: DAC -> playback mixers -> headphone ---- */
    adau_write(0x4029, 0x03);   /* Playback power: PLEN + PREN */
    adau_write(0x402A, 0x03);   /* DAC enable both */
    adau_write(0x401C, 0x21);   /* Play Mixer L (Mixer3): left DAC unmute + enable */
    adau_write(0x401E, 0x41);   /* Play Mixer R (Mixer4): right DAC unmute + enable */
    adau_write(0x4023, 0xE7);   /* LHP: 0 dB, unmute, HPEN */
    adau_write(0x4024, 0xE7);   /* RHP: 0 dB, unmute, HPMODE = headphone output */

    /* ---- 10. CRITICAL: serial routing. Defaults send ADC->DSP and DSP->DAC;
     * with no DSP program the path is dead. Route converters straight to the
     * serial port instead so the FPGA loopback works.
     */
    adau_write(0x40F2, 0x01);   /* Serial input [L0,R0] -> DACs */
    adau_write(0x40F3, 0x01);   /* ADCs -> serial output [L0,R0] */

    adau_write(0x4009, 0x14);   /* R3: ADCBIAS + RBIAS = enhanced performance */

    /* sanity read-back of clock control */
    adau_read(0x4000, &rb);
    xil_printf("ADAU1761 0x4000 read-back = 0x%02x (expect 0x09)\r\n", rb);
    return XST_SUCCESS;
}

/* =========================== main =========================== */
int main(void)
{
    xil_printf("\r\nPYNQ-Z2 audio passthrough\r\n");

    if (iic_init()  != XST_SUCCESS) { xil_printf("IIC init failed\r\n");  return -1; }
    if (adau_init() != XST_SUCCESS) { xil_printf("ADAU init failed\r\n"); return -1; }

    /* The I2S passthrough is entirely in the PL (iis_deser -> iis_ser).
     * Once the codec is configured, no further CPU work is needed. */
    xil_printf("Codec configured. PL serdes is passing audio.\r\n");

    clouds_t   cl;
    clouds_ui_t ui;

    clouds_init(&cl, XPAR_AUDIO_ENGINE_0_BASEADDR);  // your base addr
    if (clouds_id(&cl) != CLOUDS_ID_MAGIC) {
        xil_printf("clouds: ID mismatch (got 0x%08x) - check base address\r\n",
                   (unsigned)clouds_id(&cl));
    }

    clouds_ui_init(&ui, &cl);   // push defaults, print the menu
    clouds_ui_run(&ui);         // tweak by ear over the terminal

    while (1) {
        /* nothing to do - passthrough runs in hardware */
    }
    return 0;
}