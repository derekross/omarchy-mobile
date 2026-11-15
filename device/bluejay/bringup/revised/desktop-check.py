#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Fail closed before starting the new SDDM unit; changes no screen itself."""
import importlib.util
from pathlib import Path
import sys

spec = importlib.util.spec_from_file_location('revised', Path(__file__).with_name('start.py'))
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)

try:
    c = s.profile()
    s.common(c)
    for stage in s.STAGES:
        s.receipt(stage)
    s.receipt('ack')
    s.check_host()
    log = s.journal('desktop-before')
    s.gpu_post(c)
    s.touch_post(log)
    s.pcie_post(log)
    s.wifi_post(log)
    s.reading()
    s.need(Path('/dev/fb0').is_char_device(), 'retained framebuffer missing')
    s.need(not list(s.STATE.glob('*.pending')), 'unfinished hardware attempt')
except (RuntimeError, OSError, ValueError, KeyError, s.subprocess.SubprocessError) as exc:
    sys.exit('bluejay-revised-desktop: STOP: ' + str(exc))
