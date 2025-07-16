ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1024K
}

SECTIONS {
    . = 0x80000000;
    
    .text : {
        *(.text.init)
        *(.text .text.*)
    } > RAM
    
    .rodata : {
        *(.rodata .rodata.*)
    } > RAM
    
    .data : {
        *(.data .data.*)
    } > RAM
    
    .bss : {
        . = ALIGN(16);
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM
    
    /* 页表区域 - 放在代码段后 */
    .pagetables 0x80030000 : {
        . = ALIGN(4096);
        _pt_base = .;
        l0_pgtable = .;
        . += 4096;  /* L0 */
        l1_pgtable = .;
        . += 4096;  /* L1 */
        l2_pgtable = .;
        . += 4096;  /* L2 */
        l3_pgtable = .;
        . += 4096;  /* L3 */
    } > RAM
    
    /* 栈区域 */
    .stack : {
        . = ALIGN(16);
        stack = .;
        . += 4096;
    } > RAM
    
    .tohost : { *(.tohost) }
    
    /DISCARD/ : {
        *(.eh_frame)
        *(.eh_frame_hdr)
        *(.eh_frame_entry)
        *(.comment)
        *(.riscv.attributes)
        *(.debug_*)
    }
    
    . = ALIGN(8);
    _end = .;
}