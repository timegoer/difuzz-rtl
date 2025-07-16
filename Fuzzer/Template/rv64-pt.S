	.file	"rv64-pt.c"
	.option nopic
	.attribute arch, "rv64i2p1_m2p0_a2p1_f2p2_d2p2_c2p0_h1p0_zicbom1p0_zicbop1p0_zicboz1p0_zicsr2p0_zifencei2p0_zmmul1p0_zaamo1p0_zalrsc1p0_zca1p0_zcd1p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.local	l0_pgtable
	.comm	l0_pgtable,8,8
	.local	l1_pgtable
	.comm	l1_pgtable,8,8
	.local	l2_pgtable
	.comm	l2_pgtable,8,8
	.local	l3_pgtable
	.comm	l3_pgtable,8,8
	.local	stack
	.comm	stack,4096,16
	.hidden	tohost
	.globl	tohost
	.section	.tohost,"aw"
	.align	6
	.type	tohost, @object
	.size	tohost, 8
tohost:
	.zero	8
	.hidden	fromhost
	.globl	fromhost
	.align	6
	.type	fromhost, @object
	.size	fromhost, 8
fromhost:
	.zero	8
	.text
	.align	1
	.type	csrw_mtvec, @function
csrw_mtvec:
	addi	sp,sp,-32
	sd	ra,24(sp)
	sd	s0,16(sp)
	addi	s0,sp,32
	sd	a0,-24(s0)
	ld	a5,-24(s0)
#APP
# 40 "output/../rv64-pt/rv64-pt.c" 1
	csrw mtvec, a5
# 0 "" 2
#NO_APP
	nop
	ld	ra,24(sp)
	ld	s0,16(sp)
	addi	sp,sp,32
	jr	ra
	.size	csrw_mtvec, .-csrw_mtvec
	.align	1
	.type	csrw_satp, @function
csrw_satp:
	addi	sp,sp,-32
	sd	ra,24(sp)
	sd	s0,16(sp)
	addi	s0,sp,32
	sd	a0,-24(s0)
	ld	a5,-24(s0)
#APP
# 44 "output/../rv64-pt/rv64-pt.c" 1
	csrw satp, a5
# 0 "" 2
#NO_APP
	nop
	ld	ra,24(sp)
	ld	s0,16(sp)
	addi	sp,sp,32
	jr	ra
	.size	csrw_satp, .-csrw_satp
	.align	1
	.type	sfence_vma, @function
sfence_vma:
	addi	sp,sp,-16
	sd	ra,8(sp)
	sd	s0,0(sp)
	addi	s0,sp,16
#APP
# 48 "output/../rv64-pt/rv64-pt.c" 1
	sfence.vma zero, zero
# 0 "" 2
#NO_APP
	nop
	ld	ra,8(sp)
	ld	s0,0(sp)
	addi	sp,sp,16
	jr	ra
	.size	sfence_vma, .-sfence_vma
	.align	1
	.type	memset, @function
memset:
	addi	sp,sp,-64
	sd	ra,56(sp)
	sd	s0,48(sp)
	addi	s0,sp,64
	sd	a0,-40(s0)
	mv	a5,a1
	sd	a2,-56(s0)
	sw	a5,-44(s0)
	ld	a5,-40(s0)
	sd	a5,-24(s0)
	j	.L5
.L6:
	ld	a5,-24(s0)
	addi	a4,a5,1
	sd	a4,-24(s0)
	lw	a4,-44(s0)
	andi	a4,a4,0xff
	sb	a4,0(a5)
.L5:
	ld	a5,-56(s0)
	addi	a4,a5,-1
	sd	a4,-56(s0)
	bne	a5,zero,.L6
	ld	a5,-40(s0)
	mv	a0,a5
	ld	ra,56(sp)
	ld	s0,48(sp)
	addi	sp,sp,64
	jr	ra
	.size	memset, .-memset
	.align	1
	.type	init_pagetables, @function
