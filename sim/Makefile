# Functional simulation for the Clouds granular core (Icarus Verilog only).
#   make test   - run all testbenches
#   make clean
IVERILOG ?= iverilog
VVP      ?= vvp
IVFLAGS  ?= -g2012
RTL       = ../rtl
B         = build

.PHONY: all test readcheck func recip csr loopback clean
all: test
test: readcheck func recip csr loopback

$(B):
	@mkdir -p $(B)

readcheck: | $(B)
	@echo "== read-path check =="
	$(IVERILOG) $(IVFLAGS) -o $(B)/rc $(RTL)/clouds_engine.v tb_clouds_readcheck.sv
	@$(VVP) $(B)/rc

func: | $(B)
	@echo "== functional (granular) =="
	$(IVERILOG) $(IVFLAGS) -o $(B)/fn $(RTL)/clouds_engine.v tb_clouds_func.sv
	@$(VVP) $(B)/fn

recip: | $(B)
	@echo "== reciprocal divider =="
	$(IVERILOG) $(IVFLAGS) -o $(B)/rcp $(RTL)/clouds_recip.v tb_clouds_recip.sv
	@$(VVP) $(B)/rcp

csr: | $(B)
	@echo "== AXI4-Lite CSR end-to-end =="
	$(IVERILOG) $(IVFLAGS) -o $(B)/csr $(RTL)/clouds_csr_axil.v $(RTL)/clouds_recip.v $(RTL)/clouds_engine.v tb_clouds_csr.sv
	@$(VVP) $(B)/csr

loopback: | $(B)
	@echo "== I2S serdes loopback (ser <-> deser round-trip) =="
	$(IVERILOG) $(IVFLAGS) -o $(B)/lb $(RTL)/iis_ser.v $(RTL)/iis_deser.v tb_iis_loopback.sv
	@$(VVP) $(B)/lb

clean:
	rm -rf $(B)
