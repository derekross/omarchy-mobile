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
        for name, value in [('voltage_now', voltage), ('current_now', current),
                            ('current_avg', average)]:
            path = battery / name
            path.unlink(missing_ok=True)
            if value is not None:
                path.write_text(value)
        return subprocess.run(['bash', '-uc', function + '\nbat=$1; csv=/dev/stdout; '
                               'trap \'echo restored > "$bat/restored"\' EXIT; '
                               'date() { echo 42; }; sample A' ,
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
            assert result.stdout == '', result.stdout
            assert (battery / 'restored').read_text() == 'restored\n'
    result = sample('4000000', '-120000', 'invalid')
    assert result.returncode != 0 and result.stdout == ''
    for name in ['charge_counter', 'charge_now']:
        path = battery / name
        path.write_text('bad')
        result = sample('4000000', '-120000')
        assert result.returncode != 0 and result.stdout == ''
        path.unlink()
print('ok - signed/zero current, optional average, failed and malformed required reads')
