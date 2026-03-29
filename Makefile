# Board und Chip Spezifikationen für den Tang Nano 9K
BOARD = tangnano9k
FAMILY = GW1N-9C
DEVICE = GW1NR-LV9QN88PC6/I5

# Projekt-Dateien
TOP = top
SOURCES = src/top.v src/i2s_clock.v src/i2s_rx.v src/i2s_tx.v \
          src/envelope_detector.v src/gain_computer.v \
          src/limiter_core.v src/compressor_core.v \
          src/equalizer_core.v \
          src/volume_control.v \
          src/sine_gen.v
CONSTRAINTS = src/top.cst
LOADER_FLAGS ?= 

# Standard-Ziel: Bitstream erstellen
all: build/$(TOP).fs

# 1. Synthese mit Yosys
build/$(TOP).json: $(SOURCES)
	mkdir -p build
	yosys -p "read_verilog $(SOURCES); synth_gowin -top $(TOP) -json build/$(TOP).json"

# 2. Place and Route mit nextpnr-gowin
build/$(TOP)_pnr.json: build/$(TOP).json $(CONSTRAINTS)
	nextpnr-himbaechel --json build/$(TOP).json --write build/$(TOP)_pnr.json --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CONSTRAINTS)

# 3. Bitstream packen mit gowin_pack
build/$(TOP).fs: build/$(TOP)_pnr.json
	gowin_pack -d $(FAMILY) -o build/$(TOP).fs build/$(TOP)_pnr.json

# 4. In den flüchtigen SRAM flashen
load: build/$(TOP).fs
	openFPGALoader -b $(BOARD) $(LOADER_FLAGS) build/$(TOP).fs

# 5. In den permanenten Flash-Speicher flashen
flash: build/$(TOP).fs
	openFPGALoader -b $(BOARD) $(LOADER_FLAGS) -f build/$(TOP).fs

# 6. Simulation mit iverilog
# Hinweis: Benötigt ein Simulationsmodell für rPLL (gowin_sim.v)
sim: src/top_tb.v src/top.v src/pll.v src/gowin_sim.v
	mkdir -p build
	iverilog -o build/$(TOP)_sim src/top_tb.v src/top.v src/pll.v src/gowin_sim.v
	vvp build/$(TOP)_sim

# Aufräumen
clean:
	rm -rf build/
	rm -f *.vcd

.PHONY: all load flash sim clean
