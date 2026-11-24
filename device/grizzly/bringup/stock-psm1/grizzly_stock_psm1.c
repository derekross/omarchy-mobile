// SPDX-License-Identifier: GPL-2.0-only
#include <linux/atomic.h>
#include <linux/err.h>
#include <linux/io.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/notifier.h>
#include <linux/of.h>
#include <linux/string.h>
#include <linux/timekeeping.h>
#include <linux/uaccess.h>
#include <linux/utsname.h>

#define D1_RELEASE "6.12.81-android16-6-gf5369e7496cb-ab16467452-4k"
#define HSIOS_PSM_ADDR 0x3c00b108
#define HSIOS_PSM_MASK 0x1f
#define HSIOS_PSM_ON 0x10

struct psm_sample {
	struct kprobe probe;
	int registration;
	atomic_t hit;
	int result;
	u32 opcode;
	int hc_offset;
	bool prep;
	u32 raw;
	u64 mono_ns;
};

static bool prep_trace;
module_param(prep_trace, bool, 0400);
static void __iomem *hsios_psm;

static int sample_show(char *buffer, const struct kernel_param *parameter)
{
	struct psm_sample *sample = parameter->arg;
	int status = smp_load_acquire(&sample->result);

	if (status)
		return scnprintf(buffer, PAGE_SIZE, "registration=%d sample=%d\n",
				 READ_ONCE(sample->registration), status);

	return scnprintf(buffer, PAGE_SIZE, "registration=0 raw=%#x psm1=%#x mono_ns=%llu\n",
			 sample->raw, sample->raw & 0xf, sample->mono_ns);
}

static const struct kernel_param_ops sample_ops = {
	.get = sample_show,
};
static int capture_psm1(struct kprobe *probe, struct pt_regs *regs)
{
	struct psm_sample *sample = container_of(probe, struct psm_sample, probe);
	void __iomem *hc;
	const void *field;

	if (atomic_xchg(&sample->hit, 1))
		return 0;

	if (probe->opcode != sample->opcode || !regs->regs[19] ||
	    (!sample->prep && regs->regs[0])) {
		smp_store_release(&sample->result, -ESTALE);
		return 0;
	}

	/* The core hook follows a successful PHY wait. Prep has no such wait. */
	if (sample->prep && (readl(hsios_psm) & HSIOS_PSM_MASK) != HSIOS_PSM_ON) {
		smp_store_release(&sample->result, -EHOSTDOWN);
		return 0;
	}

	/* This field is normal kernel memory. Use an MMIO accessor for HC. */
	field = (const char *)regs->regs[19] + sample->hc_offset;
	if (copy_from_kernel_nofault(&hc, field, sizeof(hc)) ||
	    IS_ERR_OR_NULL(hc) || !IS_ALIGNED((unsigned long)hc, sizeof(sample->raw))) {
		smp_store_release(&sample->result, -EFAULT);
		return 0;
	}

	sample->raw = readl_relaxed(hc);
	sample->mono_ns = ktime_get_mono_fast_ns();
	smp_store_release(&sample->result, 0);
	return 0;
}
NOKPROBE_SYMBOL(capture_psm1);

static struct psm_sample samples[] = {
	{
		.probe = { .symbol_name = "ufs:ufs_google_pd_notifier",
			   .offset = 0x68, .pre_handler = capture_psm1 },
		.registration = -EAGAIN, .result = -EAGAIN,
		.opcode = 0xf8508268, .hc_offset = -0xd8,
	},
	{
		.probe = { .symbol_name = "ufs:ufs_google_pd_get_sync",
			   .offset = 0x24, .pre_handler = capture_psm1 },
		.registration = -EAGAIN, .result = -EAGAIN,
		.opcode = 0xaa0803e0, .hc_offset = 0x478, .prep = true,
	},
	{
		.probe = { .symbol_name = "ufs:ufs_google_pd_get_sync",
			   .offset = 0x2c, .pre_handler = capture_psm1 },
		.registration = -EAGAIN, .result = -EAGAIN,
		.opcode = 0xf942c660, .hc_offset = 0x478, .prep = true,
	},
};
module_param_cb(sample, &sample_ops, &samples[0], 0444);
module_param_cb(prep_before, &sample_ops, &samples[1], 0444);
module_param_cb(prep_after, &sample_ops, &samples[2], 0444);

static int ufs_coming(struct notifier_block *block, unsigned long action, void *data)
{
	struct module *module = data;
	unsigned int i, count = prep_trace ? ARRAY_SIZE(samples) : 1;

	if (action != MODULE_STATE_COMING || strcmp(module->name, "ufs"))
		return NOTIFY_DONE;

	for (i = 0; i < count; i++)
		if (READ_ONCE(samples[i].registration) == -EAGAIN)
			WRITE_ONCE(samples[i].registration, register_kprobe(&samples[i].probe));
	return NOTIFY_DONE;
}

static struct notifier_block ufs_notifier = {
	.notifier_call = ufs_coming,
	/* Match the stock trace-kprobe module notifier's ordering. */
	.priority = 2,
};

static int __init sampler_init(void)
{
	int ret;

	if (strcmp(init_utsname()->release, D1_RELEASE) ||
	    !of_machine_is_compatible("google,malibu-grizzly")) {
		pr_info("grizzly_stock_psm1: requires stock D1 on Grizzly\n");
		return -ENODEV;
	}

	if (prep_trace) {
		hsios_psm = ioremap(HSIOS_PSM_ADDR, sizeof(u32));
		if (!hsios_psm)
			return -ENOMEM;
	}
	ret = register_module_notifier(&ufs_notifier);
	if (ret && hsios_psm)
		iounmap(hsios_psm);
	return ret;
}

static void __exit sampler_exit(void)
{
	unsigned int i;

	unregister_module_notifier(&ufs_notifier);
	for (i = 0; i < ARRAY_SIZE(samples); i++)
		if (!READ_ONCE(samples[i].registration))
			unregister_kprobe(&samples[i].probe);
	if (hsios_psm)
		iounmap(hsios_psm);
}

module_init(sampler_init);
module_exit(sampler_exit);
MODULE_DESCRIPTION("Grizzly stock D1 UFS PRE_ON PSM1 diagnostic");
MODULE_LICENSE("GPL");
