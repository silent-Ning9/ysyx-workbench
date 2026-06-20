#ifdef SOC_TOP
#include "VysyxSoCFull.h"
using Top = VysyxSoCFull;
#else
#include "VNPC.h"
using Top = VNPC;
#endif

#include "verilated.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static constexpr uint32_t RESET_VECTOR = 0x80000000u;
static constexpr uint32_t PMEM_SIZE = 128u * 1024u * 1024u;
static constexpr uint32_t FLASH_BASE = 0x30000000u;
static constexpr uint32_t FLASH_SIZE = 16u * 1024u * 1024u;
static constexpr uint32_t UART_BASE = 0x10000000u;
static constexpr uint32_t UART_END = 0x10000fffu;
static constexpr uint32_t UART_REG_DLL = 0x0;
static constexpr uint32_t UART_REG_DLM = 0x1;
static constexpr uint32_t UART_REG_IER = 0x1;
static constexpr uint32_t UART_REG_LCR = 0x3;
static constexpr uint32_t UART_REG_LSR = 0x5;
static constexpr uint8_t UART_LCR_DLAB = 0x80;
static constexpr uint8_t UART_LSR_THRE = 0x20;
static constexpr uint8_t UART_LSR_TEMT = 0x40;

static std::vector<uint8_t> pmem(PMEM_SIZE);
static std::vector<uint8_t> flash(FLASH_SIZE);
static bool running = true;
static int exit_code = 0;

struct Uart16550 {
  uint8_t dll = 0;
  uint8_t dlm = 0;
  uint8_t ier = 0;
  uint8_t lcr = 0;
} uart;

static uint8_t *guest_to_host(uint32_t addr) {
  if (addr < RESET_VECTOR || addr >= RESET_VECTOR + PMEM_SIZE) {
    return nullptr;
  }
  return &pmem[addr - RESET_VECTOR];
}

static void load_binary(const char *path, std::vector<uint8_t> &target) {
  FILE *fp = fopen(path, "rb");
  if (fp == nullptr) {
    perror(path);
    exit(1);
  }

  size_t nread = fread(target.data(), 1, target.size(), fp);
  if (ferror(fp)) {
    perror("fread");
    fclose(fp);
    exit(1);
  }
  fclose(fp);
  printf("Loaded %zu bytes from %s\n", nread, path);
}

static uint32_t load_u32(const uint8_t *base) {
  uint32_t data = 0;
  memcpy(&data, base, sizeof(data));
  return data;
}

static uint8_t uart_read8(uint32_t addr) {
  uint32_t off = addr - UART_BASE;
  switch (off) {
    case UART_REG_DLL:
      return (uart.lcr & UART_LCR_DLAB) ? uart.dll : 0;
    case UART_REG_DLM:
      return (uart.lcr & UART_LCR_DLAB) ? uart.dlm : uart.ier;
    case UART_REG_LCR:
      return uart.lcr;
    case UART_REG_LSR:
      return UART_LSR_THRE | UART_LSR_TEMT;
    default:
      return 0;
  }
}

static void uart_write8(uint32_t addr, uint8_t data) {
  uint32_t off = addr - UART_BASE;
  switch (off) {
    case UART_REG_DLL:
      if (uart.lcr & UART_LCR_DLAB) {
        uart.dll = data;
      } else {
        putchar(data);
        fflush(stdout);
      }
      break;
    case UART_REG_DLM:
      if (uart.lcr & UART_LCR_DLAB) {
        uart.dlm = data;
      } else {
        uart.ier = data & 0x0f;
      }
      break;
    case UART_REG_LCR:
      uart.lcr = data;
      break;
    default:
      break;
  }
}

extern "C" int pmem_read(int raddr) {
  uint32_t addr = static_cast<uint32_t>(raddr);

  if (addr >= UART_BASE && addr <= UART_END) {
    uint32_t data = 0;
    for (int i = 0; i < 4; ++i) {
      data |= static_cast<uint32_t>(uart_read8((addr & ~0x3u) + i)) << (i * 8);
    }
    return static_cast<int>(data);
  }

  uint8_t *host = guest_to_host(addr & ~0x3u);
  if (host == nullptr) {
    printf("Invalid read at 0x%08x\n", addr);
    running = false;
    exit_code = 1;
    return 0;
  }

  return static_cast<int>(load_u32(host));
}

extern "C" void pmem_write(int waddr, int wdata, unsigned char wmask) {
  uint32_t addr = static_cast<uint32_t>(waddr);
  uint32_t data = static_cast<uint32_t>(wdata);

  if (addr >= UART_BASE && addr <= UART_END) {
    for (int i = 0; i < 4; ++i) {
      if ((wmask >> i) & 1) {
        uart_write8((addr & ~0x3u) + i, (data >> (i * 8)) & 0xff);
      }
    }
    return;
  }

  uint8_t *host = guest_to_host(addr & ~0x3u);
  if (host == nullptr) {
    printf("Invalid write at 0x%08x\n", addr);
    running = false;
    exit_code = 1;
    return;
  }

  for (int i = 0; i < 4; ++i) {
    if ((wmask >> i) & 1) {
      host[i] = (data >> (i * 8)) & 0xff;
    }
  }
}

extern "C" void flash_read(int32_t addr, int32_t *data) {
  uint32_t off = static_cast<uint32_t>(addr);
  if (off + 4 > FLASH_SIZE) {
    printf("Invalid flash read at 0x%08x\n", off);
    running = false;
    exit_code = 1;
    *data = 0;
    return;
  }

  *data = static_cast<int32_t>(load_u32(&flash[off]));
}

extern "C" void npc_trap(int code, int pc) {
  uint32_t trap_pc = static_cast<uint32_t>(pc);
  exit_code = code;
  if (code == 0) {
    printf("\nNPC: HIT GOOD TRAP at pc = 0x%08x\n", trap_pc);
  } else {
    printf("\nNPC: HIT BAD TRAP code = %d at pc = 0x%08x\n", code, trap_pc);
  }
  running = false;
}

int main(int argc, char **argv) {
  if (argc < 2) {
#ifdef SOC_TOP
    printf("Usage: %s FLASH_IMAGE [max-cycles]\n", argv[0]);
#else
    printf("Usage: %s IMAGE [max-cycles]\n", argv[0]);
#endif
    return 1;
  }

  uint64_t max_cycles = argc >= 3 ? strtoull(argv[2], nullptr, 0) : 1000000000ull;
#ifdef SOC_TOP
  load_binary(argv[1], flash);
#else
  load_binary(argv[1], pmem);
#endif

  VerilatedContext context;
  Top top{&context};

  top.reset = 1;
  for (int i = 0; i < 10; ++i) {
    top.clock = 0;
    top.eval();
    top.clock = 1;
    top.eval();
    context.timeInc(1);
  }
  top.reset = 0;

  uint64_t cycles = 0;
  while (running && cycles < max_cycles) {
    top.clock = 0;
    top.eval();
    top.clock = 1;
    top.eval();
    context.timeInc(1);
    ++cycles;
  }

  top.final();
  if (running) {
    printf("NPC: timeout after %llu cycles\n", static_cast<unsigned long long>(cycles));
    return 1;
  }
  return exit_code == 0 ? 0 : 1;
}
