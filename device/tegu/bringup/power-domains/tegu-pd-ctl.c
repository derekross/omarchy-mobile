// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up only, not for merge: power one of the Pixel 9a's unused domains
 * off by hand, with the sequence Google's GPL flexpmu_cal_local_zuma.h gives
 * for each (all the same shape): the domain CMU's controller option bit 24
 * cleared, <NAME>_CONFIGURATION bit 0 cleared, <NAME>_STATUS bit 0 waited
 * for. Not ISPFE: the camera driver powers it (CSIS).
 *
 * It goes round the kernel's PMU regmap, whose tables don't have these
 * offsets: the write is the EL3 call the regmap itself uses for its writes
 * (0x82000504), made directly, and the reads are plain MMIO of the PMU.
 *
 * There is no way back on here, on purpose. A domain powered on again by
 * hand comes up with its DTZPC at the secure default, and the next
 * non-secure access to its CMU aborts (the palmtop reset that way on
 * 2026-11-18). Switch off from the boot state only; the undo is a reboot.
 *
 * One-shot: it does its job, logs, and refuses to stay loaded. It refuses to
 * load on anything but a Pixel 9a.
 *
 *   insmod tegu-pd-ctl.ko off=tpu
 *
 * Copyright (C) 2026 W4HO
 */
#include <linux/arm-smccc.h>
#include <linux/bits.h>
#include <linux/delay.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>

#define PMU_BASE		0x15460000
#define PMU_SIZE		0x10000
#define SMC_PMU_SEC_REG		0x82000504
#define PMUREG_WRITE		1

static char *off;
module_param(off, charp, 0444);
MODULE_PARM_DESC(off, "the domain to power off");

static const struct {
	const char *name;
	u32 conf, status;	/* PMU offsets */
	u32 cmu, opt;		/* the domain's CMU and its controller option */
} doms[] = {
	{ "tpu", 0x2500, 0x2504, 0x1a300000, 0x0800 },
	{ "aur", 0x2300, 0x2304, 0x20a00000, 0x0800 },
	{ "eh", 0x2400, 0x2404, 0x16c00000, 0x0800 },
	{ "bw", 0x2380, 0x2384, 0x1a600000, 0x0800 },
	{ "mfc", 0x2080, 0x2084, 0x1a400000, 0x0800 },
	{ "g2d", 0x1e80, 0x1e84, 0x1a800000, 0x0800 },
	{ "gdc", 0x1f00, 0x1f04, 0x1d400000, 0x0800 },
	{ "gse", 0x1f80, 0x1f84, 0x1d800000, 0x0800 },
	{ "mcsc", 0x2000, 0x2004, 0x1d000000, 0x0800 },
	{ "rgbp", 0x2100, 0x2104, 0x1c400000, 0x0800 },
	{ "tnr", 0x2180, 0x2184, 0x1cc00000, 0x0800 },
	{ "yuvp", 0x2200, 0x2204, 0x1c800000, 0x0800 },
	{ "dpuf1", 0x1e00, 0x1e04, 0x19c00000, 0x0800 },
};

static int pmu_write(u32 reg, u32 val)
{
	struct arm_smccc_res res;

	arm_smccc_smc(SMC_PMU_SEC_REG, PMU_BASE + reg, PMUREG_WRITE, val, 0, 0, 0, 0, &res);
	return (int)res.a0;
}

static int __init tegu_pd_ctl_init(void)
{
	void __iomem *pmu, *cmu;
	u32 st, conf, v;
	int i, n, ret;

	if (!of_machine_is_compatible("google,zumapro-tegu")) {
		pr_err("tegu-pd-ctl: not a Pixel 9a, nothing written\n");
		return -ENODEV;
	}
	if (!off)
		return -EINVAL;
	for (i = 0; i < ARRAY_SIZE(doms); i++)
		if (!strcmp(off, doms[i].name))
			break;
	if (i == ARRAY_SIZE(doms)) {
		pr_err("tegu-pd-ctl: %s is not a domain this module may switch\n", off);
		return -EINVAL;
	}
	pmu = ioremap(PMU_BASE, PMU_SIZE);
	if (!pmu)
		return -ENOMEM;
	st = readl(pmu + doms[i].status);
	conf = readl(pmu + doms[i].conf);
	pr_info("tegu-pd-ctl: %s before: configuration %#x status %#x\n", off, conf, st);
	if (!(st & 1)) {
		pr_info("tegu-pd-ctl: %s is already off\n", off);
		goto out;
	}
	cmu = ioremap(doms[i].cmu, 0x1000);
	if (!cmu)
		goto out;
	v = readl(cmu + doms[i].opt);
	writel(v & ~BIT(24), cmu + doms[i].opt);
	iounmap(cmu);
	ret = pmu_write(doms[i].conf, conf & ~1u);
	if (ret) {
		pr_err("tegu-pd-ctl: %s: the EL3 write was refused (%d)\n", off, ret);
		goto out;
	}
	for (n = 0; n < 1000; n++) {
		st = readl(pmu + doms[i].status);
		if (!(st & 1))
			break;
		udelay(10);
	}
	pr_info("tegu-pd-ctl: %s %s after %d polls: configuration %#x status %#x\n", off,
		(st & 1) ? "NOT SWITCHED" : "off", n, readl(pmu + doms[i].conf), st);
out:
	iounmap(pmu);
	return -EAGAIN;
}
module_init(tegu_pd_ctl_init);

MODULE_DESCRIPTION("Pixel 9a unused power domain switch-off (bring-up)");
MODULE_LICENSE("GPL");
