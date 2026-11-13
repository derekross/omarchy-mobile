# SPDX-License-Identifier: MIT
# The Change PIN page's worker, started by pin.sh as `python3 -I pin.py`. The PIN is the account password (the lock
# screen checks it with pam_unix), so this runs the system's own /usr/bin/passwd in a pseudo-terminal and lets it do
# the checking. Three lines come from stdin: the current PIN, the new PIN, the new PIN again. They are only ever on
# stdin and in this process's memory: never an argument, never in the environment, never logged, never printed.
# passwd runs with LC_ALL=C and a minimal environment, so its prompts are the English ones matched here. Rules: the
# new PIN is digits only, 4 to 8 long, differs from the current one and is typed twice; everything else is up to
# passwd. After DEADLINE seconds passwd is killed: before the retype is sent nothing has changed, after it nobody can
# say, and the result says so. The binary is /usr/bin/passwd and nothing in the environment changes that; the test
# runs a copy of this file with the path and the deadline replaced.
import json, os, pty, re, select, signal, sys, time
DEADLINE = 12
passwd = "/usr/bin/passwd"
def say(**kw):
    print(json.dumps(kw, separators=(",", ":")), flush=True)
def fail(msg):
    say(error=msg)
    sys.exit(2)
def entry(why):
    line = sys.stdin.readline()
    if not line:
        fail(why)
    return line.rstrip("\n")
old = entry("no current PIN")
new = entry("no new PIN")
again = entry("no confirmation")
if not re.fullmatch(r"[0-9]{1,64}", old): fail("current PIN must be digits")
if not re.fullmatch(r"[0-9]{4,8}", new): fail("new PIN must be 4 to 8 digits")
if new != again: fail("the new PINs do not match")
if new == old: fail("the new PIN is the same as the current one")

pid, fd = pty.fork()
if pid == 0:
    os.execve(passwd, [passwd], {"LC_ALL": "C", "LANGUAGE": "C", "PATH": "/usr/bin"})
cur_re = re.compile(rb"(current|old).{0,20}(password|pin)\s*:\s*$")
new_re = re.compile(rb"(?<!retype )new.{0,10}password\s*:\s*$")
retype_re = re.compile(rb"retype.{0,20}password\s*:\s*$")
refuse_re = re.compile(rb"bad password|too short|too simple|choose a longer|do not match|does not match|password unchanged")
buf = b""
stage = 0
refused = False
timed_out = False
deadline = time.monotonic() + DEADLINE
while True:
    left = deadline - time.monotonic()
    if left <= 0:
        timed_out = True
        break
    r, _, _ = select.select([fd], [], [], min(left, 0.5))
    if not r:
        continue
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    buf += chunk
    low = buf.lower()
    if stage >= 2 and (refuse_re.search(low) or (new_re.search(low) and stage >= 2)):
        refused = True
        break
    if stage == 0 and cur_re.search(low):
        os.write(fd, (old + "\n").encode()); stage = 1; buf = b""
    elif stage == 1 and new_re.search(low):
        os.write(fd, (new + "\n").encode()); stage = 2; buf = b""
    elif stage == 2 and retype_re.search(low):
        os.write(fd, (new + "\n").encode()); stage = 3; buf = b""
old = new = again = ""
code = None
status = 0
# give a passwd that has closed the terminal a moment to exit by itself, unless we are stopping it
grace = time.monotonic() + (0 if (timed_out or refused) else 3)
while True:
    try:
        done, status = os.waitpid(pid, os.WNOHANG)
    except ChildProcessError:
        done, status = pid, 1 << 8
    if done:
        code = os.waitstatus_to_exitcode(status)
        break
    if time.monotonic() >= grace:
        break
    time.sleep(0.05)
if code is None:
    for sig in (signal.SIGHUP, signal.SIGKILL):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            break
        time.sleep(0.2)
        try:
            done, status = os.waitpid(pid, os.WNOHANG)
        except ChildProcessError:
            break
        if done:
            break
    else:
        try:
            os.waitpid(pid, 0)
        except ChildProcessError:
            pass
if code is None and not refused:
    timed_out = True
if timed_out:
    if stage == 3:
        fail("passwd did not finish in time; the PIN may or may not have changed, try the new PIN first and then the old one")
    fail("passwd did not answer in time; nothing was changed")
if refused:
    fail("the system refused the new PIN")
if stage == 3 and code == 0:
    say(changed=True)
elif stage == 0:
    fail("passwd did not ask for the current PIN as expected; nothing was changed")
elif stage == 1:
    fail("the current PIN was not accepted")
else:
    fail("the system refused the new PIN")
