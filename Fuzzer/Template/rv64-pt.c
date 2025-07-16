// 外部符号声明（由链接脚本提供）
extern void* _stack_top;
extern void* _pt_base;
extern void* _page_pool_start;
extern void* _page_pool_end;


// 定义RISC-V CSR寄存器
#define mtvec 0x305
#define mepc 0x341
#define mcause 0x342
#define mtval 0x343
#define mstatus 0x300
#define satp 0x180
#define hgatp 0x680
#define PAGE_SIZE 4096

// 页表条目标志位
#define PTE_V (1 << 0)
#define PTE_R (1 << 1)
#define PTE_W (1 << 2)
#define PTE_X (1 << 3)
#define PTE_U (1 << 4)
#define PTE_G (1 << 5)
#define PTE_A (1 << 6)
#define PTE_D (1 << 7)

// 内存布局定义
#define MEM_BASE 0x80000000
#define STACK_TOP 0x81000000
#define PT_BASE 0x82000000
#define PAGE_POOL_START 0x83000000
#define PAGE_POOL_END 0x85000000

// 写入CSR寄存器
static inline void write_csr(unsigned long csr, unsigned long val) {
    asm volatile ("csrw %0, %1" :: "i"(csr), "r"(val));
}

// 读取CSR寄存器
static inline unsigned long read_csr(unsigned long csr) {
    unsigned long val;
    asm volatile ("csrr %0, %1" : "=r"(val) : "i"(csr));
    return val;
}

// 当前空闲页指针
static unsigned long free_page_ptr = PAGE_POOL_START;

// 分配一个物理页
void* alloc_page() {
    if (free_page_ptr >= PAGE_POOL_END) {
        asm volatile ("j _end_main");  // 内存耗尽，退出
    }
    
    void* page = (void*)free_page_ptr;
    free_page_ptr += PAGE_SIZE;
    
    // 清零新分配的页
    unsigned long* p = (unsigned long*)page;
    for (int i = 0; i < PAGE_SIZE / sizeof(unsigned long); i++) {
        p[i] = 0;
    }
    
    return page;
}

// 获取页表项
unsigned long* get_pte(unsigned long vaddr, int create) {
    unsigned long vpn[4];
    vpn[0] = (vaddr >> 39) & 0x1FF;
    vpn[1] = (vaddr >> 30) & 0x1FF;
    vpn[2] = (vaddr >> 21) & 0x1FF;
    vpn[3] = (vaddr >> 12) & 0x1FF;
    
    unsigned long* pte = (unsigned long*)PT_BASE;
    
    // 遍历四级页表
    for (int i = 0; i < 3; i++) {
        unsigned long idx = vpn[i];
        if (!(pte[idx] & PTE_V)) {
            if (!create) return 0;
            void* new_table = alloc_page();
            pte[idx] = ((unsigned long)new_table >> 2) | PTE_V;
        }
        pte = (unsigned long*)((pte[idx] & ~0x3FF) << 2);
    }
    
    return &pte[vpn[3]];
}

// 页表初始化
void init_page_table() {
    // 定义页表指针 (物理地址)
    unsigned long* l1 = (unsigned long*)PT_BASE;
    unsigned long* l2 = (unsigned long*)(PT_BASE + PAGE_SIZE);
    unsigned long* l3 = (unsigned long*)(PT_BASE + 2*PAGE_SIZE);
    unsigned long* l4 = (unsigned long*)(PT_BASE + 3*PAGE_SIZE);
    
    // 清除页表区域
    for (int i = 0; i < 512; i++) {
        l1[i] = 0; l2[i] = 0; l3[i] = 0; l4[i] = 0;
    }
    
    // 创建恒等映射 (1GB大页)
    l1[0] = ((unsigned long)l2 >> 2) | PTE_V;
    l2[0] = ((unsigned long)l3 >> 2) | PTE_V;
    l3[0] = ((unsigned long)l4 >> 2) | PTE_V;
    l4[0] = (0 >> 2) | PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D;
    
    // 映射页表区域自身
    unsigned long pt_base = PT_BASE;
    unsigned long* pte = get_pte(pt_base, 1);
    *pte = (pt_base >> 2) | PTE_V | PTE_R | PTE_W;
}

