# SPDX-License-Identifier: MIT
import errno, json, os, stat, subprocess, sys, tempfile, threading, unittest
from pathlib import Path
from unittest.mock import patch
from files_core import dispatch, FileError, snapshot, no_replace

class CoreTests(unittest.TestCase):

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='mobile-files-fixture-')
        self.root = Path(self.temp.name)
        self.source = self.root / 'Quelle'
        self.source.mkdir()
        self.dest = self.root / 'Ziel'
        self.dest.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def f(self, name='Straße 100% #1.txt', data=b'hello'):
        p = self.source / name
        p.write_bytes(data)
        return p

    def error(self, code, action, payload, event=None):
        with self.assertRaises(FileError) as raised:
            dispatch(action, payload, event)
        self.assertEqual(raised.exception.code, code)
        return raised.exception

    def test_browse_hidden_unicode_sort(self):
        self.f()
        self.f('.hidden')
        (self.source / 'Ordner').mkdir()
        r = dispatch('list', {'path': str(self.source)})
        self.assertEqual(r['total'], 2)
        self.assertTrue(r['items'][0]['isDirectory'])
        self.assertEqual(dispatch('list', {'path': str(self.source), 'hidden': True})['total'], 3)

    def test_search_recursive_symlinks_not_followed(self):
        folder = self.source / 'folder'
        folder.mkdir()
        (folder / 'find me.txt').write_text('x')
        (self.source / 'loop').symlink_to(self.source, target_is_directory=True)
        r = dispatch('search', {'path': str(self.source), 'query': 'find', 'recursive': True})
        self.assertEqual(r['total'], 1)

    def test_copy_file_atomic_no_overwrite(self):
        p = self.f()
        r = dispatch('copy', {'sources': [{'path': str(p), 'token': snapshot(p)}], 'destination': str(self.dest)})
        self.assertEqual((self.dest / p.name).read_bytes(), b'hello')
        self.assertEqual(len(r['completed']), 1)
        self.error('collision', 'copy', {'sources': [str(p)], 'destination': str(self.dest)})

    def test_copy_link_not_target(self):
        p = self.f()
        link = self.source / 'link'
        link.symlink_to(p)
        dispatch('copy', {'sources': [str(link)], 'destination': str(self.dest)})
        self.assertTrue((self.dest / 'link').is_symlink())
        self.assertEqual(os.readlink(self.dest / 'link'), str(p))
        self.assertEqual(p.read_bytes(), b'hello')

    def test_copy_dangling_link(self):
        link = self.source / 'dangling'
        link.symlink_to('missing')
        dispatch('copy', {'sources': [str(link)], 'destination': str(self.dest)})
        self.assertEqual(os.readlink(self.dest / 'dangling'), 'missing')

    def test_copy_tree_and_hidden(self):
        d = self.source / 'tree'
        d.mkdir()
        (d / '.hidden').write_text('data')
        (d / 'loop').symlink_to('..')
        dispatch('copy', {'sources': [str(d)], 'destination': str(self.dest)})
        self.assertEqual((self.dest / 'tree/.hidden').read_text(), 'data')
        self.assertTrue((self.dest / 'tree/loop').is_symlink())

    def test_recursive_destination_rejected(self):
        d = self.source / 'tree'
        d.mkdir()
        self.error('recursive_destination', 'copy', {'sources': [str(self.source)], 'destination': str(d)})

    def test_stale_selection(self):
        p = self.f()
        t = snapshot(p)
        p.write_text('changed')
        self.error('changed', 'copy', {'sources': [{'path': str(p), 'token': t}], 'destination': str(self.dest)})
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_cancel_cleans_staging(self):
        p = self.f(data=b'x' * 2000000)
        event = threading.Event()

        def progress(_):
            event.set()
        from files_core import transfer
        with self.assertRaises(FileError) as e:
            transfer({'sources': [str(p)], 'destination': str(self.dest)}, event=event, callback=progress)
        self.assertEqual(e.exception.code, 'cancelled')
        self.assertEqual(list(self.dest.iterdir()), [])
        self.assertTrue(p.exists())

    def test_disk_full_no_final_or_temporary(self):
        p = self.f()
        with patch('files_core.os.fsync', side_effect=OSError(errno.ENOSPC, 'fixture full')):
            self.error('no_space', 'copy', {'sources': [str(p)], 'destination': str(self.dest)})
        self.assertEqual(list(self.dest.iterdir()), [])
        self.assertTrue(p.exists())

    def test_move_rename_mkdir(self):
        p = self.f()
        dispatch('move', {'sources': [str(p)], 'destination': str(self.dest)})
        self.assertFalse(p.exists())
        target = self.dest / p.name
        dispatch('rename', {'source': {'path': str(target), 'token': snapshot(target)}, 'name': 'Neu α.txt'})
        self.assertTrue((self.dest / 'Neu α.txt').exists())
        dispatch('mkdir', {'path': str(self.dest), 'name': 'Neuer Ordner'})
        self.assertTrue((self.dest / 'Neuer Ordner').is_dir())

    def test_rename_never_replaces(self):
        a = self.f('a')
        b = self.f('b', b'keep')
        self.error('collision', 'rename', {'source': str(a), 'name': 'b'})
        self.assertEqual(b.read_bytes(), b'keep')
        self.assertTrue(a.exists())

    def test_bad_name(self):
        for name in ['../escape', 'a/b', '.', '..', '']:
            self.error('invalid_name', 'mkdir', {'path': str(self.source), 'name': name})

    def test_atomic_raced_directory_collision(self):
        a = self.source / 'a'
        a.mkdir()
        b = self.dest / 'a'
        b.mkdir()
        with self.assertRaises(FileExistsError):
            no_replace(str(a), str(b))
        self.assertTrue(a.exists())
        self.assertTrue(b.exists())

    def test_nonexistent(self):
        self.error('not_found', 'copy', {'sources': [str(self.source / 'gone')], 'destination': str(self.dest)})

    def test_no_device_thumbnail_or_remote(self):
        self.error('unsupported_thumbnail', 'thumbnail', {'path': str(self.f('not.png', b'<svg>not raster</svg>'))})
        self.error('invalid_path', 'list', {'path': 'a\x00b'})

    def test_open_exact_argv(self):
        p = self.f("a ' $(touch BAD).txt")
        with patch('files_core.subprocess.run') as run:
            run.return_value.returncode = 0
            dispatch('open', {'path': str(p)})
            self.assertEqual(run.call_args.args[0], ['xdg-open', str(p)])
        self.assertFalse((self.root / 'BAD').exists())

    def test_trash_real_fixture_link_only(self):
        p = self.f()
        link = self.source / 'link'
        link.symlink_to(p)
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_DATA_HOME': str(self.root / 'data')}):
            result = dispatch('trash', {'sources': [str(link)]})
            self.assertTrue(result['reversible'])
            self.assertFalse(os.path.lexists(link))
            self.assertTrue(p.exists())

    def test_partial_batch_truthful(self):
        a = self.f('a')
        b = self.f('b')
        real = no_replace
        count = [0]

        def replace(source, target):
            count[0] += 1
            if count[0] == 2:
                raise OSError(errno.ENOSPC, 'fixture full')
            return real(source, target)
        with patch('files_core.no_replace', side_effect=replace):
            e = self.error('no_space', 'copy', {'sources': [str(a), str(b)], 'destination': str(self.dest)})
        self.assertEqual(len(e.details['completed']), 1)
        self.assertTrue((self.dest / 'a').exists())
        self.assertFalse((self.dest / 'b').exists())
        self.assertTrue(b.exists())

