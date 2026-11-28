// SPDX-License-Identifier: GPL-2.0-only
/*
 * The sensor hardware table the OnePlus 8T's sensor DSP (SLPI) reads from
 * SMEM item 130: for each sensor type, which chip is fitted, on which bus,
 * its IRQ, orientation and a few chip-specific values. The phone's own
 * kernel fills it from an "oplus,sensor-devinfo" device tree node; the
 * bootloader allocates the item and leaves it zeroed, and with it zeroed
 * the DSP's drivers register no physical sensor (no accelerometer, light,
 * proximity or magnetometer through SSC).
 *
 * The parsing below is the OnePlus kernel's drivers/soc/oplus/sensor/
 * oplus_sensor_devinfo.c (Copyright (C) 2018-2020 Oplus, GPL-2.0-only),
 * kept as it is so that the board's node can be copied unchanged. Its
 * procfs files, ALS and pressure calibration and the sensor LDO GPIO are
 * left out: nothing on the 8T needs them (its node has no ldo_enable).
 */
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/soc/qcom/smem.h>
#include <linux/string.h>

#define SMEM_SENSOR 130

#define REG_NUM 10
#define PARAMETER_NUM 25
#define FEATURE_NUM 10
#define SOURCE_NUM 3
#define ALGO_PARAMETER_NUM 15
#define ALGO_FEATURE_NUM 5
#define DEFAULT_CONFIG 0xff
#define SAR_MAX_CH_NUM 5
#define CLOSE_PD 1
#define CLOSE_PD_CONDITION 2

enum sensor_id {
	OPLUS_ACCEL,
	OPLUS_GYRO,
	OPLUS_MAG,
	OPLUS_LIGHT,
	OPLUS_PROXIMITY,
	OPLUS_SAR,
	OPLUS_CCT,
	OPLUS_CCT_REAR,
	OPLUS_BAROMETER,
	OPLUS_SARS,
	OPLUS_LIGHT_REAR,
	SENSORS_NUM
};

enum sensor_algo_id {
	OPLUS_PICKUP_DETECT,
	OPLUS_LUX_AOD,
	OPLUS_TP_GESTURE,
	OPLUS_FP_DISPLAY,
	OPLUS_FREE_FALL,
	OPLUS_CAMERA_PROTECT,
	OPLUS_MAG_FUSION,
	OPLUS_MEASUREMENT,
	SENSOR_ALGO_NUM
};

struct sensor_feature {
	int reg[REG_NUM];
	int parameter[PARAMETER_NUM];
	int feature[FEATURE_NUM];
};

struct sensor_hw {
	uint8_t sensor_name;
	uint8_t bus_number;
	uint8_t direction;
	uint8_t irq_number;
	struct sensor_feature feature;
};

struct sensor_vector {
	int sensor_id;
	struct sensor_hw hw[SOURCE_NUM];
};

struct sensor_vector_old {
	int sensor_id;
	struct sensor_hw hw[SOURCE_NUM - 1];
};

struct sensor_algorithm {
	int sensor_id;
	int parameter[ALGO_PARAMETER_NUM];
	int feature[ALGO_FEATURE_NUM];
};

/* The layout depends on the DSP firmware: the 8T's SMEM item is the old one */
struct sensor_info {
	int magic_num;
	struct sensor_vector s_vector[SENSORS_NUM];
	struct sensor_algorithm a_vector[SENSOR_ALGO_NUM];
};

struct sensor_info_old {
	int magic_num;
	struct sensor_vector_old s_vector[SENSORS_NUM];
	struct sensor_algorithm a_vector[SENSOR_ALGO_NUM];
};

static void is_need_close_pd(struct sensor_hw *hw, struct device_node *ch_node)
{
	int value = 0;

	hw->feature.feature[2] = 0;
	/* CLOSE_PD_CONDITION matches the phone's serial number, which we never set */
	if (!of_property_read_u32(ch_node, "is_need_close_pd", &value) && value == CLOSE_PD)
		hw->feature.feature[2] = CLOSE_PD;
}

static void parse_physical_sensor_common_dts(struct sensor_hw *hw,
					     struct device_node *ch_node)
{
	uint32_t chip_value = 0;

	hw->sensor_name = of_property_read_u32(ch_node, "sensor-name", &chip_value) ? 0 : chip_value;
	/* DEFAULT_CONFIG: the DSP takes the value from its registry */
	hw->bus_number = of_property_read_u32(ch_node, "bus-number", &chip_value) ?
			 DEFAULT_CONFIG : chip_value;
	hw->direction = of_property_read_u32(ch_node, "sensor-direction", &chip_value) ?
			DEFAULT_CONFIG : chip_value;
	hw->irq_number = of_property_read_u32(ch_node, "irq-number", &chip_value) ?
			 DEFAULT_CONFIG : chip_value;
}

