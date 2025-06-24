# DifuzzRTL: Differential Fuzz Testing to Find CPU Bugs

## Introduction

DifuzzRTL is a differential fuzz testing approach for CPU verification.
We introduce new coverage metric, _register-coverage_, which comprehensively captures the states of an RTL design and correctly guides the input generation.
DifuzzRTL automatically instruments _register-coverage_, randomly generates and mutates instructions defined in ISA, then cross-check against an ISA simulator to
detect bugs.
DiFuzzRTL is accepted at IEEE S&P 2021 ([paper][paperlink])

[paperlink]: https://www.computer.org/csdl/proceedings-article/sp/2021/893400b778/1t0x9G4Q5MI

## Setup

### Prerequisite

Please install the correct versions!

1. [sbt][sbtlink] for FIRRTL

[sbtlink]: https://www.scala-sbt.org/

2. [verilator][verilatorlink] for RTL simulation (v4.106)

[verilatorlink]: https://github.com/verilator/verilator

3. [cocotb][cocotblink] for RTL simulation (1.5.2)

[cocotblink]: https://docs.cocotb.org/en/stable/

4. [riscv][riscvlink] for RISC-V instruction mutation (2021.04.23)

[riscvlink]: https://github.com/riscv/riscv-gnu-toolchain.git

### Instructions

- For RTL simulation using verilator

```
git clone https://github.com/compsec-snu/difuzz-rtl
cd DifuzzRTL
git checkout sim

. ./setup.sh

cd elf2hex
cp elf2hex ~/local/bin/riscv64-unknown-elf-elf2hex
chmod +x ~/local/bin/riscv64-unknown-elf-elf2hex
export PATH="$HOME/local/bin:$PATH"
```

## Instrumentation

```
cd firrtl
sbt compile; sbt assembly
./utils/bin/firrtl -td regress -i regress/RocketTile_3f03ba.fir --custom-transforms tutorial.lesson1.AnalyzeCircuit
./utils/bin/firrtl -td regress -i regress/SmallBoomTile_v1.2.fir --custom-transforms tutorial.lesson1.AnalyzeCircuit
```

**target_fir**: Firrtl file to instrument  
**output_verilog**: Output verilog file

## Run

```
cd Fuzzer
pip3 install cocotb
pip3 install pytest
export SPIKE=$HOME/riscv-isa-sim/build/spike
export PATH="$PATH:$(python -c 'import site; print(site.getuserbase())')/bin"
export PYTHONPATH=$PYTHONPATH:$HOME/difuzz-rtl/Fuzzer/RTLSim/src
make VFILE=RocketTile_state TOPLEVEL=RocketTile OUT=rocket_out RECORD=1 NUM_ITER=100
make VFILE=SmallBoomTile_v1.2_state TOPLEVEL=BoomTile OUT=boom_out RECORD=1 NUM_ITER=100
ls -a output/
```

**SIM_BUILD**: Directory for RTL simulation binary build by cocotb  
**VFILE**: Target RTL design in DifuzzRTL/Benchmarks/Verilog/  
 (e.g., RocketTile_state, SmallBoomTile_v_1.2_state, SmallBoomTile_v1.3_state)  
**TOPLEVEL**: Top-level module  
 (e.g., RocketTile or BoomTile)  
**NUM_ITER**: Number of fuzzing iterations to run  
**OUT**: Output directory  
**RECORD**: Set 1 to record coverage log  
**DEBUG**: Set 1 to print debug messages
