typedef unsigned long uintptr_t;

// 常量定义
#define PAGE_SHIFT 12
#define PAGE_SIZE (1 << PAGE_SHIFT)
#define PTE_V (1 << 0)
#define PTE_R (1 << 1)
#define PTE_W (1 << 2)
#define PTE_X (1 << 3)
#define PTE_U (1 << 4)
#define PTE_A (1 << 6)
#define PTE_D (1 << 7)

// 页表指针 - 在运行时初始化
static uintptr_t* l0_pgtable;
static uintptr_t* l1_pgtable;
static uintptr_t* l2_pgtable;
static uintptr_t* l3_pgtable;

// 栈空间
static char stack[4096] __attribute__((aligned(16)));


volatile unsigned long tohost __attribute__((section(".tohost"), aligned(64)));
volatile unsigned long fromhost __attribute__((section(".tohost"), aligned(64)));

static void inline exit_program();
// 主函数
void _fuzz_main();

static void inline __attribute__((always_inline)) do_tohost(int tohost_value)
{
  while (tohost)
    fromhost = 0;
  tohost = tohost_value;
}

// CSR 操作
static inline void csrw_mtvec(uintptr_t val) {
    asm volatile("csrw mtvec, %0" : : "r"(val));
}

static inline void csrw_satp(uintptr_t val) {
    asm volatile("csrw satp, %0" : : "r"(val));
}

static inline void sfence_vma() {
    asm volatile("sfence.vma zero, zero");
}

// 内存设置
static void* memset(void* dest, int c, unsigned long n) {
    char* p = dest;
    while (n--) *p++ = c;
    return dest;
}

// 页表初始化
static void init_pagetables(uintptr_t base_addr) {
    l0_pgtable = (uintptr_t*)base_addr;
    l1_pgtable = (uintptr_t*)(base_addr + PAGE_SIZE);
    l2_pgtable = (uintptr_t*)(base_addr + 2 * PAGE_SIZE);
    l3_pgtable = (uintptr_t*)(base_addr + 3 * PAGE_SIZE);
    
    memset(l0_pgtable, 0, PAGE_SIZE);
    memset(l1_pgtable, 0, PAGE_SIZE);
    memset(l2_pgtable, 0, PAGE_SIZE);
    memset(l3_pgtable, 0, PAGE_SIZE);
    
    // 映射 0x80000000-0x80200000 (2MB)
    uintptr_t mem_base = 0x80000000;
    for (int i = 0; i < 512; i++) {
        l3_pgtable[i] = ((mem_base + i * PAGE_SIZE) >> 2) | PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D;
    }
    
    // 设置 L2 页表项
    l2_pgtable[0] = ((uintptr_t)l3_pgtable >> 2) | PTE_V;
    
    // 设置 L1 页表项
    l1_pgtable[0] = ((uintptr_t)l2_pgtable >> 2) | PTE_V;
    
    // 设置 L0 页表项
    l0_pgtable[0] = ((uintptr_t)l1_pgtable >> 2) | PTE_V;
}

// 启用分页
static void enable_paging(uintptr_t pt_base) {
    uintptr_t satp_value = (pt_base >> PAGE_SHIFT) | (8ULL << 60); // Sv48
    csrw_satp(satp_value);
    sfence_vma();
}

// 异常处理
__attribute__((naked, aligned(4))) void trap_handler() {
    asm volatile(
        "csrr t0, mcause\n"
        "csrr t1, mepc\n"
        
        // 检查是否为缺页异常
        "li t2, 0xc\n"  // 指令缺页
        "beq t0, t2, page_fault\n"
        "li t2, 0xd\n"  // 加载缺页
        "beq t0, t2, page_fault\n"
        "li t2, 0xf\n"  // 存储缺页
        "beq t0, t2, page_fault\n"
        
        // 检查是否为指令异常
        "li t2, 0x80000000\n"
        "and t3, t0, t2\n"
        "bnez t3, skip_instruction\n" // 中断
        
        "li t2, 1\n"
        "blt t0, t2, instruction_fault\n"
        
        "skip_instruction:\n"
        "addi t1, t1, 4\n"  // 跳过当前指令
        "csrw mepc, t1\n"
        "mret\n"
        
        "instruction_fault:\n"
        "j exit_program\n"
        
        "page_fault:\n"
        "csrr a0, mtval\n"  // 获取出错地址
        "li a1, 0\n"        // 错误类型
        "j handle_page_fault\n"
    );
}

