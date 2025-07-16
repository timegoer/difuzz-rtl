# RISC-V Hypervisor Fuzzer Template
# See LICENSE for license details.

#include "riscv_test.h"
#include "fuzz_test.h"

#define STORE    sd
#define LOAD     ld
#define REGBYTES 8
#define TESTEND gp

# 页表配置常量
#define PAGE_SHIFT 12
#define PAGE_SIZE (1 << PAGE_SHIFT)
#define PAGE_MASK (~(PAGE_SIZE-1))

# 虚拟地址划分 (Sv39)
#define VPN0_SHIFT 12
#define VPN0_BITS 9
#define VPN1_SHIFT (VPN0_SHIFT + VPN0_BITS)
#define VPN1_BITS 9
#define VPN2_SHIFT (VPN1_SHIFT + VPN1_BITS)
#define VPN2_BITS 9

# Hypervisor CSR definitions
#define hstatus 0x600
#define hedeleg 0x602
#define hideleg 0x603
#define hie 0x604
#define hcounteren 0x606
#define hgeie 0x607
#define hedelegh 0x612
#define htval 0x643
#define hip 0x644
#define hvip 0x645
#define htinst 0x64A
#define hgeip 0xE12
#define henvcfg 0x60A
#define henvcfgh 0x61A
#define hgatp 0x680
#define hcontext 0x6A8
#define htimedelta 0x605
#define htimedeltah 0x615
#define hstateen0 0x60C
#define hstateen1 0x60D
#define hstateen2 0x60E
#define hstateen3 0x60F
#define hstateen0h 0x61C
#define hstateen1h 0x61D
#define hstateen2h 0x61E
#define hstateen3h 0x61F
#define vsstatus 0x200
#define vsie 0x204
#define vstvec 0x205
#define vsscratch 0x240
#define vsepc 0x241
#define vscause 0x242
#define vstval 0x243
#define vsip 0x244
#define vsatp 0x280

# Hypervisor CSR bits
#define HSTATUS_SPV (1 << 7)
#define HSTATUS_SPVP (1 << 8)
#define HSTATUS_VTVM (1 << 20)

# 页表权限位定义
#define PRW_V (1 << 0)  # 有效位
#define PRW_R (1 << 1)  # 可读位
#define PRW_W (1 << 2)  # 可写位
#define PRW_X (1 << 3)  # 可执行位

.section ".text.init","ax",@progbits
.globl _start
.align 2
_start:
  j reset_vector
  
# NMI vector
.align 2
nmi_vector:
  j _end_main

# Trap vector
.align 2
trap_vector:
  j _end_main

reset_vector:
  # 初始化基址寄存器
  INIT_XREGS
  li TESTEND, 0;

  # 启用FPU
  li a0, MSTATUS_FS
  csrs mstatus, a0
  call init_freg
  
  # 初始化页表和空闲页管理
  call init_page_tables
  call init_free_pages

  # 设置异常处理
  la t0, trap_stvec
  csrw stvec, t0
  la t0, trap_mtvec
  csrw mtvec, t0

  li t0, (1 << 7) | (0 << 6)  # SPV位=1, SPVP位=0
  csrw hstatus, t0
  li t0, 0x100  # 初始化vsstatus
  csrc vsstatus, t0  # 清除SPP位（位8）

  li t0, 0b11 << 11     # MPP位掩码 (位11-12)
  csrs mstatus, t0       # 设置MPP位为11

  la t0, _fuzz_main
  csrw mepc, t0
  mret

init_freg:
  INIT_FREGS
  ret
  .align 4

.global trap_stvec
trap_stvec:
  clear_sie
  csrr t1, sepc
  addi t1, t1, 4
  csrw sepc, t1
  sret