init_pagetables:
	addi	sp,sp,-48
	sd	ra,40(sp)
	sd	s0,32(sp)
	addi	s0,sp,48
	sd	a0,-40(s0)
	ld	a4,-40(s0)
	lla	a5,l0_pgtable
	sd	a4,0(a5)
	ld	a4,-40(s0)
	li	a5,4096
	add	a5,a4,a5
	mv	a4,a5
	lla	a5,l1_pgtable
	sd	a4,0(a5)
	ld	a4,-40(s0)
	li	a5,8192
	add	a5,a4,a5
	mv	a4,a5
	lla	a5,l2_pgtable
	sd	a4,0(a5)
	ld	a4,-40(s0)
	li	a5,12288
	add	a5,a4,a5
	mv	a4,a5
	lla	a5,l3_pgtable
	sd	a4,0(a5)
	lla	a5,l0_pgtable
	ld	a5,0(a5)
	li	a2,4096
	li	a1,0
	mv	a0,a5
	call	memset
	lla	a5,l1_pgtable
	ld	a5,0(a5)
	li	a2,4096
	li	a1,0
	mv	a0,a5
	call	memset
	lla	a5,l2_pgtable
	ld	a5,0(a5)
	li	a2,4096
	li	a1,0
	mv	a0,a5
	call	memset
	lla	a5,l3_pgtable
	ld	a5,0(a5)
	li	a2,4096
	li	a1,0
	mv	a0,a5
	call	memset
	li	a5,1
	slli	a5,a5,31
	sd	a5,-32(s0)
	sw	zero,-20(s0)
	j	.L9
.L10:
	lw	a5,-20(s0)
	slliw	a5,a5,12
	sext.w	a5,a5
	mv	a4,a5
	ld	a5,-32(s0)
	add	a5,a4,a5
	srli	a4,a5,2
	lla	a5,l3_pgtable
	ld	a3,0(a5)
	lw	a5,-20(s0)
	slli	a5,a5,3
	add	a5,a3,a5
	ori	a4,a4,207
	sd	a4,0(a5)
	lw	a5,-20(s0)
	addiw	a5,a5,1
	sw	a5,-20(s0)
.L9:
	lw	a5,-20(s0)
	sext.w	a4,a5
	li	a5,511
	ble	a4,a5,.L10
	lla	a5,l3_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l2_pgtable
	ld	a5,0(a5)
	ori	a4,a4,1
	sd	a4,0(a5)
	lla	a5,l2_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l1_pgtable
	ld	a5,0(a5)
	ori	a4,a4,1
	sd	a4,0(a5)
	lla	a5,l1_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l0_pgtable
	ld	a5,0(a5)
	ori	a4,a4,1
	sd	a4,0(a5)
	nop
	ld	ra,40(sp)
	ld	s0,32(sp)
	addi	sp,sp,48
	jr	ra
	.size	init_pagetables, .-init_pagetables
	.align	1
	.type	enable_paging, @function
enable_paging:
	addi	sp,sp,-48
	sd	ra,40(sp)
	sd	s0,32(sp)
	addi	s0,sp,48
	sd	a0,-40(s0)
	ld	a5,-40(s0)
	srli	a4,a5,12
	li	a5,-1
	slli	a5,a5,63
	or	a5,a4,a5
	sd	a5,-24(s0)
	ld	a0,-24(s0)
	call	csrw_satp
	call	sfence_vma
	nop
	ld	ra,40(sp)
	ld	s0,32(sp)
	addi	sp,sp,48
	jr	ra
	.size	enable_paging, .-enable_paging
	.align	2
	.globl	trap_handler
	.hidden	trap_handler
	.type	trap_handler, @function
trap_handler:
#APP
# 95 "output/../rv64-pt/rv64-pt.c" 1
	csrr t0, mcause
