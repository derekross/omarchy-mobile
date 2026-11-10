#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Insert actual QuickSettings callbacks into the real-row refusal fixture."""
from pathlib import Path
import sys

here = Path(__file__).resolve().parent
source = (here / "../plugins/omamobile.quicksettings/QuickSettings.qml").read_text()


def body(start):
    begin = source.index("{", start)
    depth = 1
    end = begin + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[begin:end]


def function(name):
    start = source.index("  function " + name + "(")
    begin = source.index("{", start)
    return source[start:begin] + body(start)


callbacks = [function(name) for name in (
    "acknowledgeNotifications", "forgetNotification", "runForget")]
start = source.index("onExited: function(code)", source.index("id: forgetProc\n"))
callbacks.append("    function forgetDone(code) " + body(start))
start = source.index("onStreamFinished:", source.index("id: notificationsRead\n"))
callbacks.append("    function readDone(text) " + body(start))
fixture = (here / "notification-refusal.qml").read_text()
assert fixture.count("// PRODUCTION_CALLBACKS") == 1
Path(sys.argv[1]).write_text(fixture.replace("// PRODUCTION_CALLBACKS", "\n".join(callbacks)))
