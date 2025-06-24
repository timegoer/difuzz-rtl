#*********************************************************************
# rv64-v.S (修改版)
#---------------------------------------------------------------------
#include "riscv_test.h"
#include "fuzz_test.h"

#define TESTEND gp

RVTEST_RV64UF

// RVTEST_CODE_BEGIN
.section .text.init;
.align  6;
.weak stvec_handler;
.weak mtvec_handler;
.global _start;
_start:
    INIT_XREGS
    j reset_vector;
    .align;
init_freg:
    INIT_FREGS
    ret
    .align;
trap_stvec:
    clear_sie;
_fuzz_suffix:
    /**/
_end_suffix:
    csrr  t1, sepc
    addi  t1, t1, 4
    csrw  sepc, t1
    addi sp, sp, 32
    sret

.align 4;
trap_mtvec: 
    clear_mie
    csrr  t1, mepc
    addi  t1, t1, 4
    csrw  mepc, t1
    addi sp, sp, 32
    mret

.align 4;
trap_hsvec:
    csrr t0, scause
    li t1, CAUSE_FETCH_PAGE_FAULT
    beq t0, t1, handle_vm_fault
    li t1, CAUSE_LOAD_PAGE_FAULT
    beq t0, t1, handle_vm_fault
    li t1, CAUSE_STORE_PAGE_FAULT
    beq t0, t1, handle_vm_fault
    
    # 其他异常处理
    j _fuzz_suffix

handle_vm_fault:
    # 简化处理：跳过错误指令
    csrr t0, sepc
    addi t0, t0, 4
    csrw sepc, t0
    sret

reset_vector:
    csrwi mstatus, 0
    RISCV_MULTICORE_DISABLE
    DELEGATE_NO_TRAPS
    INIT_SATP
    INIT_PMP
    la t0, trap_mtvec
    csrw mtvec, t0
    li TESTEND, 0
    CHECK_XLEN
    
    # 设置stvec为HS模式处理程序
    la t0, trap_hsvec
    csrw stvec, t0
    
    # 启用H扩展
    li t0, MSTATUS_H
    csrs mstatus, t0
    
    # 委托虚拟机异常到HS模式
    li t0, (1 << CAUSE_LOAD_PAGE_FAULT) | \
            (1 << CAUSE_STORE_PAGE_FAULT) | \
            (1 << CAUSE_FETCH_PAGE_FAULT) | \
            (1 << CAUSE_MISALIGNED_FETCH) | \
            (1 << CAUSE_USER_ECALL) | \
            (1 << CAUSE_BREAKPOINT)
    csrs medeleg, t0
    
    # 初始化hgatp（G-stage页表）
    li t0, 0x80000000  # 假设的GPA基址
    slli t0, t0, 44
    ori t0, t0, 8      # Sv48x4模式
    csrw hgatp, t0
    
    # 设置虚拟机入口点
    la t0, vm_entry
    csrw mepc, t0
    # ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

    li a0, (MSTATUS_FS & (MSTATUS_FS >> 0))
    csrs mstatus, a0
    init_mie
    csrwi fcsr, 0
    call init_freg
    csrw minstret,zero
    csrr a0, mhartid
    
_fuzz_prefix:
    /**/
_end_prefix:
    addi t0, zero, 0
    mret

# ▼▼▼▼▼▼▼ 关键修改3：新增虚拟机入口点 ▼▼▼▼▼▼▼
.align 6
vm_entry:
    # 进入HS模式
    li t0, MSTATUS_SPP
    csrc mstatus, t0
    li t0, (1 << MSTATUS_SPIE_SHIFT)
    csrs mstatus, t0
    
    la t0, vm_main
    csrw mepc, t0
    mret

.align 6
vm_main:
    # 配置虚拟机环境
    li t0, (SSTATUS_SPP | SSTATUS_SPIE)
    csrs sstatus, t0
    
    # 设置VS-mode satp
    li t0, 0x80000000  # 假设的VS-stage页表基址
    slli t0, t0, 44
    ori t0, t0, 9      # Sv48模式
    csrw satp, t0
    sfence.vma
    
    # 进入VU模式
    la t0, main
    csrw sepc, t0
    li t0, SSTATUS_SPP
    csrc sstatus, t0
    sret
# ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

main:
_fuzz_main:
    /**/
    
_good_exit:
    li a0, 0
    li TESTEND, 1
    sw TESTEND, tohost, t5
    .word 0x5006b
    1: j 1b

// RVTEST_CODE_END
_end_main:

.data
RVTEST_DATA_BEGIN

        .align 8
xreg_output_data:
reg_x0_output:  .dword 0x0000000000000000
reg_x1_output:  .dword 0x0000000000000000
reg_x2_output:  .dword 0x0000000000000000
reg_x3_output:  .dword 0x0000000000000000
reg_x4_output:  .dword 0x0000000000000000
reg_x5_output:  .dword 0x0000000000000000
reg_x6_output:  .dword 0x0000000000000000
reg_x7_output:  .dword 0x0000000000000000
reg_x8_output:  .dword 0x0000000000000000
reg_x9_output:  .dword 0x0000000000000000
reg_x10_output: .dword 0x0000000000000000
reg_x11_output: .dword 0x0000000000000000
reg_x12_output: .dword 0x0000000000000000
reg_x13_output: .dword 0x0000000000000000
reg_x14_output: .dword 0x0000000000000000
reg_x15_output: .dword 0x0000000000000000
reg_x16_output: .dword 0x0000000000000000
reg_x17_output: .dword 0x0000000000000000
reg_x18_output: .dword 0x0000000000000000
reg_x19_output: .dword 0x0000000000000000
reg_x20_output: .dword 0x0000000000000000
reg_x21_output: .dword 0x0000000000000000
reg_x22_output: .dword 0x0000000000000000
reg_x23_output: .dword 0x0000000000000000
reg_x24_output: .dword 0x0000000000000000
reg_x25_output: .dword 0x0000000000000000
reg_x26_output: .dword 0x0000000000000000
reg_x27_output: .dword 0x0000000000000000
reg_x28_output: .dword 0x0000000000000000
reg_x29_output: .dword 0x0000000000000000
reg_x30_output: .dword 0x0000000000000000
reg_x31_output: .dword 0x0000000000000000

        .align 8
freg_output_data:
reg_f0_output:  .dword 0x0000000000000000
reg_f1_output:  .dword 0x0000000000000000
reg_f2_output:  .dword 0x0000000000000000
reg_f3_output:  .dword 0x0000000000000000
reg_f4_output:  .dword 0x0000000000000000
reg_f5_output:  .dword 0x0000000000000000
reg_f6_output:  .dword 0x0000000000000000
reg_f7_output:  .dword 0x0000000000000000
reg_f8_output:  .dword 0x0000000000000000
reg_f9_output:  .dword 0x0000000000000000
reg_f10_output: .dword 0x0000000000000000
reg_f11_output: .dword 0x0000000000000000
reg_f12_output: .dword 0x0000000000000000
reg_f13_output: .dword 0x0000000000000000
reg_f14_output: .dword 0x0000000000000000
reg_f15_output: .dword 0x0000000000000000
reg_f16_output: .dword 0x0000000000000000
reg_f17_output: .dword 0x0000000000000000
reg_f18_output: .dword 0x0000000000000000
reg_f19_output: .dword 0x0000000000000000
reg_f20_output: .dword 0x0000000000000000
reg_f21_output: .dword 0x0000000000000000
reg_f22_output: .dword 0x0000000000000000
reg_f23_output: .dword 0x0000000000000000
reg_f24_output: .dword 0x0000000000000000
reg_f25_output: .dword 0x0000000000000000
reg_f26_output: .dword 0x0000000000000000
reg_f27_output: .dword 0x0000000000000000
reg_f28_output: .dword 0x0000000000000000
reg_f29_output: .dword 0x0000000000000000
reg_f30_output: .dword 0x0000000000000000
reg_f31_output: .dword 0x0000000000000000

        .align 8