csrr t1, mepc
li t2, 0xc
beq t0, t2, page_fault
li t2, 0xd
beq t0, t2, page_fault
li t2, 0xf
beq t0, t2, page_fault
li t2, 0x80000000
and t3, t0, t2
bnez t3, skip_instruction
li t2, 1
blt t0, t2, instruction_fault
skip_instruction:
addi t1, t1, 4
csrw mepc, t1
mret
instruction_fault:
j exit_program
page_fault:
csrr a0, mtval
li a1, 0
j handle_page_fault

# 0 "" 2
#NO_APP
	nop
	.size	trap_handler, .-trap_handler
	.align	1
	.globl	handle_page_fault
	.hidden	handle_page_fault
	.type	handle_page_fault, @function
handle_page_fault:
	addi	sp,sp,-64
	sd	ra,56(sp)
	sd	s0,48(sp)
	addi	s0,sp,64
	sd	a0,-56(s0)
	mv	a5,a1
	sw	a5,-60(s0)
	li	a5,9
	slli	a5,a5,28
	sd	a5,-24(s0)
	ld	a5,-56(s0)
	srli	a5,a5,12
	sd	a5,-32(s0)
	ld	a5,-32(s0)
	srli	a5,a5,27
	sext.w	a5,a5
	andi	a5,a5,511
	sw	a5,-36(s0)
	ld	a5,-32(s0)
	srli	a5,a5,18
	sext.w	a5,a5
	andi	a5,a5,511
	sw	a5,-40(s0)
	ld	a5,-32(s0)
	srli	a5,a5,9
	sext.w	a5,a5
	andi	a5,a5,511
	sw	a5,-44(s0)
	ld	a5,-32(s0)
	sext.w	a5,a5
	andi	a5,a5,511
	sw	a5,-48(s0)
	lla	a5,l0_pgtable
	ld	a4,0(a5)
	lw	a5,-36(s0)
	slli	a5,a5,3
	add	a5,a4,a5
	ld	a5,0(a5)
	andi	a5,a5,1
	bne	a5,zero,.L14
	lla	a5,l1_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l0_pgtable
	ld	a3,0(a5)
	lw	a5,-36(s0)
	slli	a5,a5,3
	add	a5,a3,a5
	ori	a4,a4,1
	sd	a4,0(a5)
.L14:
	lla	a5,l1_pgtable
	ld	a4,0(a5)
	lw	a5,-40(s0)
	slli	a5,a5,3
	add	a5,a4,a5
	ld	a5,0(a5)
	andi	a5,a5,1
	bne	a5,zero,.L15
	lla	a5,l2_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l1_pgtable
	ld	a3,0(a5)
	lw	a5,-40(s0)
	slli	a5,a5,3
	add	a5,a3,a5
	ori	a4,a4,1
	sd	a4,0(a5)
.L15:
	lla	a5,l2_pgtable
	ld	a4,0(a5)
	lw	a5,-44(s0)
	slli	a5,a5,3
	add	a5,a4,a5
	ld	a5,0(a5)
	andi	a5,a5,1
	bne	a5,zero,.L16
	lla	a5,l3_pgtable
	ld	a5,0(a5)
	srli	a4,a5,2
	lla	a5,l2_pgtable
	ld	a3,0(a5)
	lw	a5,-44(s0)
	slli	a5,a5,3
	add	a5,a3,a5
	ori	a4,a4,1
	sd	a4,0(a5)
.L16:
	ld	a5,-24(s0)
	srli	a4,a5,2
	lla	a5,l3_pgtable
	ld	a3,0(a5)
	lw	a5,-48(s0)
	slli	a5,a5,3
	add	a5,a3,a5
	ori	a4,a4,207
	sd	a4,0(a5)
	call	sfence_vma
	nop
	ld	ra,56(sp)
	ld	s0,48(sp)
	addi	sp,sp,64
	jr	ra
	.size	handle_page_fault, .-handle_page_fault
	.section	.text.init,"ax",@progbits
	.align	1
	.globl	_start
	.hidden	_start
	.type	_start, @function