// 缺页处理
void handle_page_fault(uintptr_t addr, int type) {
    uintptr_t paddr = 0x90000000; // 映射到固定物理地址
    uintptr_t vpn = addr >> PAGE_SHIFT;
    
    // 计算页表索引 (Sv48)
    int idx0 = (vpn >> 27) & 0x1FF;
    int idx1 = (vpn >> 18) & 0x1FF;
    int idx2 = (vpn >> 9) & 0x1FF;
    int idx3 = vpn & 0x1FF;
    
    // 创建中间页表
    if (!(l0_pgtable[idx0] & PTE_V)) {
        l0_pgtable[idx0] = ((uintptr_t)l1_pgtable >> 2) | PTE_V;
    }
    if (!(l1_pgtable[idx1] & PTE_V)) {
        l1_pgtable[idx1] = ((uintptr_t)l2_pgtable >> 2) | PTE_V;
    }
    if (!(l2_pgtable[idx2] & PTE_V)) {
        l2_pgtable[idx2] = ((uintptr_t)l3_pgtable >> 2) | PTE_V;
    }
    
    // 设置页表项
    l3_pgtable[idx3] = (paddr >> 2) | PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D;
    sfence_vma();
}

// 程序入口
__attribute__((naked, section(".text.init"))) void _start() {
    asm volatile(
        "la sp, %0\n"       // 设置栈指针
        "j main_c_entry\n"  // 跳转到 C 入口
        : : "i" (stack + sizeof(stack))
    );
}

void main_c_entry() {
    // 在链接脚本中定义的页表基地址
    extern char _pt_base[];
    uintptr_t pt_base = (uintptr_t)_pt_base;
    
    init_pagetables(pt_base);
    enable_paging(pt_base);
    csrw_mtvec((uintptr_t)trap_handler);
    _fuzz_main();
}
// 用户主函数
void _fuzz_main() {
    // 用户代码将在此执行
    // 示例: *(int*)0x80000000 = 0x1234;
    exit_program();
}


// 退出程序
static void inline exit_program() {
    asm volatile(
        "li a0, 0\n"
        ".word 0x5006b\n"   // 香山 trap 指令
    );
    do_tohost(1);
    while (1);
}


// 创建自定义RWX段
asm(".section .data,\"aw\"\n"
    ".align 3");  // 8字节对齐

// 宏定义单个数据标签
#define DEFINE_DATA(s, o) asm("d_" #s "_" #o ": .dword 0")

// 完全展开所有数据定义
#define SECTION0 \
    DEFINE_DATA(0, 0); DEFINE_DATA(0, 1); DEFINE_DATA(0, 2); DEFINE_DATA(0, 3); \
    DEFINE_DATA(0, 4); DEFINE_DATA(0, 5); DEFINE_DATA(0, 6); DEFINE_DATA(0, 7); \
    DEFINE_DATA(0, 8); DEFINE_DATA(0, 9); DEFINE_DATA(0,10); DEFINE_DATA(0,11); \
    DEFINE_DATA(0,12); DEFINE_DATA(0,13); DEFINE_DATA(0,14); DEFINE_DATA(0,15); \
    DEFINE_DATA(0,16); DEFINE_DATA(0,17); DEFINE_DATA(0,18); DEFINE_DATA(0,19); \
    DEFINE_DATA(0,20); DEFINE_DATA(0,21); DEFINE_DATA(0,22); DEFINE_DATA(0,23); \
    DEFINE_DATA(0,24); DEFINE_DATA(0,25); DEFINE_DATA(0,26); DEFINE_DATA(0,27);

#define SECTION1 \
    DEFINE_DATA(1, 0); DEFINE_DATA(1, 1); DEFINE_DATA(1, 2); DEFINE_DATA(1, 3); \
    DEFINE_DATA(1, 4); DEFINE_DATA(1, 5); DEFINE_DATA(1, 6); DEFINE_DATA(1, 7); \
    DEFINE_DATA(1, 8); DEFINE_DATA(1, 9); DEFINE_DATA(1,10); DEFINE_DATA(1,11); \
    DEFINE_DATA(1,12); DEFINE_DATA(1,13); DEFINE_DATA(1,14); DEFINE_DATA(1,15); \
    DEFINE_DATA(1,16); DEFINE_DATA(1,17); DEFINE_DATA(1,18); DEFINE_DATA(1,19); \
    DEFINE_DATA(1,20); DEFINE_DATA(1,21); DEFINE_DATA(1,22); DEFINE_DATA(1,23); \
    DEFINE_DATA(1,24); DEFINE_DATA(1,25); DEFINE_DATA(1,26); DEFINE_DATA(1,27);

