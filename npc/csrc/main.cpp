#include "VNPC.h"
#include "verilated.h"

#include <cstdint>
#include <chrono>
#include <ctime>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

static constexpr uint32_t RESET_VECTOR = 0x80000000u;
static constexpr uint32_t PMEM_SIZE = 128u * 1024u * 1024u;
static constexpr uint32_t SERIAL_PORT = 0x10000000u;
static constexpr uint32_t RTC_ADDR = 0x10000048u;

static std::vector<uint8_t> pmem(PMEM_SIZE);
static std::chrono::steady_clock::time_point boot_time;
static bool running = true;
static int exit_code = 0;

static uint8_t *guest_to_host(uint32_t addr) {
  if (addr < RESET_VECTOR || addr >= RESET_VECTOR + PMEM_SIZE) {
    return nullptr;
  }
  return &pmem[addr - RESET_VECTOR];
}

static void load_image(const char *path) {
  FILE *fp = fopen(path, "rb");
  if (fp == nullptr) {
    perror(path);
    exit(1);
  }

  size_t nread = fread(pmem.data(), 1, pmem.size(), fp);
  if (ferror(fp)) {
    perror("fread");
    fclose(fp);
    exit(1);
  }
  fclose(fp);
  printf("Loaded %zu bytes from %s\n", nread, path);
}

static uint64_t get_uptime_us() {
  auto now = std::chrono::steady_clock::now();
  return std::chrono::duration_cast<std::chrono::microseconds>(now - boot_time).count();
}

extern "C" int pmem_read(int raddr) {
  uint32_t addr = static_cast<uint32_t>(raddr);

  if (addr == RTC_ADDR || addr == RTC_ADDR + 4) {
    uint64_t us = get_uptime_us();
    return static_cast<int>(addr == RTC_ADDR ? us : us >> 32);
  }

  uint8_t *host = guest_to_host(addr & ~0x3u);
  if (host == nullptr) {
    printf("Invalid read at 0x%08x\n", addr);
    running = false;
    exit_code = 1;
    return 0;
  }

  uint32_t data = 0;
  memcpy(&data, host, sizeof(data));
  return static_cast<int>(data);
}

extern "C" void pmem_write(int waddr, int wdata, unsigned char wmask) {
  uint32_t addr = static_cast<uint32_t>(waddr);
  uint32_t data = static_cast<uint32_t>(wdata);

  if (addr == SERIAL_PORT) {
    putchar(data & 0xff);
    fflush(stdout);
    return;
  }

  uint8_t *host = guest_to_host(addr & ~0x3u);
  if (host == nullptr) {
    printf("Invalid write at 0x%08x\n", addr);
    running = false;
    exit_code = 1;
    return;
  }

  for (int i = 0; i < 4; i++) {
    if ((wmask >> i) & 1) {
      host[i] = (data >> (i * 8)) & 0xff;
    }
  }
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
    printf("Usage: %s IMAGE [max-cycles]\n", argv[0]);
    return 1;
  }

  uint64_t max_cycles = argc >= 3 ? strtoull(argv[2], nullptr, 0) : 1000000000ull;
  load_image(argv[1]);
  boot_time = std::chrono::steady_clock::now();

  VerilatedContext context;
  VNPC top(&context);

  top.reset = 1;
  for (int i = 0; i < 10; i++) {
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
    cycles++;
  }

  top.final();
  if (running) {
    printf("NPC: timeout after %llu cycles\n", static_cast<unsigned long long>(cycles));
    return 1;
  }
  return exit_code == 0 ? 0 : 1;
}
