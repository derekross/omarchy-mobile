#!/bin/bash
# SPDX-License-Identifier: MIT
# Bring up the ADSP and the PMIC battery manager. Not required for boot.
# Installed as /usr/local/lib/omamobile/adsp-battery.sh (omamobile-adsp-battery.service).
#
# The PAS driver is loaded with only_adsp=1 by default, so the modem and the
# CDSP are not probed. Creating /etc/omamobile/modem-probe.enable loads it with
# only_adsp=0 instead: the MPSS is then probed (auto_boot is off, so it stays
# offline until started by hand) and the CDSP is probed too. Remove the file
# to go back. 
set -u
HELD=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
LOCAL=/usr/local/lib/omamobile
load() {
	local ko="$1"
	shift || true
	local base name
	base=$(basename "$ko" .ko)
	name=${base//-/_}
	if awk -v m="$name" '$1==m {found=1} END{exit !found}' /proc/modules; then
		return 0
	fi
	insmod "$ko" "$@"
}
load "$HELD/net/qrtr/qrtr.ko"
load "$HELD/net/qrtr/qrtr-smd.ko"
load "$HELD/drivers/soc/qcom/qmi_helpers.ko"
load "$HELD/drivers/soc/qcom/qcom_pdr_msg.ko"
load "$HELD/drivers/soc/qcom/pdr_interface.ko"
load "$HELD/drivers/remoteproc/qcom_pil_info.ko"
load "$HELD/drivers/soc/qcom/mdt_loader.ko"
load "$HELD/drivers/rpmsg/qcom_glink_smem.ko"
load "$HELD/drivers/remoteproc/qcom_common.ko"
load "$HELD/drivers/remoteproc/qcom_sysmon.ko"
load "$HELD/drivers/remoteproc/qcom_q6v5.ko"
load "$LOCAL/qcom_pd_mapper.ko"
ONLY_ADSP=1
[ -e /etc/omamobile/modem-probe.enable ] && ONLY_ADSP=0
load "$LOCAL/qcom_q6v5_pas.ko" only_adsp=$ONLY_ADSP
adsp_state() {
	local r
	for r in /sys/class/remoteproc/remoteproc*; do
		[ "$(cat "$r/name" 2>/dev/null)" = adsp ] && { cat "$r/state"; return; }
	done
}
for _ in 1 2 3 4 5 6 7 8 9 10; do
	state=$(adsp_state 2>/dev/null || true)
	[ "$state" = running ] && break
	sleep 0.5
done
load "$HELD/drivers/soc/qcom/pmic_glink.ko"
load "$HELD/drivers/power/supply/qcom_battmgr.ko"
