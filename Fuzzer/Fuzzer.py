import shlex
import subprocess
import time
import random

from cocotb.decorators import coroutine
from RTLSim.host import ILL_MEM, SUCCESS, TIME_OUT, ASSERTION_FAIL

from config import *
from mutator import PT, V_U
from src.utils import *
from src.multicore_manager import proc_state

# 魔数和配置参数
CORPUS_UPDATE_INTERVAL = 1000
NEMU_TIMEOUT = 1  # 秒
DEFAULT_CORPUS_SIZE = 1000

# 路径配置
# NEMU_BINARY = "/nfs/home/changgen/xs-env/NEMU/build/riscv64-nemu-interpreter"
# EMU_BINARY = "/nfs/home/changgen/xs-env/XiangShan/build/emu"
# DIFF_SO_PATH = "/nfs/home/changgen/xs-env/NEMU/ready-to-run/riscv64-nemu-interpreter-so"
# FUZZ_EMU = 0

# 目录名称
CORPUS_DIR = "corpus"
MISMATCH_DIR = "mismatch"
ILLEGAL_DIR = "illegal"
EMU_MISMATCH_DIR = "emu_mismatch"


def run_nemu_test(proc_num: int, output_dir: str) -> int:
    """执行NEMU测试并返回状态码"""
    input_file = f"{output_dir}/.input_{proc_num}.bin"
    cmd = shlex.split(f"{NEMU_BINARY} -b {input_file}")

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=NEMU_TIMEOUT,
            check=True,
        )
        return result.returncode
    except subprocess.TimeoutExpired:
        print("NEMU timeout")
        return -1  # 超时状态码
    except subprocess.CalledProcessError as e:
        print(f"NEMU fail returncode: {e.returncode}")
        return e.returncode


