CC = "riscv64-unknown-linux-gnu-gcc"
ELF2HEX = "riscv64-unknown-elf-elf2hex"
OBJCOPY = "riscv64-unknown-linux-gnu-objcopy"
SPIKE = "/nfs/home/changgen/riscv-isa-sim/build/spike"
NEMU_BINARY = "/nfs/home/changgen/xs-env/NEMU/build/riscv64-nemu-interpreter"
EMU_BINARY = "/nfs/home/changgen/xs-env/XiangShan/build/emu"
DIFF_SO_PATH = "/nfs/home/changgen/xs-env/NEMU/ready-to-run/riscv64-nemu-interpreter-so"


FUZZ_EMU = 0
GENERATOR_SELECTOR = [
    0,  # CounterTimerGenerator("RV64G"),
    0,  # ExceptionGenerator("RV64G"),
    0,  # InterruptGenerator("RV64G"),
    0,  # RandSwitchGenerator("RV64G"),
    0,  # RandomInstGenerator("RV64G"),
    0,  # IllLow2highGenerator("RV64G"),
    0,  # M2SLegalSwitchGenerator("RV64G"),
    0,  # S2ULegalSwitchGenerator("RV64G"),
    0,  # HyperviserGenerator("RV64G"),
    0,  # BitmaprGenerator("RV64G"),
    0,  # MptGenerator("RV64G"),
    1,  # CBOGenerator("RV64G"),
]
