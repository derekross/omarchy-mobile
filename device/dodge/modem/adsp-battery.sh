#!/bin/sh
# SPDX-License-Identifier: MIT
# Bring up the ADSP and the PMIC battery manager. Not required for boot.
# Installed as /usr/local/lib/omamobile/adsp-battery.sh (omamobile-adsp-battery.service).
#
# Prefer modprobe so a tip Image with a tmpfs modules overlay gets matching
# kos. Fall back to the pinned held tree (bind-mounted over by
# omamobile-kmod-overlay on gpu2-style boots) and /usr/local/lib/omamobile
# for out-of-tree held kos (pd_mapper / q6v5_pas on 6.16).
#
# The PAS driver is loaded with only_adsp=1 by default, so the modem and the
# CDSP are not probed. Creating /etc/omamobile/modem-probe.enable loads it with
# only_adsp=0 instead.
set -u
HELD=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
D=/usr/local/lib/omamobile

log() { echo "adsp-battery: $*"; }

# Load by module name. modprobe first; else insmod held path or $D.
# Extra args are module parameters (e.g. only_adsp=1).
load() {
	name=$(echo "$1" | tr - _)
	shift || true
	if awk -v m="$name" '$1==m {found=1} END{exit !found}' /proc/modules; then
		return 0
	fi
	if modprobe "$name" "$@" 2>/dev/null; then
		return 0
	fi
	hyphen=$(echo "$name" | tr _ -)
	for f in \
		"$HELD/net/qrtr/$name.ko" "$HELD/net/qrtr/$hyphen.ko" \
		"$HELD/drivers/soc/qcom/$name.ko" "$HELD/drivers/soc/qcom/$hyphen.ko" \
		"$HELD/drivers/remoteproc/$name.ko" "$HELD/drivers/remoteproc/$hyphen.ko" \
		"$HELD/drivers/rpmsg/$name.ko" "$HELD/drivers/rpmsg/$hyphen.ko" \
		"$HELD/drivers/power/supply/$name.ko" "$HELD/drivers/power/supply/$hyphen.ko" \
		"$HELD/drivers/misc/$name.ko" "$HELD/drivers/misc/$hyphen.ko" \
		"$D/$name.ko" "$D/$hyphen.ko"
	do
		[ -f "$f" ] || continue
		if [ "$#" -gt 0 ]; then
			insmod "$f" "$@" 2>/dev/null && return 0
		else
			insmod "$f" 2>/dev/null && return 0
		fi
	done
	return 1
}

opt() {
	if load "$@"; then
		return 0
	fi
	log "$1 not loaded (built-in, or no matching .ko yet)"
	return 0
}

opt qrtr
opt qrtr_smd
opt qmi_helpers
opt qcom_pdr_msg
opt pdr_interface
opt qcom_pil_info
opt mdt_loader
opt qcom_glink_smem
opt qcom_common
opt qcom_sysmon
opt qcom_q6v5
opt qcom_pd_mapper

ONLY_ADSP=1
[ -e /etc/omamobile/modem-probe.enable ] && ONLY_ADSP=0
if ! load qcom_q6v5_pas only_adsp=$ONLY_ADSP; then
	log "qcom_q6v5_pas failed to load"
	exit 1
fi

adsp_state() {
	for r in /sys/class/remoteproc/remoteproc*; do
		[ "$(cat "$r/name" 2>/dev/null)" = adsp ] && { cat "$r/state"; return; }
	done
}
i=0
while [ $i -lt 10 ]; do
	state=$(adsp_state 2>/dev/null || true)
	[ "$state" = running ] && break
	sleep 0.5
	i=$((i + 1))
done
[ "$state" = running ] || log "ADSP not running yet (state=${state:-none})"

opt pmic_glink
opt qcom_battmgr
# FastRPC device for sensors / audio PDs (module only; adsprpcd is audio's job).
opt fastrpc
