import os
import random

from riscv_definitions import *

NONE = 0
CF_J = 1
CF_BR = 2
CF_RET = 3
MEM_R = 4
MEM_W = 5
CSR = 6

PREFIX = "_p"
MAIN = "_l"
SUFFIX = "_s"


class Word:
    def __init__(
        self,
        label: int,
        insts: list,
        tpe=NONE,
        xregs=[],
        fregs=[],
        imms=[],
        symbols=[],
        populated=False,
        label_prefix: str = "",
    ):
        self.label = label
        self.tpe = tpe
        self.insts = insts
        self.len_insts = len(insts)
        self.label_prefix = label_prefix

        self.xregs = xregs
        self.fregs = fregs
        self.imms = imms
        self.symbols = symbols
        self.operands = xregs + fregs + [imm[0] for imm in imms] + symbols

        self.populated = populated
        self.ret_insts = []

    def pop_inst(self, inst, opvals):
        for op, val in opvals.items():
            inst = inst.replace(op, val)

        return inst

    def populate(self, opvals, part=MAIN):
        for op in self.operands:
            assert op in opvals.keys(), "{} is not in label {} Word opvals".format(
                op, self.label
            )

        pop_insts = []
        for inst in self.insts:
            p_inst = self.pop_inst(inst, opvals)
            pop_insts.append(p_inst)

        ret_insts = [
            "{:<8}{:<42}".format(
                part + self.label_prefix + str(self.label) + ":", pop_insts.pop(0)
            )
        ]

        for i in range(len(pop_insts)):
            ret_insts.append("{:8}{:<42}".format("", pop_insts.pop(0)))

        self.populated = True
        self.ret_insts = ret_insts

    def reset_label(self, new_label, part):
        old_label = self.label
        self.label = new_label

        if self.populated:
            self.ret_insts[0] = "{:8}{:<42}".format(
                part + self.label_prefix + str(self.label) + ":", self.ret_insts[0][8:]
            )
            return (old_label, new_label)
        else:
            return None

    def repop_label(self, label_map, max_label, part):
        if self.populated:
            for i in range(len(self.ret_insts)):
                inst = self.ret_insts[i]
                tmps = inst.split(", " + part)

                if len(tmps) > 1:
                    label = tmps[1].split(" ")[0]

                    old = int(label)
                    new = label_map.get(old, random.randint(self.label + 1, max_label))

                    new_inst = inst[8:].replace(
                        part + self.label_prefix + "{}".format(old),
                        part + self.label_prefix + "{}".format(new),
                    )
                    inst = "{:<8}{:<50}".format(inst[0:8], new_inst)

                    self.ret_insts[i] = inst
        else:
            return

    def get_insts(self):
        assert self.populated, "Word is not populated"

        return self.ret_insts