// 配置内存管理
void setup_mmu() {
    // 设置根页表物理地址 (SV48模式)
    unsigned long satp_val = (9 << 60) | ((PT_BASE >> 12) & 0xFFFFFFFFFFF);
    write_csr(satp, satp_val);
    write_csr(hgatp, satp_val);  // Hypervisor扩展使用相同页表
    
    // 使能分页 (设置mstatus的VM字段)
    unsigned long val = read_csr(mstatus);
    val |= (1 << 24);  // MSTATUS_MPP设置
    val |= (1 << 17);  // MSTATUS_MPV
    write_csr(mstatus, val);
}

// 处理缺页异常
void handle_page_fault(unsigned long cause, unsigned long vaddr) {
    // 对齐虚拟地址到页边界
    unsigned long aligned_vaddr = vaddr & ~(PAGE_SIZE - 1);
    
    // 获取页表项
    unsigned long* pte = get_pte(aligned_vaddr, 1);
    if (!pte) {
        asm volatile ("j _end_main");  // 无法获取页表项，退出
    }
    
    // 分配新物理页
    void* page = alloc_page();
    
    // 设置页表项权限
    unsigned long flags = PTE_V | PTE_A;
    if (cause == 15) {      // Store page fault
        flags |= PTE_R | PTE_W | PTE_D;
    } else if (cause == 13) { // Load page fault
        flags |= PTE_R;
    } else if (cause == 12) { // Instruction page fault
        flags |= PTE_X;
    }
    
    // 写入页表项
    *pte = ((unsigned long)page >> 2) | flags;
}

// 异常处理函数
void trap_handler() {
    unsigned long cause = read_csr(mcause);
    unsigned long vaddr = read_csr(mtval);
    unsigned long epc = read_csr(mepc);
    
    // 检查异常类型 (最高位为0表示同步异常)
    if (!(cause & 0x80000000)) {
        switch (cause) {
            case 1:   // Instruction access fault
            case 12:  // Instruction page fault
            case 13:  // Load page fault
            case 15:  // Store page fault
                handle_page_fault(cause, vaddr);
                break;
                
            default:  // 其他异常跳过指令
                write_csr(mepc, epc + 4);
        }
    }
}

// 主入口点
void _start() {
    // 使用链接脚本提供的栈顶地址
    asm volatile ("mv sp, %0" : : "r"(&_stack_top));
    
    // 使用链接脚本定义的页表和页池地址
    unsigned long* l1 = (unsigned long*)_pt_base;
    free_page_ptr = (unsigned long)_page_pool_start;
    
    // 初始化页表
    init_page_table();
    
    // 配置MMU
    setup_mmu();
    
    // 设置异常处理向量
    write_csr(mtvec, (unsigned long)&trap_handler);
    
    // 进入主函数
    _fuzz_main();
    
    // 程序退出
    asm volatile ("j _end_main");
}

// 主测试函数 (保留为空)
void _fuzz_main() {
    // 用户测试代码将放在这里
    // 示例: 访问未映射的内存触发缺页
    // volatile int* test = (int*)0x90000000;
    // *test = 0x1234;
}

// 程序退出处理
void _end_main() {
    asm volatile (
        "li a0, 0\n"            // 设置a0=0表示正常退出
        ".word 0x5006b\n"        // 香山trap指令
        "li t5, 1\n"
        "la t6, tohost\n"
        "sw t5, 0(t6)\n"
        "_test_end:\n"
        "j _test_end\n"
    );
}

// 符号定义
unsigned long tohost __attribute__((section(".tohost")));