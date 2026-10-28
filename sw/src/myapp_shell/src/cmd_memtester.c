/*
 * Zephyr shell command: destructive RAM tester
 *
 * Target: MicroBlaze V (RV32) and other Zephyr targets
 * Zephyr: 4.3.0 (Xilinx/zephyr-amd), Zephyr SDK 0.17.4
 *
 * Required Kconfig:
 *   CONFIG_SHELL=y
 * Optional (recommended if the data cache is enabled in the design):
 *   CONFIG_CACHE_MANAGEMENT=y
 *
 * IMPORTANT: This test is DESTRUCTIVE.
 * Only test RAM that is NOT used by the Zephyr kernel, the application,
 * stacks, heap, device buffers or DMA buffers. The memory must be
 * CPU-accessible. Ranges overlapping the Zephyr image are rejected.
 */

#include <zephyr/kernel.h>
#include <zephyr/shell/shell.h>
#include <zephyr/cache.h>
#include <zephyr/linker/linker-defs.h>
#include <zephyr/sys/util.h>
#include <stdint.h>
#include <stdlib.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>

#define MEMTEST_WORD_SIZE  sizeof(uint32_t)
#define MEMTEST_YIELD_MASK 0xfffffU

/* --------------------------------------------------------------------------
 * Helpers
 * ------------------------------------------------------------------------ */

static int parse_u64(const char *str, uint64_t *value)
{
	char *endptr;
	unsigned long long val;

	errno = 0;
	val = strtoull(str, &endptr, 0);

	if ((errno != 0) || (endptr == str) || (*endptr != '\0')) {
		return -EINVAL;
	}

	*value = (uint64_t)val;
	return 0;
}

/*
 * Write back dirty lines and invalidate the range so that the following
 * read-back really comes from RAM and not from the data cache.
 * Without this, a defective RAM may pass the test on cached systems.
 */
static void mem_sync(volatile uint32_t *mem, size_t size)
{
#if defined(CONFIG_CACHE_MANAGEMENT) && defined(CONFIG_DCACHE)
	(void)sys_cache_data_flush_and_invd_range((void *)mem, size);
#else
	ARG_UNUSED(mem);
	ARG_UNUSED(size);
#endif
	/*
	 * Full memory barrier. GCC builtin, no Zephyr header needed.
	 * Emits "fence rw,rw" on RISC-V (MicroBlaze V).
	 */
	__atomic_thread_fence(__ATOMIC_SEQ_CST);
}

/*
 * Address-derived pattern.
 * Avoids shifting a 32-bit uintptr_t by 32 (undefined behaviour on RV32).
 */
static inline uint32_t addr_pattern(uintptr_t address)
{
	uint32_t pattern = (uint32_t)address;

#if UINTPTR_MAX > 0xffffffffU
	pattern ^= (uint32_t)((uint64_t)address >> 32);
#endif
	return pattern ^ 0xa5a5a5a5U;
}

static void report_fail(const struct shell *sh, volatile uint32_t *addr,
			uint32_t expected, uint32_t actual)
{
	shell_error(sh,
		    "FAIL\n"
		    "    Address : %p\n"
		    "    Expected: 0x%08" PRIx32 "\n"
		    "    Actual  : 0x%08" PRIx32 "\n"
		    "    XOR     : 0x%08" PRIx32,
		    (void *)addr, expected, actual, expected ^ actual);
}

/* Reject ranges overlapping the running Zephyr image (code/data/bss/stacks) */
static bool overlaps_zephyr_image(uintptr_t start, size_t size)
{
	uintptr_t img_start = (uintptr_t)_image_ram_start;
	uintptr_t img_end = (uintptr_t)_image_ram_end;
	uintptr_t end = start + size; /* exclusive */

	return (start < img_end) && (end > img_start);
}

/* --------------------------------------------------------------------------
 * Tests
 * ------------------------------------------------------------------------ */

