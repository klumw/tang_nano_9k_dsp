# Board and chip specifications for the Tang Nano 9K
BOARD = tangnano9k
FAMILY = GW1N-9C
DEVICE = GW1NR-LV9QN88PC6/I5

# Project files
TOP = top
SOURCES = src/top.v src/i2s_clock.v src/i2s_rx.v src/i2s_tx.v \
          src/envelope_detector.v src/gain_computer.v \
          src/limiter_core.v src/compressor_core.v \
          src/equalizer_core.v \
          src/volume_control.v \
          src/sine_gen.v
CONSTRAINTS = src/top.cst
LOADER_FLAGS ?= 

# Default target: generate bitstream
all: build/$(TOP).fs

# 1. Synthesis with Yosys
build/$(TOP).json: $(SOURCES)
	mkdir -p build
	yosys -p "read_verilog $(SOURCES); synth_gowin -top $(TOP) -json build/$(TOP).json"

# 2. Place and Route with nextpnr-gowin
build/$(TOP)_pnr.json: build/$(TOP).json $(CONSTRAINTS)
	nextpnr-himbaechel --json build/$(TOP).json --write build/$(TOP)_pnr.json --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CONSTRAINTS)

# 3. Pack bitstream with gowin_pack
build/$(TOP).fs: build/$(TOP)_pnr.json
	gowin_pack -d $(FAMILY) -o build/$(TOP).fs build/$(TOP)_pnr.json

# 4. Flash to volatile SRAM
load: build/$(TOP).fs
	openFPGALoader -b $(BOARD) $(LOADER_FLAGS) build/$(TOP).fs

# 5. Flash to permanent flash memory
flash: build/$(TOP).fs
	openFPGALoader -b $(BOARD) $(LOADER_FLAGS) -f build/$(TOP).fs

# 6. Simulation with iverilog
# Note: Requires a simulation model for rPLL (gowin_sim.v)
sim: src/top_tb.v src/top.v src/pll.v src/gowin_sim.v
	mkdir -p build
	iverilog -o build/$(TOP)_sim src/top_tb.v src/top.v src/pll.v src/gowin_sim.v
	vvp build/$(TOP)_sim

# Clean up
clean:
	rm -rf build/
	rm -f *.vcd

.PHONY: all load flash sim clean
