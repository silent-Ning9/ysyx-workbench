SOC ?= 0
TOPNAME = NPC
ifeq ($(SOC),1)
TOPNAME = ysyxSoCFull
endif
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(OBJ_DIR)/V$(TOPNAME)
override NEMU_HOME := $(abspath .)
override YSYX_HOME := $(abspath ..)

VSRCS = $(shell find vsrc -name "*.v")
CSRCS = $(shell find csrc -name "*.cpp")

ifeq ($(SOC),1)
VSRCS += $(shell find ../ysyxSoC/perip -name "*.v")
VSRCS += ../ysyxSoC/ready-to-run/D-stage/ysyxSoCFull.v
VERILATOR_FLAGS += -I../ysyxSoC/perip/uart16550/rtl
VERILATOR_FLAGS += -I../ysyxSoC/perip/spi/rtl
VERILATOR_FLAGS += --timescale "1ns/1ns" --no-timing
VERILATOR_FLAGS += -CFLAGS "-DSOC_TOP=1"
endif

VERILATOR_FLAGS += -Wall --cc --exe --build --trace --top-module $(TOPNAME)
VERILATOR_FLAGS += -Wno-fatal
VERILATOR_FLAGS += -Mdir $(OBJ_DIR)
VERILATOR_FLAGS += -CFLAGS "-std=c++17 -O2"

all: $(BIN)

$(BIN): $(VSRCS) $(CSRCS)
	@mkdir -p $(BUILD_DIR)
	verilator $(VERILATOR_FLAGS) $(VSRCS) $(CSRCS)

sim: $(BIN)
	$(call git_commit, "sim RTL") # DO NOT REMOVE THIS LINE!!!
	@if [ -z "$(IMG)" ]; then \
		echo "Usage: make sim IMG=/path/to/program.bin"; \
		exit 1; \
	fi
	$(BIN) $(IMG) $(MAX_CYCLES)

soc:
	@$(MAKE) SOC=1 sim IMG="$(IMG)" MAX_CYCLES="$(MAX_CYCLES)"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all sim soc clean

include ../Makefile
