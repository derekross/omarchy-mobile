# SPDX-License-Identifier: BSD-3-Clause
# AudioReach topology for the OnePlus 13 (dodge, SM8750).
# Derived from linux-msm/audioreach-topology SM8550-HDK.m4 and
# Google-SC7180-WSA-Speakers-SEC-I2S-VA-DMIC-WCD-TX3.m4 (Copyright, Linaro Ltd, 2023).
# Speakers: two smart amplifiers on Secondary MI2S (TLMM i2s1), playback on SD1.
# Headset: WCD939x HPH over RX codec DMA 0 (USB-C analog), fed from MultiMedia1.
# Microphones: WCD939x ADCs over SoundWire TX into TX codec DMA 3, captured on MultiMedia3.
# Build: m4 -I <audioreach-topology> OnePlus-dodge.m4 > OnePlus-dodge.conf
#        alsatplg -c OnePlus-dodge.conf -o OnePlus-dodge-tplg.bin
# Install on the phone as /lib/firmware/qcom/sm8750/OnePlus-dodge-tplg.bin
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
dnl Playback MultiMedia1
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl Capture MultiMedia3
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006020, `110000')
dnl Secondary MI2S Playback (speaker amplifiers). The amplifiers listen on
dnl i2s1 data1 (gpio124), the DSP's SD1: on SD0 they never left the noise gate.
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `Secondary', SECONDARY_MI2S_RX,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_SECONDARY, SD_LINE_IDX_I2S_SD1, DATA_FORMAT_FIXED_POINT,
	0x00004005, 0x00004005, 0x00006050, `SECONDARY_MI2S_RX')
dnl WCD RX Playback (USB-C analog headset)
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-playback.m4, `RX_CODEC_DMA_RX_0', RX_CODEC_DMA_RX_0,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_RX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004007, 0x00004007, 0x00006070)
dnl WCD TX Capture (built-in and headset microphones)
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `TX_CODEC_DMA_TX_3', TX_CODEC_DMA_TX_3,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_RXTX, CODEC_INTF_IDX_TX3, 0, DATA_FORMAT_FIXED_POINT,
	0x00004009, 0x00004009, 0x00006090)
dnl
STREAM_DEVICE_PLAYBACK_MIXER(SECONDARY_MI2S_RX, ``SECONDARY_MI2S_RX'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(SECONDARY_MI2S_RX, ``SECONDARY_MI2S_RX Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_PLAYBACK_MIXER(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_ROUTE(RX_CODEC_DMA_RX_0, ``RX_CODEC_DMA_RX_0 Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``TX_CODEC_DMA_TX_3'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``TX_CODEC_DMA_TX_3, device120.logger1'')
