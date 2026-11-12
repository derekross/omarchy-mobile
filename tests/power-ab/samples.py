#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Exercise the production sampler with files, without phone operations."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'tools/power-ab').read_text()
function = source[source.index('sample() {'):source.index('\nfreeze_phase()')]
with tempfile.TemporaryDirectory() as tmp:
    battery = Path(tmp)
    def sample(voltage, current, average=None):
        (battery / 'restored').unlink(missing_ok=True)
        for name, value in [('voltage_now', voltage), ('current_now', current),
                            ('current_avg', average)]:
            path = battery / name
            path.unlink(missing_ok=True)
            if value is not None:
                path.write_text(value)
        return subprocess.run(['bash', '-uc', function + '\nbat=$1; csv=/dev/stdout; '
                               'trap \'echo restored > "$bat/restored"\' EXIT; '
                               'date() { echo 42; }; sleep() { :; }; sample A' ,
                               'test', tmp], capture_output=True, text=True)

    for current in ['-120000', '0', '120000']:
        result = sample('4000000', current)
        assert result.returncode == 0, result.stderr
        assert result.stdout == f'42,A,4000000,{current},,,\n'
    result = sample('4000000', '-120000', '-110000')
    assert result.stdout == '42,A,4000000,-120000,-110000,,\n'
    for bad in [None, '', 'garbage', '12.5', '1\n2']:
        for voltage, current in [(bad, '-120000'), ('4000000', bad)]:
            result = sample(voltage, current)
            assert result.returncode != 0, (voltage, current)
            assert result.stdout.startswith('# power-ab: invalid or unavailable ') and 'after retry; stopping' in result.stdout, result.stdout
            assert (battery / 'restored').read_text() == 'restored\n'
    # Simulate one stale sysfs read followed by a good reading.
    (battery / 'voltage_now').write_text('4000000')
    (battery / 'current_now').write_text('-120000')
    for required in ['voltage_now', 'current_now']:
        (battery / 'attempt').unlink(missing_ok=True)
        retry = subprocess.run(['bash', '-uc', function + "\nbat=$1; target=$2; csv=/dev/stdout; "
                                'date() { echo 42; }; sleep() { [[ $1 == 1 ]] && touch "$bat/waited"; }; '
                                'cat() { if [[ $1 == "$bat/$target" && ! -e $bat/attempt ]]; then '
                                'touch "$bat/attempt"; return 1; fi; '
                                'if [[ $1 == "$bat/$target" ]]; then [[ -e $bat/waited ]] || return 1; fi; '
                                'command cat "$@"; }; sample A',
                                'test', tmp, required], capture_output=True, text=True)
        assert retry.returncode == 0 and retry.stdout == '42,A,4000000,-120000,,,\n'
        (battery / 'waited').unlink()
    result = sample('4000000', '-120000', 'invalid')
    assert result.returncode == 0 and result.stdout == '42,A,4000000,-120000,,,\n'
    for name in ['charge_counter', 'charge_now']:
        path = battery / name
        path.write_text('bad')
        result = sample('4000000', '-120000')
        assert result.returncode == 0 and result.stdout == '42,A,4000000,-120000,,,\n'
        path.unlink()
print('ok - signed/zero current, optional average, failed and malformed required reads')