class ExtraTests(unittest.TestCase):
    setUp = CoreTests.setUp
    tearDown = CoreTests.tearDown
    f = CoreTests.f
    error = CoreTests.error

    def test_recent_real_metadata_bounded(self):
        a = self.f('old.txt')
        b = self.f('new.txt')
        os.utime(a, (100, 100))
        os.utime(b, (200, 200))
        self.f('.secret')
        (self.source / 'loop').symlink_to(self.source, target_is_directory=True)
        r = dispatch('recent', {'roots': [str(self.source)], 'limit': 1})
        self.assertEqual(r['items'][0]['name'], 'new.txt')
        self.assertEqual(r['total'], 2)

    def test_capacity_actual(self):
        r = dispatch('capacity', {'path': str(self.root)})
        self.assertGreater(r['total'], 0)
        self.assertGreaterEqual(r['free'], 0)

    def test_copy_explicit_keep_both(self):
        a = self.f('file.txt')
        (self.dest / 'file.txt').write_text('existing')
        dispatch('copy', {'sources': [str(a)], 'destination': str(self.dest), 'collisionPolicy': 'keep_both'})
        self.assertEqual((self.dest / 'file.txt').read_text(), 'existing')
        self.assertEqual((self.dest / 'file (copy).txt').read_bytes(), b'hello')

    def test_token_json_safe_strings(self):
        t = snapshot(self.f())
        self.assertTrue(all((isinstance(value, str) for value in t)))
        self.assertEqual(json.loads(json.dumps(t)), t)

    def test_move_race_detected_put_back(self):
        p = self.f()
        actual = no_replace
        once = [False]

        def replace(src, dst):
            if not once[0]:
                once[0] = True
                Path(src).write_text('changed in fixture race')
            return actual(src, dst)
        with patch('files_core.no_replace', side_effect=replace):
            self.error('changed', 'move', {'sources': [str(p)], 'destination': str(self.dest)})
        self.assertTrue(p.exists())
        self.assertEqual(p.read_text(), 'changed in fixture race')
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_real_gio_trash_list_restore_no_follow(self):
        p = self.f()
        link = self.source / 'restore link'
        link.symlink_to(p)
        base = self.root / 'data/Trash'
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_DATA_HOME': str(self.root / 'data')}), patch('files_core.trash_roots', return_value=[(str(base), None)]):
            dispatch('trash', {'sources': [str(link)]})
            listed = dispatch('trash-list', {})
            self.assertEqual(listed['total'], 1)
            item = listed['items'][0]
            self.assertEqual(item['originalPath'], str(link))
            self.assertTrue(item['isSymlink'])
            dispatch('restore', {'items': [{'trashId': item['trashId'], 'token': item['token']}]})
            self.assertTrue(link.is_symlink())
            self.assertEqual(p.read_bytes(), b'hello')
            self.assertEqual(dispatch('trash-list', {})['total'], 0)

    def test_restore_collision_keeps_both(self):
        p = self.f('restore me')
        base = self.root / 'data/Trash'
        with patch.dict(os.environ, {'HOME': str(self.root), 'XDG_DATA_HOME': str(self.root / 'data')}), patch('files_core.trash_roots', return_value=[(str(base), None)]):
            dispatch('trash', {'sources': [str(p)]})
            item = dispatch('trash-list', {})['items'][0]
            p.write_text('new existing content')
            self.error('collision', 'restore', {'items': [{'trashId': item['trashId'], 'token': item['token']}]})
            self.assertEqual(p.read_text(), 'new existing content')
            self.assertEqual(dispatch('trash-list', {})['total'], 1)

