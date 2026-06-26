# Convenience delegator. Real targets live in sim/Makefile.
.PHONY: test clean
test:  ; @$(MAKE) -C sim test
clean: ; @$(MAKE) -C sim clean
