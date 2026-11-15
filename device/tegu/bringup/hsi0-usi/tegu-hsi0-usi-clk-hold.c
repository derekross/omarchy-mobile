// SPDX-License-Identifier: GPL-2.0-only
/*
 * Bring-up only (SLEEP-PLAN item 1): hold the bus and function clocks of
 * the HSI0 block's USI2 and USI3 on while loaded, so that neither the USI
 * driver's resume nor the SPI controllers' runtime PM gates them. They
 * are manual-mode gates, as the PERIC0 GPIO bus clock was.
 * ip=0 holds the bus clocks (pclk) alone.
 */
#include <linux/clk.h>
#include <linux/clk-provider.h>
#include <linux/module.h>
#include <linux/of.h>

static bool ip = true;
module_param(ip, bool, 0444);
MODULE_PARM_DESC(ip, "Also hold the function clocks (ipclk), default on");

static const char * const nodes[] = { "/soc/usi@111d00c0", "/soc/usi@111e00c0" };
static const char * const names[] = { "pclk", "ipclk" };
static struct clk *held[4];
static int nheld;

static void hold_release(void)
{
	while (nheld) {
		nheld--;
		clk_disable_unprepare(held[nheld]);
		clk_put(held[nheld]);
	}
}

static int __init hold_init(void)
{
	int i, j, ret;

	for (i = 0; i < ARRAY_SIZE(nodes); i++) {
		struct device_node *np = of_find_node_by_path(nodes[i]);

		if (!np) {
			hold_release();
			return -ENODEV;
		}
		for (j = 0; j < (ip ? 2 : 1); j++) {
			struct clk *c = of_clk_get_by_name(np, names[j]);

			if (IS_ERR(c)) {
				of_node_put(np);
				hold_release();
				return PTR_ERR(c);
			}
			ret = clk_prepare_enable(c);
			if (ret) {
				clk_put(c);
				of_node_put(np);
				hold_release();
				return ret;
			}
			held[nheld++] = c;
			pr_info("tegu-hsi0-usi-clk-hold: %s held on\n", __clk_get_name(c));
		}
		of_node_put(np);
	}
	return 0;
}

static void __exit hold_exit(void)
{
	hold_release();
}

module_init(hold_init);
module_exit(hold_exit);
MODULE_DESCRIPTION("Bring-up: hold the HSI0 USI2 and USI3 clocks on");
MODULE_LICENSE("GPL");