class ProtocolTests(unittest.TestCase):

    def test_cli_real_json_unicode_and_invalid(self):
        if os.geteuid() == 0:
            self.skipTest('runtime refuses root')
        with tempfile.TemporaryDirectory(prefix='mobile-files-cli-fixture-') as tmp:
            p = Path(tmp)
            (p / 'α file.txt').write_text('fixture')
            cli = Path(__file__).with_name('files_backend.py')
            result = subprocess.run([sys.executable, str(cli)], input=json.dumps({'action': 'list', 'payload': {'path': tmp}}) + '\n', capture_output=True, text=True, check=True)
            answer = json.loads(result.stdout)
            self.assertTrue(answer['ok'])
            self.assertEqual(answer['result']['items'][0]['name'], 'α file.txt')
            self.assertTrue(all((isinstance(x, str) for x in answer['result']['items'][0]['token'])))
            invalid = subprocess.run([sys.executable, str(cli)], input='{not JSON}\n', capture_output=True, text=True)
            self.assertEqual(json.loads(invalid.stdout)['error']['code'], 'invalid_request')
class InvalidRequestTests(unittest.TestCase):
    def test_nonobject_payload(self):
        with self.assertRaises(FileError) as raised:
            dispatch('list', [])
        self.assertEqual(raised.exception.code, 'invalid_request')

    def test_missing_path_selection(self):
        from files_core import selected
        with self.assertRaises(FileError) as raised:
            selected({})
        self.assertEqual(raised.exception.code, 'invalid_request')

    def test_nonlist_sources(self):
        with self.assertRaises(FileError) as raised:
            dispatch('copy', {'sources': 'not a list', 'destination': '/tmp'})
        self.assertEqual(raised.exception.code, 'invalid_request')

    def test_root_runtime_refused_before_io(self):
        with patch('files_core.os.geteuid', return_value=0):
            with self.assertRaises(FileError) as raised:
                dispatch('list', {'path': '/never-read'})
        self.assertEqual(raised.exception.code, 'root_forbidden')

if __name__ == '__main__':
    unittest.main()
