// SPDX-License-Identifier: GPL-2.0-only
/*
 * THIS MODULE HANGS THE SOC BY DESIGN on a kernel whose HSI0 USI clock
 * gates are switched (without linux-omarchy-mobile#247): that is what it is
 * for. Run it only as README describes, attended, with the modem off.
 *
 * Bring-up only (SLEEP-PLAN item 1): do what exynos_usi_enable() does in the
 * noirq resume, over and over, awake: turn pclk and ipclk of one HSI0 USI
 * on, read USI_CON, write it back with the reset bit clear (as the driver
 * does at every resume), wait 1 us and turn the clocks off. To see whether
 * the switch of a manual-mode gate followed at once by a register access
 * hangs the SoC outside the wake path too. A hang ends in a reset by the
 * cluster watchdog while systemd feeds it, and otherwise needs the buttons.
 *   insmod tegu-hsi0-usi-stress.ko loops=200000 usi=3 cpu=7
 * It refuses anything but a Pixel 9a (google,zumapro-tegu), and usi= (2 or
 * 3) has no default: USI2 is the touchscreen's, so the choice is explicit.
 * access=0 switches the clocks and touches no register; delay_us=N waits
 * N us between turning the clocks on and the first access.
 */
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/kthread.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/of_address.h>

#define USI_CON		0x04
#define USI_CON_RESET	BIT(0)

static unsigned long loops = 200000;
module_param(loops, ulong, 0444);
static unsigned long report = 10000;
module_param(report, ulong, 0444);
static int usi;
module_param(usi, int, 0444);
MODULE_PARM_DESC(usi, "the HSI0 USI to switch: 2 (the touchscreen's) or 3; required");
static int cpu = 7;
module_param(cpu, int, 0444);
static bool access = true;
module_param(access, bool, 0444);
static unsigned int delay_us;
module_param(delay_us, uint, 0444);

static struct clk *pclk, *ipclk;
static void __iomem *regs;
static struct task_struct *task;

static int stress_fn(void *unused)
{
	unsigned long i, off = 0;
	u32 val = 0;

	pr_info("tegu-hsi0-usi-stress: usi%d, %lu loops on cpu %d, access %d, delay %u us, ipclk %s, pclk %s\n",
		usi, loops, raw_smp_processor_id(), access, delay_us,
		__clk_is_enabled(ipclk) ? "on" : "off",
		__clk_is_enabled(pclk) ? "on" : "off");
	for (i = 1; i <= loops && !kthread_should_stop(); i++) {
		if (clk_prepare_enable(pclk))
			break;
		if (clk_prepare_enable(ipclk)) {
			clk_disable_unprepare(pclk);
			break;
		}
		if (delay_us)
			udelay(delay_us);
		if (access) {
			val = readl(regs + USI_CON);
			val &= ~USI_CON_RESET;
			writel(val, regs + USI_CON);
		}
		udelay(1);
		clk_disable_unprepare(ipclk);
		clk_disable_unprepare(pclk);
		if (!__clk_is_enabled(ipclk))
			off++;
		if (!(i % report)) {
			pr_info("tegu-hsi0-usi-stress: %lu loops, ipclk gate off after %lu of them, USI_CON 0x%x\n",
				i, off, val);
			cond_resched();
		}
	}
	pr_info("tegu-hsi0-usi-stress: done after %lu loops, ipclk gate off after %lu of them\n",
		i - 1, off);
	while (!kthread_should_stop())
		schedule_timeout_interruptible(HZ);
	return 0;
}

static int __init stress_init(void)
{
	static const char * const nodes[] = { "/soc/usi@111d00c0", "/soc/usi@111e00c0" };
	struct device_node *np;
	int ret = -ENODEV;

	if (!of_machine_is_compatible("google,zumapro-tegu")) {
		pr_err("tegu-hsi0-usi-stress: not a Pixel 9a (google,zumapro-tegu): refusing\n");
		return -ENODEV;
	}
	if (usi != 2 && usi != 3) {
		pr_err("tegu-hsi0-usi-stress: usi=2 or usi=3 is required\n");
		return -EINVAL;
	}
	np = of_find_node_by_path(nodes[usi - 2]);
	if (!np)
		return -ENODEV;
	pclk = of_clk_get_by_name(np, "pclk");
	ipclk = of_clk_get_by_name(np, "ipclk");
	regs = of_iomap(np, 0);
	of_node_put(np);
	if (IS_ERR(pclk) || IS_ERR(ipclk) || !regs)
		goto err;
	task = kthread_create(stress_fn, NULL, "usi-stress");
	if (IS_ERR(task)) {
		ret = PTR_ERR(task);
		goto err;
	}
	if (cpu >= 0)
		kthread_bind(task, cpu);
	wake_up_process(task);
	return 0;
err:
	if (regs)
		iounmap(regs);
	if (!IS_ERR_OR_NULL(ipclk))
		clk_put(ipclk);
	if (!IS_ERR_OR_NULL(pclk))
		clk_put(pclk);
	return ret;
}

static void __exit stress_exit(void)
{
	kthread_stop(task);
	iounmap(regs);
	clk_put(ipclk);
	clk_put(pclk);
}

module_init(stress_init);
module_exit(stress_exit);
MODULE_DESCRIPTION("Bring-up: switch an HSI0 USI's clocks around a register access, awake");
MODULE_LICENSE("GPL");
