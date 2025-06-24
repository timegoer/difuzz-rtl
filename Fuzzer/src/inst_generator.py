import os
import random

from riscv_definitions import *
from word import *

""" rvInstGenerator
Generates syntactically, semantically desirable unit of instructions

Properties
 2. Compilable
 1. Guarantee forward progress and end (No loop)
"""


class BaseInstGenerator:
    def __init__(self, isa="RV64G"):
        self.isa = isa
        self.rv_isas = self._get_isas(isa)

        self.opcodes_map = {}
        for isa in self.rv_isas:
            self.opcodes_map.update(rv_opcodes[isa])
        self.opcodes = list(self.opcodes_map.keys())

        self._reset_state()
        self.xNums = list(range(32))
        self.fNums = list(range(32))

    def _get_isas(self, isa):
        isas = ["trap_ret"]
        extensions = {
            "I": "rv32i",
            "M": "rv32m",
            "A": "rv32a",
            "F": "rv32f",
            "D": "rv32d",
            "Q": "rv32q",
            "zifencei": "rv_zifencei",
            # "zicsr": "rv_zicsr",
        }

        for key, ext in extensions.items():
            if key in isa:
                isas.append(ext)

        if "G" in isa:
            isas += ["rv32i", "rv32a", "rv32f", "rv_zifencei", "rv_zicsr"]

        if "RV64" in isa:
            isas = self._extend_isas(isas)

        return isas

    def _extend_isas(self, isas):
        extended_isas = []
        for isa in isas:
            extended_isas.append(isa)
            if "32" in isa:
                extended_isas.append(isa.replace("32", "64"))
        return extended_isas

    def _reset_state(self):
        self._p_num = 0
        self._l_num = 0
        self._s_num = 0
        self.used_xNums = set()
        self.used_fNums = set()
        self.used_imms = set()

    def reset(self):
        self._reset_state()

    def _get_xregs(self, region=(0, 31), no_zero=False, thres=0.2):
        if region == (0, 31) and self.used_xNums and random.random() < thres:
            xNum = random.choice(list(self.used_xNums))
        else:
            xNum = random.choice(self.xNums[region[0] : region[1]])
            self.used_xNums.add(xNum)

        if no_zero and xNum == 0:
            xNum = random.choice(self.xNums[1:])

        return f"x{xNum}"

    def _get_fregs(self, thres=0.2):
        if self.used_fNums and random.random() < thres:
            fNum = random.choice(list(self.used_fNums))
        else:
            fNum = random.choice(self.fNums)
            self.used_fNums.add(fNum)
        return f"f{fNum}"

    def _get_imm(self, iName, align, thres=0.2, zfthres=0.2, alignthres=1):
        assert align & (align - 1) == 0, "align must be power of 2"

        is_unsigned = "uimm" in iName
        prefix = "" if is_unsigned else random.choice(["", "-"])
        width = int(iName[4:] if is_unsigned else iName[3:]) - (0 if is_unsigned else 1)

        mask = (1 << width) - 1
        use_alignment = random.random() < alignthres
        mask = mask & ~(align - 1) if use_alignment else mask

        rand_val = random.random()
        if self.used_imms and rand_val < thres:
            imm = random.choice(list(self.used_imms))
        elif rand_val < thres + zfthres:
            imm = random.choice([0x0, 0x1, 0x80000000, 0xFFFFFFFF])
        else:
            imm = random.randint(0, mask)
            self.used_imms.add(imm)

        return f"{prefix}{mask & imm}"

    def _get_symbol(self, inst_type, current_label, max_label, part):
        if inst_type == MEM_W:
            section = random.randint(0, 5)
            offset = random.randint(0, 27)
            return f"d_{section}_{offset}"

        if inst_type == MEM_R:
            return (
                f"{part}{random.randint(0, max_label)}"
                if random.random() < 0.2
                else f"d_{random.randint(0, 5)}_{random.randint(0, 27)}"
            )

        if inst_type in (CF_J, CF_RET):
            target = random.randint(current_label + 1, max_label)
            return f"{part}{target}"

        return f"{part}{random.randint(current_label + 1, max_label)}"

    def populate_word(self, word: Word, max_label: int, part: str):
        if word.populated:
            return

        region = (10, 15) if part == PREFIX else (0, 31)
        opvals = {}

        for xreg in word.xregs:
            opvals[xreg] = self._get_xregs(region, word.tpe != NONE)

        for freg in word.fregs:
            opvals[freg] = self._get_fregs()

        for imm, align in word.imms:
            opvals[imm] = self._get_imm(imm, align)

        for symbol in word.symbols:
            opvals[symbol] = self._get_symbol(word.tpe, word.label, max_label, part)

        word.populate(opvals, part)

    def get_word(self, part: str) -> Word:
        label_num = getattr(self, f"{part}_num")
        setattr(self, f"{part}_num", label_num + 1)

        opcode = self._select_opcode(part)
        syntax, xregs, fregs, imms, symbols = self.opcodes_map[opcode]

        xregs = list(xregs)
        fregs = list(fregs)
        imms = list(imms)
        symbols = list(symbols)
        inst_type, insts = self._process_opcode(
            opcode,
            syntax,
            xregs,
            fregs,
            imms,
            symbols,
        )
        return Word(
            label_num,
            insts,
            inst_type,
            xregs,
            fregs,
            imms,
            symbols,
        )

    def _select_opcode(self, part: str) -> str:
        if part == PREFIX:
            return random.choice(list(rv_zicsr.keys()))
        return random.choice(self.opcodes)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):
        inst_type = NONE
        insts = [syntax]

        for key, (opcodes_set, handler) in opcodes_words.items():
            if opcode in opcodes_set:
                inst_type, insts = handler(opcode, syntax, xregs, fregs, imms, symbols)
                break

        return inst_type, insts


