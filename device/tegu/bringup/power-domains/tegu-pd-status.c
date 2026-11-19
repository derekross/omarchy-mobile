// SPDX-License-Identifier: GPL-2.0-only
/*
 * Read-only, bring-up only: which of the Pixel 9a's power domains are on.
 *
 * Reads each domain's <NAME>_STATUS word in the PMU (0x15460000), the word
 * Google's GPL flexpmu_cal_local_zuma.h reads for a domain's state (bit 0
 * set: on, what its "on" sequence waits for). The PMU is always powered, and
 * the kernel reads it with plain MMIO (tensor_sec_reg_read() does), but the
 * zumapro PMU regmap only lets a few offsets through, so this maps the PMU
 * itself and reads only the offsets below, past the regmap's tables. ISPFE
 * and HSI0, the two STATUS words the regmap does let through, are also read
 * through it, as a check of the mapping. Writes nothing; refuses to stay
 * loaded, and to load on anything but a Pixel 9a. only=NAME reads a single
 * domain (a first probe).
 *
 * Copyright (C) 2026 W4HO
 */
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/regmap.h>
#include <linux/soc/samsung/exynos-pmu.h>

#define PMU_BASE	0x15460000
#define PMU_SIZE	0x10000

static char *only;
module_param(only, charp, 0444);
MODULE_PARM_DESC(only, "read this one domain only");

static const struct {
	const char *name;
	u32 off;
} doms[] = {
	{ "g3d", 0x1a84 },     { "embedded_g3d", 0x1c84 }, { "dpub", 0x1d04 },
	{ "dpuf0", 0x1d84 },   { "dpuf1", 0x1e04 },        { "g2d", 0x1e84 },
	{ "gdc", 0x1f04 },     { "gse", 0x1f84 },          { "mcsc", 0x2004 },
	{ "mfc", 0x2084 },     { "rgbp", 0x2104 },         { "tnr", 0x2184 },
	{ "yuvp", 0x2204 },    { "aoc", 0x2284 },          { "aur", 0x2304 },
	{ "bw", 0x2384 },      { "eh", 0x2404 },           { "ispfe", 0x2484 },
	{ "tpu", 0x2504 },     { "nocl0", 0x2804 },        { "nocl1a", 0x2884 },
	{ "nocl1b", 0x2904 },  { "nocl2aa", 0x2984 },      { "nocl2ab", 0x2a04 },
	{ "hsi0", 0x2a84 },    { "hsi1", 0x2b04 },
};

static int __init tegu_pd_status_init(void)
{
	struct regmap *map = exynos_get_pmu_regmap();
	void __iomem *pmu;
	int i, n = 0;
	u32 v, r;

	if (!of_machine_is_compatible("google,zumapro-tegu")) {
		pr_err("tegu-pd-status: not a Pixel 9a, nothing read\n");
		return -ENODEV;
	}
	pmu = ioremap(PMU_BASE, PMU_SIZE);
	if (!pmu)
		return -ENOMEM;
	for (i = 0; i < ARRAY_SIZE(doms); i++) {
		if (only && strcmp(only, doms[i].name))
			continue;
		v = readl(pmu + doms[i].off);
		n++;
		if (!IS_ERR_OR_NULL(map) && (doms[i].off == 0x2484 || doms[i].off == 0x2a84) &&
		    !regmap_read(map, doms[i].off, &r))
			pr_info("tegu-pd-status: %-13s %#06x %#010x %s (regmap %#010x)\n",
				doms[i].name, doms[i].off, v, (v & 1) ? "on" : "off", r);
		else
			pr_info("tegu-pd-status: %-13s %#06x %#010x %s\n", doms[i].name,
				doms[i].off, v, (v & 1) ? "on" : "off");
	}
	iounmap(pmu);
	pr_info("tegu-pd-status: %d read, nothing written\n", n);
	/* Nothing to keep loaded: the reads are the whole job. */
	return -EAGAIN;
}
module_init(tegu_pd_status_init);

MODULE_DESCRIPTION("Pixel 9a power domain status, read-only (bring-up)");
MODULE_LICENSE("GPL");