_start:
#APP
# 159 "output/../rv64-pt/rv64-pt.c" 1
	la sp, stack+4096
j main_c_entry

# 0 "" 2
#NO_APP
	nop
	.size	_start, .-_start
	.text
	.align	1
	.globl	main_c_entry
	.hidden	main_c_entry
	.type	main_c_entry, @function
main_c_entry:
	addi	sp,sp,-32
	sd	ra,24(sp)
	sd	s0,16(sp)
	addi	s0,sp,32
	lla	a5,_pt_base
	sd	a5,-24(s0)
	ld	a0,-24(s0)
	call	init_pagetables
	ld	a0,-24(s0)
	call	enable_paging
	lla	a5,trap_handler
	mv	a0,a5
	call	csrw_mtvec
	call	_fuzz_main
	nop
	ld	ra,24(sp)
	ld	s0,16(sp)
	addi	sp,sp,32
	jr	ra
	.size	main_c_entry, .-main_c_entry
	.align	1
	.globl	_fuzz_main
	.hidden	_fuzz_main
	.type	_fuzz_main, @function
_fuzz_main:
	addi	sp,sp,-16
	sd	ra,8(sp)
	sd	s0,0(sp)
	addi	s0,sp,16
	call	exit_program
	nop
	ld	ra,8(sp)
	ld	s0,0(sp)
	addi	sp,sp,16
	jr	ra
	.size	_fuzz_main, .-_fuzz_main
	.align	1
	.type	exit_program, @function
exit_program:
	addi	sp,sp,-32
	sd	ra,24(sp)
	sd	s0,16(sp)
	addi	s0,sp,32
#APP
# 186 "output/../rv64-pt/rv64-pt.c" 1
	li a0, 0
.word 0x5006b

# 0 "" 2
#NO_APP
	li	a5,1
	sw	a5,-20(s0)
	j	.L21
.L22:
	lla	a5,fromhost
	sd	zero,0(a5)
.L21:
	lla	a5,tohost
	ld	a5,0(a5)
	bne	a5,zero,.L22
	lw	a4,-20(s0)
	lla	a5,tohost
	sd	a4,0(a5)
	nop
.L23:
	j	.L23
	.size	exit_program, .-exit_program
#APP
	.section .data,"aw"