static int test_pattern(const struct shell *sh, volatile uint32_t *mem,
			size_t words, uint32_t pattern)
{
	size_t i;

	shell_fprintf(sh, SHELL_NORMAL, "  Pattern 0x%08" PRIx32 " ... ", pattern);

	for (i = 0; i < words; i++) {
		mem[i] = pattern;
		if ((i & MEMTEST_YIELD_MASK) == 0) {
			k_yield();
		}
	}

	mem_sync(mem, words * MEMTEST_WORD_SIZE);

	for (i = 0; i < words; i++) {
		uint32_t value = mem[i];

		if (value != pattern) {
			report_fail(sh, &mem[i], pattern, value);
			return -EIO;
		}
		if ((i & MEMTEST_YIELD_MASK) == 0) {
			k_yield();
		}
	}

	shell_print(sh, "PASS");
	return 0;
}

static int test_address_pattern(const struct shell *sh, volatile uint32_t *mem,
				size_t words)
{
	size_t i;

	shell_fprintf(sh, SHELL_NORMAL, "  Address pattern     ... ");

	for (i = 0; i < words; i++) {
		mem[i] = addr_pattern((uintptr_t)&mem[i]);
		if ((i & MEMTEST_YIELD_MASK) == 0) {
			k_yield();
		}
	}

	mem_sync(mem, words * MEMTEST_WORD_SIZE);

	for (i = 0; i < words; i++) {
		uint32_t expected = addr_pattern((uintptr_t)&mem[i]);
		uint32_t actual = mem[i];

		if (actual != expected) {
			report_fail(sh, &mem[i], expected, actual);
			return -EIO;
		}
		if ((i & MEMTEST_YIELD_MASK) == 0) {
			k_yield();
		}
	}

	shell_print(sh, "PASS");
	return 0;
}

/* invert == false: walking ones, invert == true: walking zeros */
static int test_walking(const struct shell *sh, volatile uint32_t *mem,
			size_t words, bool invert)
{
	unsigned int bit;
	size_t i;

	shell_fprintf(sh, SHELL_NORMAL, "  Walking %s       ... ",
		      invert ? "zeros" : "ones ");

	for (bit = 0; bit < 32; bit++) {
		uint32_t pattern = invert ? ~BIT(bit) : BIT(bit);

		for (i = 0; i < words; i++) {
			mem[i] = pattern;
			if ((i & MEMTEST_YIELD_MASK) == 0) {
				k_yield();
			}
		}

		mem_sync(mem, words * MEMTEST_WORD_SIZE);

		for (i = 0; i < words; i++) {
			uint32_t actual = mem[i];

			if (actual != pattern) {
				shell_error(sh, "Bit %u", bit);
				report_fail(sh, &mem[i], pattern, actual);
				return -EIO;
			}
			if ((i & MEMTEST_YIELD_MASK) == 0) {
				k_yield();
			}
		}
	}

	shell_print(sh, "PASS");
	return 0;
}

static int run_memtest(const struct shell *sh, uintptr_t address, size_t size)
{
	static const uint32_t patterns[] = {
		0x00000000U, 0xffffffffU, 0xaaaaaaaaU,
		0x55555555U, 0xccccccccU, 0x33333333U,
	};
	volatile uint32_t *mem = (volatile uint32_t *)address;
	size_t words = size / MEMTEST_WORD_SIZE;
	int ret;

	for (size_t p = 0; p < ARRAY_SIZE(patterns); p++) {
		ret = test_pattern(sh, mem, words, patterns[p]);
		if (ret != 0) {
			return ret;
		}
	}

	ret = test_address_pattern(sh, mem, words);
	if (ret != 0) {
		return ret;
	}

	ret = test_walking(sh, mem, words, false);
	if (ret != 0) {
		return ret;
	}

	return test_walking(sh, mem, words, true);
}

/* --------------------------------------------------------------------------
 * Shell command
 * ------------------------------------------------------------------------ */

