#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import shlex
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader('browser_setup', str(Path(__file__).resolve().parents[1] / 'bin/omamobile-browser-setup'))
spec = importlib.util.spec_from_loader(loader.name, loader)
M = importlib.util.module_from_spec(spec)
loader.exec_module(M)


class BrowserSetupTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.config = self.root / '.config'
        self.config.mkdir()
        self.done = self.root / '.local/state/omarchy/done'
        self.path = self.config / 'chromium-flags.conf'

    def mark(self, *names):
        self.done.mkdir(parents=True, exist_ok=True)
        for name in names:
            (self.done / ('omamobile-' + name)).touch()

    def configure(self, program='chromium', factor='0.62'):
        M.configure(self.path, factor, self.done, program)

    def test_geometry_shared_fit_and_landscape(self):
        for width, scale, expected in [(1080, 3, '0.62'), (1440, 3, '0.83'), (1080, 8 / 3, '0.70'), (1080, 2, '0.83')]:
            for name in ('DSI-1', 'eDP-1', 'Unknown-1'):
                monitors = [{'name': name, 'width': width, 'height': 2400, 'scale': scale}, {'name': 'DP-1', 'width': 3840, 'height': 2160, 'scale': 1}]
                self.assertEqual(M.factor_for(M.logical_width(monitors)), expected)
                monitors[0].update(width=2400, height=width, transform=1)
                self.assertEqual(M.factor_for(M.logical_width(monitors)), expected)
        self.assertIsNone(M.logical_width([{'name': 'DSI-1', 'width': 0, 'height': 0, 'scale': 0}]))

    def test_numeric_scale_only(self):
        self.assertEqual(M.monitor_scale('local omarchy_monitor_scale = 8 / 3\n'), 8 / 3)
        for text in ['"auto"', 'os.execute("touch bad")', '1 / 0', '-1', '0', 'math.huge']:
            self.assertIsNone(M.monitor_scale('local omarchy_monitor_scale = ' + text))

    def test_precompositor_geometry_and_defer(self):
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/monitors.lua').write_text('local omarchy_monitor_scale = 3\n')
        modes = self.root / 'drm/card0-Unknown-1/modes'
        modes.parent.mkdir(parents=True)
        modes.write_text('1080x2400\n')
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_STATE_HOME': str(self.root / 'other-state'), 'XDG_CONFIG_HOME': str(self.root / 'other-config'), 'OMAMOBILE_DRM': str(self.root / 'drm')}), patch.object(M.subprocess, 'run', side_effect=OSError):
            self.assertEqual(M.geometry(self.config), 360)
            modes.unlink()
            M.main()
            initial = shlex.split(self.path.read_text())
            self.assertIn('--no-first-run', initial)
            self.assertIn('--enable-wayland-ime', initial)
            self.assertIn('--wayland-text-input-version=3', initial)
            self.assertEqual(len([f for f in initial if f.startswith('--user-agent=')]), 1)
            self.assertFalse(any(f.startswith('--force-device-scale-factor=') for f in initial))
            self.assertFalse((self.done / 'omamobile-browser-fit-chromium').exists())
            self.assertFalse((self.config / 'grok-bot-flags.conf').exists())
            modes.write_text('1080x2400\n')
            M.main()
            self.assertIn('--force-device-scale-factor=0.62', self.path.read_text())
            self.assertEqual((self.config / 'grok-bot-flags.conf').read_text(), '--force-device-scale-factor=0.62\n')
            self.assertFalse((self.config / 'chrome-flags.conf').exists())

    def test_deferred_fit_keeps_defaults_removed_before_shell_retry(self):
        with patch.dict(os.environ, {'HOME': str(self.root)}), patch.object(M, 'geometry', return_value=None), patch.object(M, 'browser_major', return_value='157') as version:
            M.main()
            self.path.write_text('# desktop sites, system input method\n')
            M.main()
            self.assertEqual(self.path.read_text(), '# desktop sites, system input method\n')
            version.assert_called_once_with('chromium')
        with patch.dict(os.environ, {'HOME': str(self.root)}), patch.object(M, 'geometry', return_value=360), patch.object(M, 'browser_major') as version:
            M.main()
            self.assertEqual(self.path.read_text(), '# desktop sites, system input method\n--force-device-scale-factor=0.62\n')
            self.assertTrue((self.done / 'omamobile-browser-fit-chromium').exists())
            self.assertEqual((self.config / 'grok-bot-flags.conf').read_text(), '--force-device-scale-factor=0.62\n')
            version.assert_not_called()

    def test_deferred_migration_preserves_historical_choices(self):
        self.mark('chromium-mobile', 'chromium-wayland-ime', 'chromium-no-first-run', 'chromium-scale-3')
        self.path.write_text('--force-device-scale-factor=0.83\n')
        with patch.object(M, 'browser_major') as version:
            self.configure(factor=None)
            self.assertEqual(self.path.read_text(), '--force-device-scale-factor=0.83\n')
            self.configure()
            self.assertEqual(self.path.read_text(), '--force-device-scale-factor=0.62\n')
            version.assert_not_called()

    def test_computed_scale_gets_its_fit_from_live_session_retry(self):
        (self.config / 'hypr').mkdir()
        (self.config / 'hypr/monitors.lua').write_text('local omarchy_monitor_scale = math.max(1, 3)\n')
        with patch.dict(os.environ, {'HOME': str(self.root), 'OMAMOBILE_DRM': str(self.root / 'no-drm')}), patch.object(M, 'browser_major', return_value='157') as version:
            with patch.object(M.subprocess, 'run', side_effect=OSError):
                M.main()
            self.assertIn('--enable-wayland-ime', self.path.read_text())
            self.assertNotIn('--force-device-scale-factor', self.path.read_text())
            monitors = [{'name': 'Unknown-1', 'width': 1080, 'height': 2400, 'scale': 3}]
            with patch.object(M.subprocess, 'run', return_value=SimpleNamespace(stdout=json.dumps(monitors))):
                M.main()
            self.assertIn('--force-device-scale-factor=0.62', self.path.read_text())
            self.assertEqual((self.config / 'grok-bot-flags.conf').read_text(), '--force-device-scale-factor=0.62\n')
            version.assert_called_once_with('chromium')

    def test_defaults_once_and_ua_one_argument(self):
        with patch.object(M, 'browser_major', return_value='157') as version:
            self.configure()
            ua = [f for f in shlex.split(self.path.read_text(), comments=True) if f.startswith('--user-agent=')]
            self.assertEqual(ua, ['--user-agent=Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Mobile Safari/537.36'])
            # Removing every generated flag is a deliberate user choice.
            self.path.write_text('# desktop sites and system defaults\n')
            self.configure()
            self.assertEqual(self.path.read_text(), '# desktop sites and system defaults\n')
            version.assert_called_once_with('chromium')

    def test_historical_markers_preserve_removed_ua_ime_and_scale(self):
        self.mark('chromium-mobile', 'chromium-wayland-ime', 'chromium-no-first-run', 'chromium-scale-3')
        with patch.object(M, 'browser_major') as version:
            self.configure()
            self.assertFalse(self.path.exists())
            version.assert_not_called()

    def test_upgrade_uses_omarchy_marker_path_with_custom_xdg(self):
        self.mark('chromium-mobile', 'chromium-wayland-ime', 'chromium-no-first-run', 'chromium-scale-3')
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_STATE_HOME': str(self.root / 'elsewhere')}), patch.object(M, 'geometry', return_value=360), patch.object(M, 'browser_major') as version:
            M.main()
            self.assertFalse(self.path.exists())
            self.assertTrue((self.done / 'omamobile-browser-fit-chromium').exists())
            version.assert_not_called()

    def test_exact_generated_migration_once_for_both_programs(self):
        for program, legacy in [('chromium', 'chromium-scale-2'), ('grok-bot', 'grok-bot-fit')]:
            with self.subTest(program=program):
                self.mark(legacy, 'chromium-mobile', 'chromium-no-first-run', 'chromium-wayland-ime')
                self.path.write_text('# own comment\n--force-device-scale-factor=0.83\n--disable-gpu\n')
                with patch.object(M, 'browser_major') as version:
                    self.configure(program)
                    self.assertEqual(self.path.read_text(), '# own comment\n--force-device-scale-factor=0.62\n--disable-gpu\n')
                    self.path.write_text('--force-device-scale-factor=0.83\n')
                    self.configure(program)
                    self.assertEqual(self.path.read_text(), '--force-device-scale-factor=0.83\n')
                    version.assert_not_called()

    def test_custom_flags_and_quoted_override(self):
        self.mark('chromium-scale-3')
        original = '# personal\n"--force-device-scale-factor=0.83"\n"--user-agent=My own agent"\n--disable-gpu\n--wayland-text-input-version=1\n'
        self.path.write_text(original)
        with patch.object(M, 'browser_major') as version:
            self.configure()
            self.assertTrue(self.path.read_text().startswith(original))
            self.assertNotIn('--wayland-text-input-version=3', self.path.read_text())
            version.assert_not_called()

    def test_custom_personal_scale_preserved(self):
        self.mark('chromium-scale-3')
        self.path.write_text('--force-device-scale-factor=0.70\n')
        with patch.object(M, 'browser_major', return_value='157'):
            self.configure()
        self.assertTrue(self.path.read_text().startswith('--force-device-scale-factor=0.70\n'))

    def test_malformed_flags_retry_without_marking(self):
        self.path.write_text('"unterminated')
        with self.assertRaises(ValueError):
            self.configure()
        self.assertEqual(self.path.read_text(), '"unterminated')
        self.assertFalse(self.done.exists())

    def test_later_logins_start_no_process(self):
        self.mark('browser-fit-chromium', 'browser-fit-grok-bot')
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_STATE_HOME': str(self.root / 'other-state'), 'XDG_CONFIG_HOME': str(self.root / 'other-config')}), patch.object(M.subprocess, 'run') as run:
            M.main()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
