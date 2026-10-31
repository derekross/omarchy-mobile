#!/bin/bash
# SPDX-License-Identifier: MIT
# dodge speaker audio bring-up, run as root by omamobile-dodge-audio.service
# after omamobile-adsp-battery.service has the ADSP running. Installed as
# /usr/local/lib/omamobile/audio-bringup.sh.
# Prefer modprobe so a tip Image with a tmpfs modules overlay gets matching
# kos. Fall back to the pinned held tree for gpu2-style boots.
# Order matters: the FastRPC audio heap must be assigned before q6apm
# probes, or APM_CMD_GET_SPF_STATE times out.
# Never rmmod the card or unbind q6apm-dai after the topology loaded:
# that oopsed in snd_soc_unregister_component_by_driver (2026-10-20).
set -u
HELD=/usr/lib/modules/6.16.0-gb3ee311dab85.held/kernel
RPC=/usr/local/lib/omamobile/fastrpc
log() { echo "audio-bringup: $*"; }

# $1 = relative path under kernel/ (held) OR a bare module name.
# Prefer modprobe of the basename; else insmod held path.
load() {
	local rel=$1
	shift || true
	local base name err
	base=$(basename "$rel" .ko)
	name=$(echo "$base" | tr - _)
	if awk -v m="$name" '$1==m {found=1} END{exit !found}' /proc/modules; then
		return 0
	fi
	if modprobe "$name" "$@" 2>/dev/null; then
		return 0
	fi
	err=$(insmod "$HELD/$rel" "$@" 2>&1) && return 0
	case $err in *"File exists"*) return 0 ;; esac
	log "load $base failed: $err"; exit 1
}

[ -e /proc/device-tree/sound/compatible ] || { log "no sound node in this DTB"; exit 1; }
adsp_state() {
	local r
	for r in /sys/class/remoteproc/remoteproc*; do
		[ "$(cat "$r/name" 2>/dev/null)" = adsp ] && { cat "$r/state" 2>/dev/null; return; }
	done
}
for _ in $(seq 40); do
	[ "$(adsp_state)" = running ] && break
	sleep 0.5
done
[ "$(adsp_state)" = running ] || { log "ADSP not running"; exit 1; }

# 7.3: upstream fastrpc assigns the audio PD heap itself inside
# adsprpcd's create-static-PD call. Readiness: that call returned.
heap_ready() {
	inv=$(systemctl show -p InvocationID --value x-adsprpcd 2>/dev/null)
	[ -n "$inv" ] && journalctl -q -o cat _SYSTEMD_INVOCATION_ID="$inv" 2>/dev/null |
		grep -q 'Successfully opened handle.*createstaticpd:audiopd' && return 0
	dmesg | grep -q "assigned audio heap"
}
load drivers/misc/fastrpc.ko
for _ in $(seq 20); do [ -e /dev/fastrpc-adsp-secure ] && break; sleep 0.5; done
if ! systemctl is-active -q x-adsprpcd; then
	systemd-run --unit=x-adsprpcd -p WorkingDirectory=$RPC \
		-E LD_LIBRARY_PATH=$RPC $RPC/adsprpcd audiopd adsp
fi
for _ in $(seq 40); do
	heap_ready && break
	sleep 0.5
done
heap_ready || { log "audio heap not assigned (no audiopd static PD)"; exit 1; }

load drivers/soc/qcom/apr.ko
load sound/soc/qcom/qdsp6/snd-q6dsp-common.ko
load sound/soc/qcom/qdsp6/snd-q6apm.ko
load sound/soc/qcom/qdsp6/q6prm.ko
load sound/soc/qcom/qdsp6/q6prm-clocks.ko
for _ in $(seq 40); do
	[ -e /sys/bus/platform/devices/6800000.remoteproc:glink-edge:gpr:service@1:dais ] && break
	sleep 0.5
done
load sound/soc/qcom/qdsp6/q6apm-dai.ko
load sound/soc/qcom/qdsp6/q6apm-lpass-dais.ko

load drivers/i2c/busses/i2c-qcom-geni.ko
load sound/soc/codecs/snd-soc-aw882308.ko

load drivers/soundwire/soundwire-bus.ko

if [ -e /proc/device-tree/audio-codec/compatible ]; then
	load drivers/pinctrl/qcom/pinctrl-lpass-lpi.ko
	load drivers/pinctrl/qcom/pinctrl-sm8650-lpass-lpi.ko
	load sound/soc/codecs/snd-soc-lpass-macro-common.ko
	load sound/soc/codecs/snd-soc-lpass-va-macro.ko
	load sound/soc/codecs/snd-soc-lpass-tx-macro.ko
	load sound/soc/codecs/snd-soc-lpass-rx-macro.ko
	load drivers/base/regmap/regmap-sdw.ko
	load sound/soc/codecs/snd-soc-wcd-mbhc.ko
	load sound/soc/codecs/snd-soc-wcd-classh.ko
	load sound/soc/codecs/snd-soc-wcd-common.ko
	load sound/soc/codecs/snd-soc-wcd939x-sdw.ko
	load sound/soc/codecs/snd-soc-wcd939x.ko
	load drivers/usb/typec/mux/wcd939x-usbss.ko
	for _ in $(seq 20); do
		[ -e /sys/bus/i2c/drivers/wcd939x-usbss/3-000e ] && break
		sleep 0.5
	done
	[ -e /sys/bus/i2c/drivers/wcd939x-usbss/3-000e ] || log "warning: wcd939x-usbss not bound"
	load drivers/slimbus/slimbus.ko
	load drivers/soundwire/soundwire-qcom.ko
	for _ in $(seq 20); do
		[ -e /sys/bus/platform/drivers/wcd939x_codec/audio-codec ] && break
		sleep 0.5
	done
	[ -e /sys/bus/platform/drivers/wcd939x_codec/audio-codec ] || log "warning: wcd939x not bound"
fi

load sound/soc/qcom/snd-soc-qcom-common.ko
load sound/soc/qcom/snd-soc-qcom-sdw.ko
load sound/soc/qcom/snd-soc-sc8280xp.ko
for _ in $(seq 20); do grep -q OnePlusdodge /proc/asound/cards && break; sleep 0.5; done
cat /proc/asound/cards
