TOPNAME = NPC
BUILD_DIR = build
OBJ_DIR = $(BUILD_DIR)/obj_dir
BIN = $(OBJ_DIR)/V$(TOPNAME)
override NEMU_HOME := $(abspath .)
override YSYX_HOME := $(abspath ..)

VSRCS = $(shell find vsrc -name "*.v")
CSRCS = $(shell find csrc -name "*.cpp")

VERILATOR_FLAGS += -Wall --cc --exe --build --trace --top-module $(TOPNAME)
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

clean:
	rm -rf $(BUILD_DIR)

.PHONY: all sim clean

include ../Makefile