#define SECTION2 \
    DEFINE_DATA(2, 0); DEFINE_DATA(2, 1); DEFINE_DATA(2, 2); DEFINE_DATA(2, 3); \
    DEFINE_DATA(2, 4); DEFINE_DATA(2, 5); DEFINE_DATA(2, 6); DEFINE_DATA(2, 7); \
    DEFINE_DATA(2, 8); DEFINE_DATA(2, 9); DEFINE_DATA(2,10); DEFINE_DATA(2,11); \
    DEFINE_DATA(2,12); DEFINE_DATA(2,13); DEFINE_DATA(2,14); DEFINE_DATA(2,15); \
    DEFINE_DATA(2,16); DEFINE_DATA(2,17); DEFINE_DATA(2,18); DEFINE_DATA(2,19); \
    DEFINE_DATA(2,20); DEFINE_DATA(2,21); DEFINE_DATA(2,22); DEFINE_DATA(2,23); \
    DEFINE_DATA(2,24); DEFINE_DATA(2,25); DEFINE_DATA(2,26); DEFINE_DATA(2,27);

#define SECTION3 \
    DEFINE_DATA(3, 0); DEFINE_DATA(3, 1); DEFINE_DATA(3, 2); DEFINE_DATA(3, 3); \
    DEFINE_DATA(3, 4); DEFINE_DATA(3, 5); DEFINE_DATA(3, 6); DEFINE_DATA(3, 7); \
    DEFINE_DATA(3, 8); DEFINE_DATA(3, 9); DEFINE_DATA(3,10); DEFINE_DATA(3,11); \
    DEFINE_DATA(3,12); DEFINE_DATA(3,13); DEFINE_DATA(3,14); DEFINE_DATA(3,15); \
    DEFINE_DATA(3,16); DEFINE_DATA(3,17); DEFINE_DATA(3,18); DEFINE_DATA(3,19); \
    DEFINE_DATA(3,20); DEFINE_DATA(3,21); DEFINE_DATA(3,22); DEFINE_DATA(3,23); \
    DEFINE_DATA(3,24); DEFINE_DATA(3,25); DEFINE_DATA(3,26); DEFINE_DATA(3,27);

#define SECTION4 \
    DEFINE_DATA(4, 0); DEFINE_DATA(4, 1); DEFINE_DATA(4, 2); DEFINE_DATA(4, 3); \
    DEFINE_DATA(4, 4); DEFINE_DATA(4, 5); DEFINE_DATA(4, 6); DEFINE_DATA(4, 7); \
    DEFINE_DATA(4, 8); DEFINE_DATA(4, 9); DEFINE_DATA(4,10); DEFINE_DATA(4,11); \
    DEFINE_DATA(4,12); DEFINE_DATA(4,13); DEFINE_DATA(4,14); DEFINE_DATA(4,15); \
    DEFINE_DATA(4,16); DEFINE_DATA(4,17); DEFINE_DATA(4,18); DEFINE_DATA(4,19); \
    DEFINE_DATA(4,20); DEFINE_DATA(4,21); DEFINE_DATA(4,22); DEFINE_DATA(4,23); \
    DEFINE_DATA(4,24); DEFINE_DATA(4,25); DEFINE_DATA(4,26); DEFINE_DATA(4,27);

#define SECTION5 \
    DEFINE_DATA(5, 0); DEFINE_DATA(5, 1); DEFINE_DATA(5, 2); DEFINE_DATA(5, 3); \
    DEFINE_DATA(5, 4); DEFINE_DATA(5, 5); DEFINE_DATA(5, 6); DEFINE_DATA(5, 7); \
    DEFINE_DATA(5, 8); DEFINE_DATA(5, 9); DEFINE_DATA(5,10); DEFINE_DATA(5,11); \
    DEFINE_DATA(5,12); DEFINE_DATA(5,13); DEFINE_DATA(5,14); DEFINE_DATA(5,15); \
    DEFINE_DATA(5,16); DEFINE_DATA(5,17); DEFINE_DATA(5,18); DEFINE_DATA(5,19); \
    DEFINE_DATA(5,20); DEFINE_DATA(5,21); DEFINE_DATA(5,22); DEFINE_DATA(5,23); \
    DEFINE_DATA(5,24); DEFINE_DATA(5,25); DEFINE_DATA(5,26); DEFINE_DATA(5,27);

// 定义所有数据段（静态展开）
SECTION0
SECTION1
SECTION2
SECTION3
SECTION4
SECTION5