.global trap_mtvec
trap_mtvec:
  clear_mie
  # 保存寄存器
  addi sp, sp, -64
  
  csrr t0, mcause
  li t1, 1
  beq t0, t1, handle_access_fault
  li t1, 12           # 指令缺页
  beq t0, t1, handle_page_fault
  li t1, 13           # 加载缺页
  beq t0, t1, handle_page_fault
  li t1, 15           # 存储缺页
  beq t0, t1, handle_page_fault

  # 其他异常: 跳过指令
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  j trap_mtvec_exit

handle_access_fault:
  j _end_main


handle_page_fault:
  # 获取出错地址并4KB对齐
  csrr a0, mtval
  li t0, -4096
  and a0, a0, t0

  # 分配物理页
  call allocate_page
  mv a1, a0           # 物理地址

  # 根据异常类型设置权限
  csrr t0, mcause
  li t1, 12
  beq t0, t1, 1f      # 指令缺页
  li t1, 15
  beq t0, t1, 2f      # 存储缺页
  
  # 加载缺页: R权限
  li a2, PRW_V | PRW_R
  j 3f
1:
  # 指令缺页: RX权限
  li a2, PRW_V | PRW_R | PRW_X
  j 3f
2:
  # 存储缺页: RW权限
  li a2, PRW_V | PRW_R | PRW_W
3:
  # 建立映射
  call map_page
  sfence.vma         # 刷新TLB

trap_mtvec_exit:
  addi sp, sp, 64
  mret

#-----------------------------------------------------------------------
# 页表初始化
#-----------------------------------------------------------------------
init_page_tables:
  # 设置根页表条目
  la t0, root_page_table
  la t1, root_page_table
  li t4, 4096
  add t1, t1, t4   # 二级页表位置
  
  # 根页表条目: PPN=二级页表地址>>12, V=1
  srli t2, t1, 12
  slli t2, t2, 10
  ori t2, t2, PRW_V
  sd t2, 0(t0)        # 写入根页表第一个条目

  # 初始化二级页表 (映射低4MB内存)
  # 第一个2MB大页: 虚拟地址0 -> 物理地址0
  li t3, PRW_V | PRW_R | PRW_W | PRW_X
  sd t3, 0(t1)        # 二级页表第一个条目
  
  # 第二个2MB大页: 虚拟地址2MB -> 物理地址2MB
  li t4, 0x200000     # 2MB
  srli t4, t4, 2      # 转换为PPN格式
  slli t4, t4, 10
  or t4, t4, t3
  sd t4, 8(t1)        # 二级页表第二个条目

  # 设置hgatp寄存器 (Sv39x4模式)
  la t0, root_page_table
  srli t0, t0, 12     # PPN
  li t1, 8 << 60      # Sv39x4模式
  or t0, t0, t1
  csrw hgatp, t0
  
  # 刷新TLB
  sfence.vma
  ret

#-----------------------------------------------------------------------
# 空闲页初始化
#-----------------------------------------------------------------------
init_free_pages:
  la t0, free_page_start
  la t1, free_page_end
  la t2, free_page_list
  
  # 初始化空闲页链表
  li t3, 0
1:
  sd t3, 0(t0)        # 当前页指向上一页
  mv t3, t0           # 更新上一页指针
  li t4, 4096
  add t0, t0, t4   # 移动到下一页
  blt t0, t1, 1b      # 循环直到结束
  
  sd t3, free_page_list, t4  # 设置链表头
  ret

#-----------------------------------------------------------------------
# 页表操作函数
#-----------------------------------------------------------------------
# 分配物理页
# 返回: a0 = 物理地址 (0表示失败)
allocate_page:
  la t0, free_page_list
  ld a0, 0(t0)             # 获取空闲页
  beqz a0, 1f              # 无可用页
  ld t1, 0(a0)             # 获取下一空闲页
  sd t1, 0(t0)             # 更新链表头
  ret
1:
  li a0, 0                 # 分配失败
  ret