static void parse_magnetic_sensor_dts(struct sensor_hw *hw,
				      struct device_node *ch_node)
{
	int value = 0;
	int soft_default_para[18] = { 10000, 0, 0, 0, 0, 0, 0, 0, 10000,
				      0, 0, 0, 0, 0, 0, 0, 10000, 0 };

	memcpy(&hw->feature.parameter[0], soft_default_para, sizeof(soft_default_para));
	/* the per-project parameter tables need the OnePlus project ID: not used on the 8T */
	if (!of_property_read_u32(ch_node, "parameter-number", &value) &&
	    value > 0 && value < PARAMETER_NUM)
		of_property_read_u32_array(ch_node, "soft-mag-parameter",
					   (u32 *)&hw->feature.parameter[0], value);
}

static void parse_proximity_sensor_dts(struct sensor_hw *hw,
				       struct device_node *ch_node)
{
	int value = 0;
	int di;
	static const char * const param[] = {
		"low_step",	     "high_step",	  "low_limit",
		"high_limit",	     "dirty_low_step",	  "dirty_high_step",
		"ps_dirty_limit",    "ps_ir_limit",	  "ps_adjust_min",
		"ps_adjust_max",     "sampling_count",	  "step_max",
		"step_min",	     "step_div",	  "anti_shake_delta",
		"dynamic_cali_max",  "raw2offset_radio",  "offset_max",
		"offset_range_min",  "offset_range_max",  "force_cali_limit",
		"cali_jitter_limit", "cal_offset_margin", "esd_gpio_use"
	};

	if (!of_property_read_u32(ch_node, "ps-type", &value))
		hw->feature.feature[0] = value;
	if (!of_property_read_u32(ch_node, "ps_saturation", &value))
		hw->feature.feature[1] = value;
	is_need_close_pd(hw, ch_node);
	if (!of_property_read_u32(ch_node, "ps_factory_cali_max", &value))
		hw->feature.feature[3] = value;

	for (di = 0; di < ARRAY_SIZE(param); di++)
		if (!of_property_read_u32(ch_node, param[di], &value))
			hw->feature.parameter[di] = value;

	if (!of_property_read_u32(ch_node, "parameter-number", &value) &&
	    value > 0 && value < REG_NUM - 1) {
		hw->feature.reg[0] = value;
		of_property_read_u32_array(ch_node, "sensor-reg",
					   (u32 *)&hw->feature.reg[1], value);
	}
}

static void parse_light_sensor_dts(struct sensor_hw *hw,
				   struct device_node *ch_node)
{
	int value = 0;
	int di;
	static const char * const als_feature[] = {
		"als-type", "is-unit-device", "is-als-dri", "als-factor",
		"is_als_initialed", "als_buffer_length", "normalization_value",
		"use_lb_algo", "para-matrix", "als_ratio_type"
	};
	static const char * const light_para[] = {
		"coef_a", "coef_b", "coef_c", "coef_d", "coef_e", "coef_ratio",
		"gold-reset-scale", /* gold scale value after sale */
		/* lb para begin */
		"lcd_type", "linear_comp_scope", "linear_comp_intercept",
		"temp_lux", "coef", "bal_coef", "ir_coef_stage_0",
		"ir_coef_stage_1", "ir_coef_stage_2", "ir_coef_stage_3",
		"ir_coef_val_0", "ir_coef_val_1", "ir_coef_val_2",
		"ir_coef_val_3", "ir_coef_val_4", "lb-dbv-coefs-id",
		"light-cut",
		/* lb para end */
	};

	for (di = 0; di < ARRAY_SIZE(als_feature); di++) {
		if (!of_property_read_u32(ch_node, als_feature[di], &value))
			hw->feature.feature[di] = value;
		else if (!strncmp(als_feature[di], "norm", 4))
			hw->feature.feature[di] = 1057;
		else if (!strcmp(als_feature[di], "als_ratio_type"))
			hw->feature.feature[di] = 0;
	}

	for (di = 0; di < ARRAY_SIZE(light_para); di++) {
		if (!of_property_read_u32(ch_node, light_para[di], &value))
			hw->feature.parameter[di] = value;
		else if (!strcmp(light_para[di], "gold-reset-scale"))
			hw->feature.parameter[di] = 1001;
		else
			hw->feature.parameter[di] = 0;
	}
}

static void parse_light_rear_sensor_dts(struct sensor_hw *hw,
					struct device_node *ch_node)
{
	int value = 0;

	if (!of_property_read_u32(ch_node, "als-factor", &value))
		hw->feature.feature[0] = value;
}

