## ----------------------------------------------------------------------------
## audio.xdc - ADAU1761 codec pin constraints, TUL PYNQ-Z2 (XC7Z020, clg400)
##
## Port names match the block-design wrapper (soc_bd_wrapper):
##   aud_mclk  codec master clock   (from PS FCLK_CLK1)
##   au_bclk   I2S bit clock        (FPGA -> codec, BCLK)
##   au_wclk   I2S word/LR clock    (FPGA -> codec, LRCLK)
##   au_din    I2S data             (FPGA -> codec, DAC)
##   au_dout   I2S data             (codec -> FPGA, ADC)
##   audio_i2c control bus          (PS axi_iic -> codec)
##
## BCLK/LRCLK are produced by dividing the 100 MHz fabric clock inside
## audio_engine.
## ----------------------------------------------------------------------------

## codec master clock
set_property -dict { PACKAGE_PIN U5  IOSTANDARD LVCMOS33 } [get_ports aud_mclk]

## I2S serial audio
set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 } [get_ports au_bclk]
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports au_wclk]
set_property -dict { PACKAGE_PIN F17 IOSTANDARD LVCMOS33 } [get_ports au_dout] ;# ADC -> FPGA
set_property -dict { PACKAGE_PIN G18 IOSTANDARD LVCMOS33 } [get_ports au_din]  ;# FPGA -> DAC

## I2C control (ADAU1761 register configuration)
set_property -dict { PACKAGE_PIN U9  IOSTANDARD LVCMOS33 } [get_ports audio_i2c_scl_io]
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports audio_i2c_sda_io]