class RandomInstGenerator(BaseInstGenerator):
    """Default generator using random instruction selection"""

    templates = [0, 1, 2]
    pass


# 测试从用户模式（U-mode）切换到超级模式（S-mode）或机器模式（M-mode）
class IllLow2highGenerator(BaseInstGenerator):
    templates = [2]

    def _select_opcode(self, part: str) -> str:
        if (random.random() < 0.4) and (part == MAIN or part == SUFFIX):
            # Prioritize privileged instructions
            dice = random.randint(0, 100)
            if dice < 20:
                opcode = random.choice(["sret", "mret", "sfence.vma", "csrrw"])
            elif dice >= 20 and dice < 30:
                opcode = "ecall"
            else:
                opcode = random.choice(["csrrs", "csrrc", "csrrw"])
            return opcode
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):

        def _word_csr_r(opcode, syntax, xregs, fregs, imms, symbols):
            csr = random.choice(["sstatus", "mstatus", "sepc", "mepc"])
            tpe = CSR
            insts = ["xor xreg1, xreg1, xreg1"]
            for i in range(random.randint(0, 3)):
                set_bits = random.choice([1, 3])
                offset = random.randint(0, 31)
                insts = insts + [
                    "addi xreg{}, zero, {}".format(i + 2, set_bits),
                    "slli xreg{}, xreg{}, {}".format(i + 2, i + 2, offset),
                    "add xreg1, xreg1, xreg{}".format(i + 2),
                ]
                xregs.append("xreg{}".format(i + 2))
            insts.append(syntax.format(csr))

            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["csrrw", "csrrs", "csrrc"]:
            inst_type, insts = _word_csr_r(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        return inst_type, insts


# 验证从 M-mode 到 S-mode 的合法切换是否正常。
class M2SLegalSwitchGenerator(BaseInstGenerator):
    templates = [0]

    def _select_opcode(self, part: str) -> str:
        if random.random() < 0.3 and part == MAIN:
            return "csrrw"
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):

        def _word_csrrw(opcode, syntax, xregs, fregs, imms, symbols):
            csr = random.choice(["mepc", "mstatus"])
            tpe = CSR
            if csr == "mepc":
                insts = [
                    "auipc xreg1, 0",
                    "addi  xreg1, xreg1, 16",
                ]
            elif csr == "mstatus":
                i = random.randint(0, 3)
                insts = [
                    "csrr xreg1, mstatus",
                    "li  xreg{}, {}".format(i + 3, ~(3 << 11)),
                    "and xreg1, xreg1, xreg{}".format(i + 3),
                    "ori xreg1, xreg1, -2048",
                ]
                xregs.append("xreg{}".format(i + 3))
            insts.append(syntax.format(csr))
            insts.append("mret")

            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["csrrw"]:
            inst_type, insts = _word_csrrw(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        return inst_type, insts


# 从 S-mode 到 U-mode 的合法切换是否正常。
class S2ULegalSwitchGenerator(BaseInstGenerator):
    templates = [1]

    def _select_opcode(self, part: str) -> str:
        if random.random() < 0.2 and part == MAIN:
            return "csrrw"
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):

        def _word_csrrw(opcode, syntax, xregs, fregs, imms, symbols):
            csr = random.choice(["sepc", "sstatus"])
            tpe = CSR
            if csr == "sepc":
                insts = [
                    "auipc xreg1, 0",
                    "addi  xreg1, xreg1, 16",
                ]
                insts.append(syntax.format(csr))
            elif csr == "sstatus":
                i = random.randint(0, 3)
                insts = [
                    "csrr xreg1, sstatus",
                    "li  xreg{}, {}".format(i + 3, ~(3 << 8)),
                    "and xreg1, xreg1, xreg{}".format(i + 3),
                ]
                xregs.append("xreg{}".format(i + 3))
                insts.append(syntax.format(csr))
                insts.append("sret")

            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["csrrw"]:
            inst_type, insts = _word_csrrw(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        return inst_type, insts


class RandSwitchGenerator(BaseInstGenerator):
    templates = [0, 1, 2]

    def _select_opcode(self, part: str) -> str:
        if (random.random() < 0.2) and (part == MAIN or part == SUFFIX):
            return random.choice(
                list(rv_zicsr.keys())
                + list(rv_zifencei.keys())
                + ["fence", "ecall", "ebreak", "mret", "sret"]
            )
        return super()._select_opcode(part)


class InterruptGenerator(BaseInstGenerator):
    templates = [0, 1, 2]

    def _select_opcode(self, part: str) -> str:
        if (random.random() < 0.3) and (part == MAIN):
            return "csrrs"
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):

        def _word_csrrs(opcode, syntax, xregs, fregs, imms, symbols):
            tpe = CSR
            offset = random.randint(0, 16)
            insts = ["li xreg1, {}".format(1 << offset), "csrs mip, xreg1"]
            insts.append(syntax.format("mie"))

            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["csrrs"]:
            inst_type, insts = _word_csrrs(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        return inst_type, insts


class ExceptionGenerator(BaseInstGenerator):
    templates = [0, 1, 2]

    def _select_opcode(self, part: str) -> str:
        if (random.random() < 0.2) and (part == MAIN or part == SUFFIX):
            return random.choices(
                ["jalr", "ebreak", "lw", "sw", "ecall"], weights=[1, 2, 10, 10, 2]
            )[0]
            # return random.choice(["jalr", "ebreak", "lw", "sw", "ecall"])
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):

        def rand_addr_j():
            misalign = random.randint(0x80002000, 0x80003000)
            while misalign % 4 == 0:
                misalign = random.randint(0x80002000, 0x80003000)
            return misalign

        def rand_addr_d():
            rand = random.random()
            if rand < 0.9:
                misalign = random.randint(0x80003000, 0x80050000)
                while misalign % 4 == 0:
                    misalign = random.randint(0x80003000, 0x80050000)
                return misalign
            else:
                fault_addr = random.randint(0x0, 0xFFFFFFFF)
                return fault_addr

        def _word_jalr(opcode, syntax, xregs, fregs, imms, symbols):
            tpe = CF_J

            insts = ["li xreg1, {}".format(rand_addr_j()), syntax]

            return (tpe, insts)

        def _word_mem(opcode, syntax, xregs, fregs, imms, symbols):
            if opcode == "sw":
                tpe = MEM_W
            elif opcode == "lw":
                tpe = MEM_R
            addr = rand_addr_d()
            insts = ["li xreg1, {}".format(addr), syntax]
            return (tpe, insts)

        def _word_ecall(opcode, syntax, xregs, fregs, imms, symbols):
            tpe = NONE
            if random.random() < 0.7:
                v = random.choice([0x1 << 11, 0])
                insts = ["li xreg0, {}".format(v), "csrw mstatus, xreg0", syntax]
                xregs.append("xreg0")
            else:
                insts = [syntax]
            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["jalr"]:
            inst_type, insts = _word_jalr(opcode, syntax, xregs, fregs, imms, symbols)
        elif opcode in ["lw", "sw"]:
            inst_type, insts = _word_mem(opcode, syntax, xregs, fregs, imms, symbols)
        elif opcode in ["ecall"]:
            inst_type, insts = _word_ecall(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        if random.random() < 0.05 and len(insts) > 2:
            random_position = random.randint(0, len(insts))
            insts.insert(
                random_position, ".word 0x{:X}".format(random.randint(0x0, 0xFFFF))
            )
        return inst_type, insts


class CounterTimerGenerator(BaseInstGenerator):
    templates = [0, 1, 2]

    def _select_opcode(self, part: str) -> str:
        if (random.random() < 0.3) and (part == MAIN or part == SUFFIX):
            return random.choice(["csrrw", "csrrs", "csrrc"])
        return super()._select_opcode(part)

    def _process_opcode(self, opcode, syntax, xregs, fregs, imms, symbols):
        def _word_csr(opcode, syntax, xregs, fregs, imms, symbols):
            tpe = CSR
            reg = random.choice(counter_timers + csr_names)
            if reg == "time":
                insts = [
                    "csrr xreg1, {}".format(reg),
                    "addi xreg1, xreg1, {}".format(
                        random.choice([0x1, 0x2, 0x100, -2048, 2047, -1, 0x80])
                    ),
                ]
            else:
                k = random.randint(0, 10)
                insts = []
                while k > 0:
                    insts.append(syntax.format(reg))
                    k -= 1
            insts.append(syntax.format(reg))

            return (tpe, insts)

        inst_type = NONE
        insts = [syntax]

        if opcode in ["csrrw", "csrrs", "csrrc"]:
            inst_type, insts = _word_csr(opcode, syntax, xregs, fregs, imms, symbols)
        else:
            for key, (opcodes_set, handler) in opcodes_words.items():
                if opcode in opcodes_set:
                    inst_type, insts = handler(
                        opcode, syntax, xregs, fregs, imms, symbols
                    )
                    break

        return inst_type, insts


# class MemoryInstGenerator(BaseInstGenerator):
#     def _select_opcode(self, part: str) -> str:
#         if part == MAIN:
#             # Prioritize memory access instructions
#             mem_ops = [op for op in self.opcodes if op in MEMORY_OPCODES]
#             if mem_ops:
#                 return random.choice(mem_ops)
#         return super()._select_opcode(part)


# 使用示例
# generator = PrivilegedInstGenerator(isa="RV64G")
# word = generator.get_word(part=MAIN)