def word_jal(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = CF_J
    insts = [syntax]
    return (tpe, insts)


def word_jalr(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = CF_J
    insts = ["la xreg1, symbol", syntax]
    symbols.append("symbol")

    return (tpe, insts)


# Need to update
def word_branch(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = CF_BR
    insts = [syntax]

    return (tpe, insts)


def word_ret(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = CF_RET
    if syntax == "mret":
        epc = "mepc"
    elif syntax == "sret":
        epc = "sepc"
    else:
        epc = "uepc"

    insts = ["la xreg0, symbol", "csrrw zero, {}, xreg0".format(epc), syntax]

    xregs.append("xreg0")
    symbols.append("symbol")

    return (tpe, insts)


def word_mem_r(opcode, syntax, xregs, fregs, imms, symbols):

    tpe = MEM_R
    rand = random.random()
    if rand < 0.1:
        mask_addr = ["lui xreg2, 0xffe00", "xor xreg1, xreg1, xreg2"]
        xregs.append("xreg2")
    else:
        mask_addr = []

    insts = ["la xreg1, symbol"] + mask_addr + [syntax]
    symbols.append("symbol")

    return (tpe, insts)


def word_mem_w(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = MEM_W
    rand = random.random()
    if rand < 0.1:
        mask_addr = ["lui xreg2, 0xffe00", "xor xreg1, xreg1, xreg2"]
        xregs.append("xreg2")
    else:
        mask_addr = []

    insts = ["la xreg1, symbol"] + mask_addr + [syntax]
    symbols.append("symbol")

    return (tpe, insts)


def word_atomic(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = MEM_W
    rand = random.random()
    if rand < 0.1:
        mask_addr = ["lui xreg2, 0xffe00", "xor xreg1, xreg1, xreg2"]
        xregs.append("xreg2")
    else:
        mask_addr = []

    insts = ["la xreg1, symbol", "addi xreg1, xreg1, imm6"] + mask_addr + [syntax]

    if opcode in rv64.keys():
        imms.append(("imm6", 8))
    else:
        imms.append(("imm6", 4))
    symbols.append("symbol")

    return (tpe, insts)


def csr_randint(csr_name):
    if csr_name in ["mstatus", "sstatus", "vsstatus"]:
        # 状态寄存器: 组合关键标志位
        mie = random.randint(0, 1) << 3  # 中断使能
        mpie = random.randint(0, 1) << 7  # 先前中断状态
        mpp = random.choice([0, 1, 3]) << 11  # 特权级
        fs = random.choice([0, 1, 3]) << 13  # 浮点状态
        sd = random.randint(0, 1) << 31  # 状态脏位
        return mie | mpie | mpp | fs | sd

    elif csr_name in ["mip", "sip", "vsip"]:
        # 中断挂起寄存器: 设置随机中断位
        return (
            random.randint(0, 1)
            | (random.randint(0, 1) << 1)
            | (random.randint(0, 1) << 5)
            | (random.randint(0, 1) << 9)
        )

    elif csr_name in ["mie", "sie", "vsie"]:
        # 中断使能寄存器: 使能随机中断
        return (
            random.randint(0, 1)
            | (random.randint(0, 1) << 3)
            | (random.randint(0, 1) << 7)
            | (random.randint(0, 1) << 11)
        )

    elif csr_name in ["hstatus", "vsstatus"]:
        # Hypervisor状态寄存器: 关键位组合
        spv = random.randint(0, 1) << 7  # 先前虚拟化状态
        hu = random.randint(0, 1) << 9  # Hypervisor用户模式
        vgein = random.randint(0, 63) << 18  # 虚拟中断号
        return spv | hu | vgein

    elif csr_name in ["satp", "vsatp"]:
        # 地址转换寄存器: 模式+ASID+PPN
        mode = random.choice([0, 8, 9]) << 60  # Sv39/Sv48模式
        asid = random.randint(0, 0xFFFF) << 44
        ppn = random.randint(0, 0xFFFFF)
        return mode | asid | ppn

    elif csr_name in ["0xBC2"]:
        cmode = random.choice([0, 1])
        b_clear = random.choice([0, 1]) << 1
        bme = random.choices([0, 1], [0.1, 0.9])[0] << 2
        bma = random.randint(0x800000000, 0xA00000000) << 3
        return cmode | b_clear | bme | bma

    elif csr_name in ["0xBC3"]:
        MODE = random.choices([0, 1, 2, 3], [0.1, 0.3, 0.3, 0.3])[0]
        if MODE == 0:
            PPN = 0
            SDID = 0
        else:
            PPN = 0x80032000
            SDID = random.randint(0, 0x3F) << 54

        return (MODE << 60) | PPN | SDID

    elif csr_name in ["menvcfg", "senvcfg", "henvcfg"]:
        CBIE = random.choice([0, 1, 3]) << 4
        CBCFE = random.choice([0, 1]) << 6
        CBZE = random.choice([0, 1]) << 7
        return CBIE | CBCFE | CBZE

    # 其他寄存器生成完全随机值
    return (
        random.randint(0, 0xFFFFFFFF)
        if "s" in csr_name
        else random.randint(0, 0xFFFFFFFFFFFFFFFF)
    )


def word_csr_csrs(opcode, syntax, xregs, fregs, imms, symbols, csrs_list):
    if random.random() < 0.99:
        csr = random.choice(csrs_list)
    else:
        csr = "0x{:x}".format(random.randint(0x000, 0xFFF))

    if "pmpaddr" in csr and opcode in ["csrrw", "csrrs", "csrrc"]:
        tpe = MEM_R
        insts = ["la xreg1, symbol", "srai xreg1, xreg1, 1", syntax.format(csr)]
        symbols.append("symbol")
    else:
        tpe = CSR
        # 使用安全的临时寄存器 (x5-x7, x28-x31)
        temp_regs = ["x5", "x6", "x7", "x28", "x29", "x30", "x31"]
        rd = random.choice(temp_regs)
        rs1 = random.choice(temp_regs)

        # 构建上下文序列
        insts = []

        # 1. 随机设置特权级上下文
        if random.random() < 0.3:
            insts.append("csrwi mstatus, 0")
            if random.random() < 0.2:
                insts.append("csrwi mie, 0")

        # 2. 准备源寄存器值
        if opcode in ["csrrw", "csrrs", "csrrc"]:  # 寄存器源操作数
            # 多种寄存器初始化策略
            strategy = random.choices([0, 1, 2, 3], [0.1, 0.1, 0.7, 0.1])[0]
            if strategy == 0:  # 清零
                insts.append(f"mv {rs1}, zero")
            elif strategy == 1:  # 全1
                insts.append(f"li {rs1}, -1")
            elif strategy == 2:  # 随机位掩码
                insts.append(f"li {rs1}, {csr_randint(csr)}")
            else:  # 保留随机值 (测试未初始化寄存器)
                pass
        else:  # 立即数操作
            imm = csr_randint(csr) & 31
            rs1 = str(imm)  # 立即数直接嵌入指令

        # 4. 生成CSR指令
        if opcode in ["csrrw", "csrrs", "csrrc"]:
            insts.append(f"{opcode} {rd}, {csr}, {rs1}")
        else:  # 立即数版本
            insts.append(f"{opcode} {rd}, {csr}, {rs1}")

        # 5. 添加结果使用指令 (防止优化并增加状态变化)
        if random.random() < 0.8:
            insts.append(f"addi x{random.randint(0,31)}, {rd}, 0")  # 伪使用
        if random.random() < 0.3:
            insts.append(f"sw {rd}, 0(sp)")

    return (tpe, insts)


def word_csr(opcode, syntax, xregs, fregs, imms, symbols):
    return word_csr_csrs(opcode, syntax, xregs, fregs, imms, symbols, csr_names)


def word_sfence(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = NONE
    pt_symbol = random.choice(["pt0", "pt1", "pt2", "pt3"])

    imms += [("uimm1", 1), ("uimm6", 8)]
    insts = [
        "li xreg0, uimm1",
        "la xreg1, {}".format(pt_symbol),
        "addi xreg1, xreg1, uimm6",
    ] + [syntax]

    return (tpe, insts)


def word_fp(opcode, syntax, xregs, fregs, imms, symbols):
    tpe = NONE
    # rm = random.choice([ 'rne', 'rtz', 'rdn',
    #                      'rup', 'rmm', 'dyn'])
    # Unset rounding mode testing
    rm = "rne"

    insts = [syntax.format(rm)]

    return (tpe, insts)


""" Opcodes_words
Dictionary of opcodes - word generation functions
to handle opcodes which need special instructions
"""
opcodes_words = {
    "jal": (["jal"], word_jal),
    "jalr": (["jalr"], word_jalr),
    "branch": (list(rv32i_btype.keys()), word_branch),
    "ret": (["mret", "sret", "uret"], word_ret),
    "mem_r": (
        ["lb", "lh", "lw", "ld", "lbu", "lhu", "lwu", "flw", "fld", "flq"],
        word_mem_r,
    ),
    "mem_w": (["sb", "sh", "sw", "sd", "fsw", "fsd", "fsq"], word_mem_w),
    "atomic": (list(rv32a.keys()) + list(rv64a.keys()), word_atomic),
    "csr": (["csrrw", "csrrs", "csrrc", "csrrwi", "csrrsi", "csrrci"], word_csr),
    "sfence": (["sfence.vma"], word_sfence),
    "fp": (
        list(rv32f.keys())
        + list(rv64f.keys())
        + list(rv32d.keys())
        + list(rv64d.keys())
        + list(rv32q.keys())
        + list(rv64q.keys()),
        word_fp,
    ),
}