.align 3
	d_0_0: .dword 0
	d_0_1: .dword 0
	d_0_2: .dword 0
	d_0_3: .dword 0
	d_0_4: .dword 0
	d_0_5: .dword 0
	d_0_6: .dword 0
	d_0_7: .dword 0
	d_0_8: .dword 0
	d_0_9: .dword 0
	d_0_10: .dword 0
	d_0_11: .dword 0
	d_0_12: .dword 0
	d_0_13: .dword 0
	d_0_14: .dword 0
	d_0_15: .dword 0
	d_0_16: .dword 0
	d_0_17: .dword 0
	d_0_18: .dword 0
	d_0_19: .dword 0
	d_0_20: .dword 0
	d_0_21: .dword 0
	d_0_22: .dword 0
	d_0_23: .dword 0
	d_0_24: .dword 0
	d_0_25: .dword 0
	d_0_26: .dword 0
	d_0_27: .dword 0
	d_1_0: .dword 0
	d_1_1: .dword 0
	d_1_2: .dword 0
	d_1_3: .dword 0
	d_1_4: .dword 0
	d_1_5: .dword 0
	d_1_6: .dword 0
	d_1_7: .dword 0
	d_1_8: .dword 0
	d_1_9: .dword 0
	d_1_10: .dword 0
	d_1_11: .dword 0
	d_1_12: .dword 0
	d_1_13: .dword 0
	d_1_14: .dword 0
	d_1_15: .dword 0
	d_1_16: .dword 0
	d_1_17: .dword 0
	d_1_18: .dword 0
	d_1_19: .dword 0
	d_1_20: .dword 0
	d_1_21: .dword 0
	d_1_22: .dword 0
	d_1_23: .dword 0
	d_1_24: .dword 0
	d_1_25: .dword 0
	d_1_26: .dword 0
	d_1_27: .dword 0
	d_2_0: .dword 0
	d_2_1: .dword 0
	d_2_2: .dword 0
	d_2_3: .dword 0
	d_2_4: .dword 0
	d_2_5: .dword 0
	d_2_6: .dword 0
	d_2_7: .dword 0
	d_2_8: .dword 0
	d_2_9: .dword 0
	d_2_10: .dword 0
	d_2_11: .dword 0
	d_2_12: .dword 0
	d_2_13: .dword 0
	d_2_14: .dword 0
	d_2_15: .dword 0
	d_2_16: .dword 0
	d_2_17: .dword 0
	d_2_18: .dword 0
	d_2_19: .dword 0
	d_2_20: .dword 0
	d_2_21: .dword 0
	d_2_22: .dword 0
	d_2_23: .dword 0
	d_2_24: .dword 0
	d_2_25: .dword 0
	d_2_26: .dword 0
	d_2_27: .dword 0
	d_3_0: .dword 0
	d_3_1: .dword 0
	d_3_2: .dword 0
	d_3_3: .dword 0
	d_3_4: .dword 0
	d_3_5: .dword 0
	d_3_6: .dword 0
	d_3_7: .dword 0
	d_3_8: .dword 0
	d_3_9: .dword 0
	d_3_10: .dword 0
	d_3_11: .dword 0
	d_3_12: .dword 0
	d_3_13: .dword 0
	d_3_14: .dword 0
	d_3_15: .dword 0
	d_3_16: .dword 0
	d_3_17: .dword 0
	d_3_18: .dword 0
	d_3_19: .dword 0
	d_3_20: .dword 0
	d_3_21: .dword 0
	d_3_22: .dword 0
	d_3_23: .dword 0
	d_3_24: .dword 0
	d_3_25: .dword 0
	d_3_26: .dword 0
	d_3_27: .dword 0
	d_4_0: .dword 0
	d_4_1: .dword 0
	d_4_2: .dword 0
	d_4_3: .dword 0
	d_4_4: .dword 0
	d_4_5: .dword 0
	d_4_6: .dword 0
	d_4_7: .dword 0
	d_4_8: .dword 0
	d_4_9: .dword 0
	d_4_10: .dword 0
	d_4_11: .dword 0
	d_4_12: .dword 0
	d_4_13: .dword 0
	d_4_14: .dword 0
	d_4_15: .dword 0
	d_4_16: .dword 0
	d_4_17: .dword 0
	d_4_18: .dword 0
	d_4_19: .dword 0
	d_4_20: .dword 0
	d_4_21: .dword 0
	d_4_22: .dword 0
	d_4_23: .dword 0
	d_4_24: .dword 0
	d_4_25: .dword 0
	d_4_26: .dword 0
	d_4_27: .dword 0
	d_5_0: .dword 0
	d_5_1: .dword 0
	d_5_2: .dword 0
	d_5_3: .dword 0
	d_5_4: .dword 0
	d_5_5: .dword 0
	d_5_6: .dword 0
	d_5_7: .dword 0
	d_5_8: .dword 0
	d_5_9: .dword 0
	d_5_10: .dword 0
	d_5_11: .dword 0
	d_5_12: .dword 0
	d_5_13: .dword 0
	d_5_14: .dword 0
	d_5_15: .dword 0
	d_5_16: .dword 0
	d_5_17: .dword 0
	d_5_18: .dword 0
	d_5_19: .dword 0
	d_5_20: .dword 0
	d_5_21: .dword 0
	d_5_22: .dword 0
	d_5_23: .dword 0
	d_5_24: .dword 0
	d_5_25: .dword 0
	d_5_26: .dword 0
	d_5_27: .dword 0
	.ident	"GCC: (g1b306039a) 15.1.0"
	.section	.note.GNU-stack,"",@progbits