# 建立页表映射
# 参数: a0 = 虚拟地址, a1 = 物理地址, a2 = 权限
map_page:
  # 保存参数
  addi sp, sp, -32
  sd a1, 0(sp)
  sd a2, 8(sp)
  sd t0, 16(sp)
  sd t1, 24(sp)

  # 获取根页表地址
  csrr t0, hgatp
  srli t0, t0, 12
  slli t0, t0, 12          # 根页表物理地址

  # 计算VPN2索引 (虚拟地址[38:30])
  srli t1, a0, 30
  andi t1, t1, 0x1FF       # 9位索引
  slli t1, t1, 3
  add t1, t0, t1           # 三级条目地址
  ld t0, 0(t1)             # 加载三级条目
  andi t2, t0, PRW_V
  bnez t2, 1f              # 条目有效

  # 分配二级页表
  call allocate_page
  beqz a0, .map_fail       # 分配失败
  mv t2, a0
  # 初始化页表 (清零)
  li t3, 512
  mv t4, t2
1:
  sd zero, 0(t4)
  addi t4, t4, 8
  addi t3, t3, -1
  bnez t3, 1b

  # 设置三级条目
  srli t2, t2, 12
  slli t2, t2, 10
  ori t2, t2, PRW_V
  sd t2, 0(t1)
  mv t0, t2

1:
  # 获取二级页表地址
  srli t0, t0, 10
  slli t0, t0, 12          # 二级页表物理地址

  # 计算VPN1索引 (虚拟地址[29:21])
  srli t1, a0, 21
  andi t1, t1, 0x1FF       # 9位索引
  slli t1, t1, 3
  add t1, t0, t1           # 二级条目地址
  ld t0, 0(t1)             # 加载二级条目
  andi t2, t0, PRW_V
  bnez t2, 1f              # 条目有效

  # 分配一级页表
  call allocate_page
  beqz a0, .map_fail       # 分配失败
  mv t2, a0
  # 初始化页表 (清零)
  li t3, 512
  mv t4, t2
1:
  sd zero, 0(t4)
  addi t4, t4, 8
  addi t3, t3, -1
  bnez t3, 1b

  # 设置二级条目
  srli t2, t2, 12
  slli t2, t2, 10
  ori t2, t2, PRW_V
  sd t2, 0(t1)
  mv t0, t2

1:
  # 获取一级页表地址
  srli t0, t0, 10
  slli t0, t0, 12          # 一级页表物理地址

  # 计算VPN0索引 (虚拟地址[20:12])
  srli t1, a0, 12
  andi t1, t1, 0x1FF       # 9位索引
  slli t1, t1, 3
  add t1, t0, t1           # 一级条目地址

  # 恢复参数
  ld a1, 0(sp)
  ld a2, 8(sp)

  # 设置叶子条目
  srli a1, a1, 12          # 物理页号
  slli a1, a1, 10
  andi a2, a2, 0x0F        # 权限位
  or a1, a1, a2
  sd a1, 0(t1)

  # 恢复寄存器并返回
  ld t0, 16(sp)
  ld t1, 24(sp)
  addi sp, sp, 32
  ret

.map_fail:
  # 死循环 (页表映射失败)
  j .map_fail

#-----------------------------------------------------------------------
# Fuzzer Main Section
#-----------------------------------------------------------------------
.section .text
.global _fuzz_main
.align 4
_fuzz_main:
  # Fuzzer将在此处插入随机指令
  
  # 正常退出
  j _end_main

.section .text
.global _end_main
.align 4
_end_main:
  li a0, 0             # 设置a0=0表示正常退出
  .word 0x5006b        # 香山trap指令
  li TESTEND, 1
  sw TESTEND, tohost, t5;
  _test_end:
    j _test_end;

#-----------------------------------------------------------------------
# Data Sections
#-----------------------------------------------------------------------

.section .data
.align 12
root_page_table:
  .skip 4096 * 3  # 三级页表空间

# 空闲页管理
free_page_list: .dword 0  # 空闲链表头指针

.section .bss
.align 12
free_page_start:
  .skip 4096 * 128  # 128个空闲页 (512KB)
free_page_end:

PT_BASES

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
              