static void parse_sar_sensor_dts(struct sensor_hw *hw,
				 struct device_node *ch_node)
{
	int di = 0;
	int value = 0;
	int dc_offset_default[SAR_MAX_CH_NUM * 2] = {
		0, 0, 0, 0, 0, 30000, 30000, 30000, 30000, 30000
	};

	if (!of_property_read_u32(ch_node, "parameter-number", &value) &&
	    value > 0 && value < PARAMETER_NUM) {
		of_property_read_u32_array(ch_node, "sensor-reg",
					   (u32 *)&hw->feature.parameter[0], value);
		di = value / 2;	/* the OnePlus driver's index, below */
	}
	/* channel-num goes in feature[di], di left over from the register loop as upstream */
	if (!of_property_read_u32(ch_node, "channel-num", &value) && value < SAR_MAX_CH_NUM)
		hw->feature.feature[di] = value;
	if (!of_property_read_u32(ch_node, "is-dc-offset", &value) && value == 1) {
		/* upstream copies SAR_MAX_CH_NUM * 2 bytes of the default, not ints */
		memcpy(&hw->feature.reg[0], dc_offset_default, SAR_MAX_CH_NUM * 2);
		of_property_read_u32_array(ch_node, "dc-offset",
					   (u32 *)&hw->feature.reg[0], SAR_MAX_CH_NUM * 2);
	}
}

static void parse_down_sar_sensor_dts(struct sensor_hw *hw,
				      struct device_node *ch_node)
{
	int value = 0;

	if (!of_property_read_u32(ch_node, "parameter-number", &value) &&
	    value > 0 && value < PARAMETER_NUM)
		of_property_read_u32_array(ch_node, "sensor-reg",
					   (u32 *)&hw->feature.parameter[0], value);
}

static void parse_cct_sensor_dts(struct sensor_hw *hw,
				 struct device_node *ch_node, bool rear)
{
	int value = 0;
	int di;
	static const char * const feature[] = {
		"decoupled-driver", "publish-sensors", "is-ch-dri",
		"timer-size", "fac-cali-sensor"
	};
	/* the rear CCT has no algo-flag */
	static const char * const para[] = {
		"para-matrix",	 "atime",
		"first-atime",	 "fac-cali-atime",
		"first-again",	 "fac-cali-again",
		"fd-time",	 "fac-cali-fd-time",
		"first-fd-gain", "fac-cali-fd-gain",
		"algo-flag"
	};

	hw->feature.feature[0] = 1; /* default use decoupled driver oplus_cct */
	for (di = 0; di < ARRAY_SIZE(feature); di++)
		if (!of_property_read_u32(ch_node, feature[di], &value))
			hw->feature.feature[di] = value;
	for (di = 0; di < ARRAY_SIZE(para) - (rear ? 1 : 0); di++)
		if (!of_property_read_u32(ch_node, para[di], &value))
			hw->feature.parameter[di] = value;
}

static void parse_accelerometer_sensor_dts(struct sensor_hw *hw,
					   struct device_node *ch_node)
{
	int value = 0;
	int di;
	static const char * const feature[] = { "use-sois", "single-acc" };

	hw->feature.feature[0] = 0; /* default not use s-ois */
	for (di = 0; di < ARRAY_SIZE(feature); di++)
		if (!of_property_read_u32(ch_node, feature[di], &value))
			hw->feature.feature[di] = value;
}

/* by node name, compared on the first 7 characters as upstream does */
static void parse_each_physical_sensor_dts(struct sensor_hw *hw,
					   struct device_node *ch_node)
{
	if (!strncmp(ch_node->name, "msensor", 7))
		parse_magnetic_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "psensor", 7))
		parse_proximity_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "lsensor", 7))
		parse_light_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "ssensor", 7))
		parse_sar_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "cctsensor", 7))
		parse_cct_sensor_dts(hw, ch_node, false);
	else if (!strncmp(ch_node->name, "cctrsensor", 7))
		parse_cct_sensor_dts(hw, ch_node, true);
	else if (!strncmp(ch_node->name, "sdsensor", 7))
		parse_down_sar_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "lrsensor", 7))
		parse_light_rear_sensor_dts(hw, ch_node);
	else if (!strncmp(ch_node->name, "gsensor", 7))
		parse_accelerometer_sensor_dts(hw, ch_node);
}

static void parse_each_virtual_sensor_dts(struct sensor_algorithm *algo,
					  struct device_node *ch_node)
{
	int value = 0;