csr_output_data:
ustatus_output:        .dword 0x0000000000000000                   
uie_output:            .dword 0x0000000000000000               
utvec_output:          .dword 0x0000000000000000                 
uscratch_output:       .dword 0x0000000000000000                    
uepc_output:           .dword 0x0000000000000000                
ucause_output:         .dword 0x0000000000000000                  
utval_output:          .dword 0x0000000000000000                 
uip_output:            .dword 0x0000000000000000               
fflags_output:         .dword 0x0000000000000000                 
frm_output:            .dword 0x0000000000000000               
fcsr_output:           .dword 0x0000000000000000                
sstatus_output:        .dword 0x0000000000000000                   
sedeleg_output:        .dword 0x0000000000000000                   
sideleg_output:        .dword 0x0000000000000000                   
sie_output:            .dword 0x0000000000000000               
stvec_output:          .dword 0x0000000000000000                 
scounteren_output:     .dword 0x0000000000000000                      
sscratch_output:       .dword 0x0000000000000000                    
sepc_output:           .dword 0x0000000000000000                
scause_output:         .dword 0x0000000000000000                  
stval_output:          .dword 0x0000000000000000                 
sip_output:            .dword 0x0000000000000000               
satp_output:           .dword 0x0000000000000000                
mhartid_output:        .dword 0x0000000000000000                   
mstatus_output:        .dword 0x0000000000000000                   
medeleg_output:        .dword 0x0000000000000000                   
mideleg_output:        .dword 0x0000000000000000                   
mie_output:            .dword 0x0000000000000000               
mtvec_output:          .dword 0x0000000000000000                 
mcounteren_output:     .dword 0x0000000000000000                      
mscratch_output:       .dword 0x0000000000000000                    
mepc_output:           .dword 0x0000000000000000                
mcause_output:         .dword 0x0000000000000000                  
mtval_output:          .dword 0x0000000000000000                 
mip_output:            .dword 0x0000000000000000               
pmpcfg0_output:        .dword 0x0000000000000000                   
pmpcfg1_output:        .dword 0x0000000000000000                   
pmpcfg2_output:        .dword 0x0000000000000000                   
pmpcfg3_output:        .dword 0x0000000000000000                   
pmpaddr0_output:       .dword 0x0000000000000000                    
pmpaddr1_output:       .dword 0x0000000000000000                    
pmpaddr2_output:       .dword 0x0000000000000000                    
pmpaddr3_output:       .dword 0x0000000000000000                    
pmpaddr4_output:       .dword 0x0000000000000000                    
pmpaddr5_output:       .dword 0x0000000000000000                    
pmpaddr6_output:       .dword 0x0000000000000000                    
pmpaddr7_output:       .dword 0x0000000000000000                    
pmpaddr8_output:       .dword 0x0000000000000000                    
pmpaddr9_output:       .dword 0x0000000000000000                    
pmpaddr10_output:      .dword 0x0000000000000000                     
pmpaddr11_output:      .dword 0x0000000000000000                     
pmpaddr12_output:      .dword 0x0000000000000000                     
pmpaddr13_output:      .dword 0x0000000000000000                     
pmpaddr14_output:      .dword 0x0000000000000000                     
pmpaddr15_output:      .dword 0x0000000000000000                     
mcycle_output:         .dword 0x0000000000000000                         
minstret_output:       .dword 0x0000000000000000                    
mcycleh_output:        .dword 0x0000000000000000                   
minstreth_output:      .dword 0x0000000000000000                     

RVTEST_DATA_END  

PT_BASES

    .section .data.random0;
    .align  8;

_random_data0:
        /* Random data */
_end_data0:
                 

    .section .data.random1;
    .align  8;

_random_data1:
        /* Random data */
_end_data1:


    .section .data.random2;
    .align  8;

_random_data2:
         /* Random data */
_end_data2:
                

    .section .data.random3;
    .align  8;

_random_data3:
        /* Random data */
_end_data3:


    .section .data.random4;
    .align  8;

_random_data4:
        /* Random data */
_end_data4:


    .section .data.random5;
    .align  8;

_random_data5:
         /* Random data */
_end_data5: