// SPDX-License-Identifier: MIT
// reboot-to: reboot with a reason ABL reads from the PMIC SDAM.
// "reboot-to bootloader" is LINUX_REBOOT_CMD_RESTART2. Busybox reboot
// cannot pass a reason. Same call as
// packages/omamobile-device-cheetah/src/reboot-to.c, built without a
// libc so the ramdisk pack needs no aarch64 sysroot.
//
// aarch64 Linux entry: sp points at argc, then the argv pointers.

#define __NR_sync 81
#define __NR_reboot 142
#define __NR_exit_group 94

#define LINUX_REBOOT_MAGIC1 0xfee1dead
#define LINUX_REBOOT_MAGIC2 672274793
#define LINUX_REBOOT_CMD_RESTART2 0xA1B2C3D4

static long scall(long n, long a, long b, long c, long d)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;

	__asm__ volatile("svc #0"
			 : "+r"(x0)
			 : "r"(x1), "r"(x2), "r"(x3), "r"(x8)
			 : "memory");
	return x0;
}

/* A C _start has a prologue, so sp there is no longer the entry stack.
   Linux put argc at [sp] and argv just after it. */
__attribute__((naked)) void _start(void)
{
	__asm__ volatile(
		"ldr x0, [sp]\n"
		"add x1, sp, #8\n"
		"b go\n");
}

void go(long argc, char **argv)
{
	const char *reason = "bootloader";

	if (argc > 1 && argv[1] && argv[1][0])
		reason = argv[1];

	scall(__NR_sync, 0, 0, 0, 0);
	scall(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
	      LINUX_REBOOT_CMD_RESTART2, (long)reason);
	scall(__NR_exit_group, 1, 0, 0, 0);
	for (;;)
		;
}