static int cmd_memtest(const struct shell *sh, size_t argc, char **argv)
{
	uint64_t address64;
	uint64_t size64;
	uint64_t loops64 = 1;
	uintptr_t address;
	size_t size;
	unsigned int loops;
	int64_t t_start;
	int ret;

	if (parse_u64(argv[1], &address64) != 0) {
		shell_error(sh, "Invalid address: %s", argv[1]);
		return -EINVAL;
	}

	if (parse_u64(argv[2], &size64) != 0) {
		shell_error(sh, "Invalid size: %s", argv[2]);
		return -EINVAL;
	}

	if (argc >= 4) {
		ret = parse_u64(argv[3], &loops64);
		if ((ret != 0) || (loops64 == 0) || (loops64 > UINT_MAX)) {
			shell_error(sh, "Invalid loop count: %s", argv[3]);
			return -EINVAL;
		}
	}

	if (address64 > UINTPTR_MAX) {
		shell_error(sh, "Address exceeds CPU address range");
		return -EINVAL;
	}

	if (size64 > SIZE_MAX) {
		shell_error(sh, "Size exceeds CPU address range");
		return -EINVAL;
	}

	address = (uintptr_t)address64;
	size = (size_t)size64;
	loops = (unsigned int)loops64;

	if ((address & (MEMTEST_WORD_SIZE - 1)) != 0) {
		shell_error(sh, "Address must be %u-byte aligned",
			    (unsigned int)MEMTEST_WORD_SIZE);
		return -EINVAL;
	}

	if ((size == 0) || ((size & (MEMTEST_WORD_SIZE - 1)) != 0)) {
		shell_error(sh, "Size must be a non-zero multiple of %u bytes",
			    (unsigned int)MEMTEST_WORD_SIZE);
		return -EINVAL;
	}

	/* Last byte must not wrap (allows ranges ending at the top of memory) */
	if ((address + (size - 1)) < address) {
		shell_error(sh, "Address range overflow");
		return -EINVAL;
	}

	if (overlaps_zephyr_image(address, size)) {
		shell_error(sh,
			    "Range overlaps Zephyr image RAM [0x%" PRIxPTR
			    " - 0x%" PRIxPTR "] - refusing",
			    (uintptr_t)_image_ram_start,
			    (uintptr_t)_image_ram_end - 1);
		return -EPERM;
	}

	shell_print(sh, "");
	shell_print(sh, "Zephyr Memory Tester");
	shell_print(sh, "--------------------");
	shell_print(sh, "Start : 0x%" PRIxPTR, address);
	shell_print(sh, "End   : 0x%" PRIxPTR, address + size - 1);
	shell_print(sh, "Size  : %zu bytes (%zu KiB)", size, size / 1024U);
	shell_print(sh, "Loops : %u", loops);
#if defined(CONFIG_CACHE_MANAGEMENT) && defined(CONFIG_DCACHE)
	shell_print(sh, "Cache : flush/invalidate before read-back");
#else
	shell_warn(sh, "Cache : no cache management (enable "
		       "CONFIG_CACHE_MANAGEMENT if D-cache is present)");
#endif
	shell_print(sh, "");
	shell_warn(sh, "WARNING: This test DESTROYS the memory contents!");
	shell_print(sh, "");

	t_start = k_uptime_get();

	for (unsigned int loop = 0; loop < loops; loop++) {
		shell_print(sh, "=== Loop %u/%u ===", loop + 1, loops);

		ret = run_memtest(sh, address, size);
		if (ret != 0) {
			shell_error(sh, "");
			shell_error(sh, "MEMORY TEST FAILED (loop %u)", loop + 1);
			return ret;
		}
		shell_print(sh, "");
	}

	shell_print(sh, "=============================");
	shell_print(sh, " MEMORY TEST PASSED");
	shell_print(sh, " Duration: %" PRId64 " ms", k_uptime_get() - t_start);
	shell_print(sh, "=============================");

	return 0;
}

SHELL_CMD_ARG_REGISTER(memtest, NULL,
	"Destructive memory test.\n"
	"Usage: memtest <address> <size> [loops]\n"
	"\n"
	"Examples:\n"
	"  memtest 0x90000000 0x100000\n"
	"  memtest 0x90000000 0x1000000 10",
	cmd_memtest, 3, 1);