@coroutine
def Run(
    dut,
    toplevel,
    num_iter=1,
    template="Template",
    in_file=None,
    out="output",
    record=False,
    cov_log=None,
    multicore=0,
    manager=None,
    proc_num=0,
    start_time=0,
    start_iter=0,
    start_cov=0,
    prob_intr=0,
    no_guide=False,
    debug=False,
):
    assert toplevel in ["RocketTile", "BoomTile"], f"{toplevel} not valid top module"
    random.seed(time.time() * (proc_num + 1))

    components = setup(dut, toplevel, template, out, proc_num, debug, no_guide=no_guide)
    mutator, preprocessor, isaHost, rtlHost, checker = components

    if in_file:
        num_iter = 1

    stop_flag = [proc_state.NORMAL]
    mismatch_count = 0
    coverage_count = 0
    illegal_count = 0
    last_coverage = 0

    debug_print("[DifuzzRTL] start fuzz", debug)

    if multicore:
        yield manager.cov_restore(dut)

    for iteration in range(num_iter):
        if multicore:
            if iteration == 0:
                mutator.update_corpus(f"{out}/{CORPUS_DIR}", DEFAULT_CORPUS_SIZE)
            elif iteration % CORPUS_UPDATE_INTERVAL == 0:
                mutator.update_corpus(f"{out}/{CORPUS_DIR}")

        # 生成或读取测试输入
        assert_intr = random.random() < prob_intr
        if in_file:
            sim_input, data, assert_intr = mutator.read_siminput(in_file)
            generator_name = "from_file"
        else:
            sim_input, data, generator_name = mutator.get(assert_intr)

        # 打印调试信息
        if debug:
            print("[DifuzzRTL] fuzz inst list")
            for inst, INT in zip(sim_input.get_insts(), sim_input.ints + [0]):
                print(f"{inst:<50}{INT:04b}")

        print("[DifuzzRTL] process")
        processed = preprocessor.process(sim_input, data, assert_intr)
        isa_input, rtl_input, symbols, version = processed

        if not (isa_input and rtl_input):
            stop_flag[0] = proc_state.ERR_COMPILE
            print("[DifuzzRTL] break")
            break

        # ============= ISA 测试阶段 =============
        print("[DifuzzISA] start ISA fuzz")
        isa_ret = run_isa_test(isaHost, isa_input, stop_flag, out, proc_num)

        if isa_ret == proc_state.ERR_ISA_TIMEOUT:
            print("[DifuzzISA] ISA timeout")
            continue
        elif isa_ret == proc_state.ERR_ISA_ASSERT:
            print("[DifuzzISA] ISA assert fail", isa_ret)
            continue

        print(f"[DifuzzISA] ISA return: {isa_ret}")

        # ============= RTL 测试阶段 =============
        if version not in [V_U, PT]:  # RTL 测试
            print("[DifuzzRTL] RTL fuzz")
            rtl_result = yield rtlHost.run_test(rtl_input, assert_intr)
            rtl_ret, coverage = rtl_result

            # 中断处理逻辑
            if assert_intr and rtl_ret == SUCCESS:
                intr_prv, epc = checker.check_intr(symbols)
                if epc != 0:
                    preprocessor.write_isa_intr(isa_input, rtl_input, epc)
                    isa_ret = run_isa_test(
                        isaHost, isa_input, stop_flag, out, proc_num, True
                    )
                    if isa_ret != SUCCESS:
                        continue
                else:
                    continue

            # 结果验证逻辑
            cause = "-"
            match = False

            if rtl_ret == SUCCESS:
                match = checker.check(symbols)
            elif rtl_ret == ILL_MEM:
                match = True
                debug_print(f"[DifuzzRTL] illegal mem -- {illegal_count}", debug, True)
                if record:
                    save_mismatch(
                        out,
                        proc_num,
                        f"{out}/{ILLEGAL_DIR}",
                        sim_input,
                        data,
                        illegal_count,
                    )
                illegal_count += 1

            # 不匹配处理
            if not match or rtl_ret not in [SUCCESS, ILL_MEM]:
                if multicore:
                    mismatch_count = manager.read_num("mNum")
                    manager.write_num("mNum", mismatch_count + 1)

                if record:
                    save_mismatch(
                        out,
                        proc_num,
                        f"{out}/{MISMATCH_DIR}",
                        sim_input,
                        data,
                        mismatch_count,
                        generator_name,
                    )

                mismatch_count += 1
                if rtl_ret == TIME_OUT:
                    cause = "timeout"
                    print("[DifuzzRTL] RTL timeout")
                    continue
                elif rtl_ret == ASSERTION_FAIL:
                    cause = "assert fail"
                    print("[DifuzzRTL] RTL assert fail")
                else:
                    cause = "mismatch"
                    print("[DifuzzRTL] RTL mismatch")

                debug_print(
                    f"[DifuzzRTL] find bug -- {mismatch_count} [{cause}]",
                    debug,
                    not match or (rtl_ret != SUCCESS),
                )

            # ============= NEMU/EMU 验证阶段 =============
            print(f"[DifuzzRTL] cov: {coverage}")

            print("[DifuzzRTL] NEMU fuzz")
            nemu_ret = run_nemu_test(proc_num, out)
            if nemu_ret != 0:
                continue  # NEMU失败跳过后续
            print(f"[DifuzzNEMU] iter [{iteration}] PASS")
            if FUZZ_EMU == 1:
                print("[DifuzzRTL] EMU fuzz")
                input_bin = f"{out}/.input_{proc_num}.bin"
                emu_ret = subprocess.call(
                    [EMU_BINARY, "--diff", DIFF_SO_PATH, "-i", input_bin],
                    stderr=subprocess.DEVNULL,
                )

                if emu_ret != 0:
                    print(f"[DifuzzEMU] iter [{iteration}] FAIL")
                    if record:
                        save_mismatch(
                            out,
                            proc_num,
                            f"{out}/{EMU_MISMATCH_DIR}",
                            sim_input,
                            data,
                            coverage_count,
                            generator_name,
                        )
                else:
                    print(f"[DifuzzEMU] iter [{iteration}] PASS")

            # ============= 覆盖引导逻辑 =============
            if coverage > last_coverage:
                print(f"[DifuzzRTL] iter [{iteration}]")
                debug_print(f"[DifuzzRTL] iter [{iteration}]", debug)

                if multicore:
                    coverage_count = manager.read_num("cNum")
                    manager.write_num("cNum", coverage_count + 1)

                if record:
                    cov_log_entry = "{:<10}\t{:<10}\t{:<10}\n".format(
                        time.time() - start_time,
                        start_iter + iteration,
                        start_cov + coverage,
                    )
                    save_file(cov_log, "a", cov_log_entry)

                    save_mismatch(
                        out,
                        proc_num,
                        f"{out}/{CORPUS_DIR}",
                        sim_input,
                        data,
                        coverage_count,
                        generator_name,
                    )

                # 更新迭代状态
                last_coverage = coverage
                coverage_count += 1
                mutator.add_corpus(sim_input)
                mutator.update_phase(iteration)

        else:
            print("[DifuzzRTL] NEMU fuzz")
            nemu_ret = run_nemu_test(proc_num, out)
            if nemu_ret != 0:
                continue  # NEMU失败跳过后续
            print(f"[DifuzzNEMU] iter [{iteration}] PASS")

            if FUZZ_EMU == 1:
                emu_ret = subprocess.call(
                    [EMU_BINARY, "--diff", DIFF_SO_PATH, "-i", input_bin],
                    stderr=subprocess.DEVNULL,
                )

                if emu_ret != 0:
                    print(f"[DifuzzEMU] iter [{iteration}] FAIL")
                    save_mismatch(
                        out,
                        proc_num,
                        f"{out}/{EMU_MISMATCH_DIR}",
                        sim_input,
                        data,
                        coverage_count,
                        generator_name,
                    )
                else:
                    print(f"[DifuzzEMU] iter [{iteration}] PASS")
                    save_mismatch(
                        out,
                        proc_num,
                        f"{out}/{CORPUS_DIR}",
                        sim_input,
                        data,
                        coverage_count,
                        generator_name,
                    )

            coverage_count += 1
            mutator.add_corpus(sim_input)

    if multicore:
        save_err(out, proc_num, manager, stop_flag[0])
        manager.set_state(proc_num, stop_flag[0])
        yield manager.cov_store(dut, proc_num)
        manager.store_covmap(proc_num, start_time, start_iter, num_iter)

    debug_print("[DifuzzRTL] fuzz end", debug)