	if (!strncmp(ch_node->name, "pickup", 6)) {
		if (!of_property_read_u32(ch_node, "is-need-prox", &value))
			algo->feature[0] = value;
		if (!of_property_read_u32(ch_node, "prox-type", &value))
			algo->parameter[0] = value;
	} else if (!strncmp(ch_node->name, "lux_aod", 6)) {
		if (!of_property_read_u32(ch_node, "thrd-low", &value))
			algo->parameter[0] = value;
		if (!of_property_read_u32(ch_node, "thrd-high", &value))
			algo->parameter[1] = value;
		if (!of_property_read_u32(ch_node, "als-type", &value))
			algo->parameter[2] = value;
		if (!of_property_read_u32(ch_node, "fold-feature", &value))
			algo->feature[0] = value;
	} else if (!strncmp(ch_node->name, "fp_display", 6)) {
		if (!of_property_read_u32(ch_node, "prox-type", &value))
			algo->parameter[0] = value;
	} else if (!strncmp(ch_node->name, "mag_fusion", 10)) {
		if (!of_property_read_u32(ch_node, "fusion-type", &value))
			algo->feature[0] = value;
		if (!of_property_read_u32(ch_node, "mag-type", &value))
			algo->feature[1] = value;
	} else if (!strncmp(ch_node->name, "oplus_measurement", 17)) {
		if (!of_property_read_u32(ch_node, "acc-range", &value))
			algo->parameter[0] = value;
		if (!of_property_read_u32(ch_node, "gyro-range", &value))
			algo->parameter[1] = value;
	}
}

static int oplus_devinfo_probe(struct platform_device *pdev)
{
	struct sensor_info *chip = NULL;
	struct sensor_info_old *chip_old = NULL;
	struct device_node *ch_node;
	size_t smem_size = 0;
	void *smem_addr;
	int rc, n = 0;

	rc = qcom_smem_alloc(QCOM_SMEM_HOST_ANY, SMEM_SENSOR, sizeof(struct sensor_info));
	if (rc < 0 && rc != -EEXIST)
		return dev_err_probe(&pdev->dev, rc, "allocating SMEM item %d\n", SMEM_SENSOR);

	smem_addr = qcom_smem_get(QCOM_SMEM_HOST_ANY, SMEM_SENSOR, &smem_size);
	if (IS_ERR(smem_addr))
		return dev_err_probe(&pdev->dev, PTR_ERR(smem_addr),
				     "getting SMEM item %d\n", SMEM_SENSOR);

	if (smem_size == sizeof(struct sensor_info)) {
		chip = smem_addr;
		memset(chip, 0, sizeof(*chip));
	} else if (smem_size == sizeof(struct sensor_info_old)) {
		chip_old = smem_addr;
		memset(chip_old, 0, sizeof(*chip_old));
	} else {
		dev_err(&pdev->dev, "unsupported SMEM item %d size %zu\n", SMEM_SENSOR, smem_size);
		return -EINVAL;
	}

	for_each_child_of_node(pdev->dev.of_node, ch_node) {
		bool is_virtual = of_property_read_bool(ch_node, "is-virtual-sensor");
		u32 type, index;

		if (of_property_read_u32(ch_node, "sensor-type", &type) ||
		    (is_virtual && type >= SENSOR_ALGO_NUM) || type >= SENSORS_NUM)
			continue;

		if (!is_virtual) {
			struct sensor_hw *hw;

			if (chip)
				chip->s_vector[type].sensor_id = type;
			else
				chip_old->s_vector[type].sensor_id = type;
			/* upstream checks SOURCE_NUM for both layouts; the old one has two sources */
			if (of_property_read_u32(ch_node, "sensor-index", &index) ||
			    index >= (chip ? SOURCE_NUM : SOURCE_NUM - 1))
				continue;
			hw = chip ? &chip->s_vector[type].hw[index] :
				    &chip_old->s_vector[type].hw[index];
			parse_physical_sensor_common_dts(hw, ch_node);
			parse_each_physical_sensor_dts(hw, ch_node);
		} else {
			struct sensor_algorithm *algo;

			algo = chip ? &chip->a_vector[type] : &chip_old->a_vector[type];
			algo->sensor_id = type;
			parse_each_virtual_sensor_dts(algo, ch_node);
		}
		n++;
	}

	dev_info(&pdev->dev, "%d entries in SMEM item %d (%zu bytes)\n", n, SMEM_SENSOR, smem_size);
	return 0;
}

static const struct of_device_id oplus_devinfo_match[] = {
	{ .compatible = "oplus,sensor-devinfo" },
	{}
};
MODULE_DEVICE_TABLE(of, oplus_devinfo_match);

static struct platform_driver oplus_devinfo_driver = {
	.probe = oplus_devinfo_probe,
	.driver = {
		.name = "sensor_devinfo",
		.of_match_table = oplus_devinfo_match,
	},
};
module_platform_driver(oplus_devinfo_driver);

MODULE_DESCRIPTION("OPLUS sensor hardware table in SMEM for the sensor DSP");
MODULE_LICENSE("GPL");
