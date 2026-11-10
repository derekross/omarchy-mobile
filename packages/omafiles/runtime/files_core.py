# SPDX-License-Identifier: MIT
"""Unprivileged local filesystem operations. No Qt needed; never runs a shell."""
from __future__ import annotations
import ctypes, errno, hashlib, mimetypes, os, shutil, stat, subprocess, tempfile, threading, time
from pathlib import Path

class FileError(Exception):

    def __init__(self, code, message, **details):
        super().__init__(message)
        self.code = code
        self.details = details

    def json(self):
        return {'code': self.code, 'message': str(self), 'details': self.details}

def path(value):
    if not isinstance(value, str) or not value or '\x00' in value:
        raise FileError('invalid_path', 'Invalid path.')
    return os.path.abspath(os.path.expanduser(value))

def token(st):
    return [str(value) for value in (st.st_dev, st.st_ino, st.st_mode, st.st_size, st.st_mtime_ns)]

def snapshot(p):
    try:
        return token(os.lstat(p))
    except FileNotFoundError:
        raise FileError('not_found', 'The file no longer exists.', path=p)

def selected(value):
    if isinstance(value, dict) and 'path' not in value:
        raise FileError('invalid_request', 'A selected item is missing its path.')
    p = path(value['path'] if isinstance(value, dict) else value)
    current = snapshot(p)
    if isinstance(value, dict) and value.get('token') is not None and (value['token'] != current):
        raise FileError('changed', 'The file has changed. Refresh the view first.', path=p)
    return (p, current)

def cancelled(event):
    if event and event.is_set():
        raise FileError('cancelled', 'Operation cancelled.')

def convert_error(e):
    if isinstance(e, FileError):
        return e
    if isinstance(e, OSError):
        code = {errno.EACCES: 'permission_denied', errno.EPERM: 'permission_denied', errno.ENOSPC: 'no_space', errno.EDQUOT: 'no_space', errno.EEXIST: 'collision', errno.ENOENT: 'not_found', errno.ENAMETOOLONG: 'invalid_name', errno.EXDEV: 'cross_device'}.get(e.errno, 'io_error')
        message = {'permission_denied': 'Permission denied.', 'no_space': 'There is not enough space at the destination.', 'collision': 'An item with this name already exists at the destination.', 'not_found': 'The path no longer exists.', 'invalid_name': 'This name is too long.', 'cross_device': 'Moving to another filesystem is not supported yet. Copy the item instead.'}.get(code, 'The operation could not be completed.')
        return FileError(code, message, errno=e.errno)
    return FileError('internal_error', 'The operation could not be completed.')

def entry(p, name=None):
    st = os.lstat(p)
    link = stat.S_ISLNK(st.st_mode)
    directory = stat.S_ISDIR(st.st_mode)
    target_directory = os.path.isdir(p) if link else directory
    mime = 'inode/directory' if target_directory else mimetypes.guess_type(p)[0] or 'application/octet-stream'
    return {'path': p, 'name': name if name is not None else os.path.basename(p), 'kind': 'symlink' if link else 'directory' if directory else 'file' if stat.S_ISREG(st.st_mode) else 'other', 'isDirectory': directory, 'targetIsDirectory': target_directory, 'isSymlink': link, 'linkTarget': os.readlink(p) if link else None, 'size': st.st_size, 'mtime': st.st_mtime, 'mime': mime, 'token': token(st), 'readable': os.access(p, os.R_OK), 'writable': os.access(p, os.W_OK), 'thumbnailEligible': not link and stat.S_ISREG(st.st_mode) and (mime in ('image/png', 'image/jpeg', 'image/webp', 'image/gif', 'image/bmp', 'image/x-ms-bmp'))}

def browse(payload, event=None, progress=None):
    folder = path(payload.get('path', '~'))
    hidden = bool(payload.get('hidden', False))
    query = str(payload.get('query', '')).casefold()
    recursive = bool(payload.get('recursive', False)) and bool(query)
    sort = str(payload.get('sort', 'name'))
    descending = bool(payload.get('descending', False))
    limit = max(1, min(1000, int(payload.get('limit', 200))))
    offset = max(0, int(payload.get('offset', 0)))
    items = []
    errors = 0
    visited = 0

    def walk(directory):
        nonlocal errors, visited
        cancelled(event)
        with os.scandir(directory) as listing:
            for child in listing:
                cancelled(event)
                visited += 1
                if visited > 100000:
                    raise FileError('search_limit', 'This search is too large. Choose a smaller folder.')
                if not hidden and child.name.startswith('.'):
                    continue
                try:
                    row = entry(os.path.join(directory, child.name), child.name)
                except OSError:
                    errors += 1
                    continue
                if (not payload.get('imagesOnly') or row['isDirectory'] or row['targetIsDirectory'] or (row['kind'] == 'file' and Path(row['name']).suffix.lower() in IMAGE_SUFFIXES)) and (not query or query in child.name.casefold()):
                    items.append(row)
                if recursive and row['isDirectory']:
                    try:
                        walk(row['path'])
                    except PermissionError:
                        errors += 1
    walk(folder)
    keys = {'name': lambda x: x['name'].casefold(), 'size': lambda x: x['size'], 'modified': lambda x: x['mtime'], 'type': lambda x: (x['mime'], x['name'].casefold())}
    if sort not in keys:
        raise FileError('invalid_sort', 'Unknown sort order.')
    items.sort(key=keys[sort], reverse=descending)
    items.sort(key=lambda x: not x['isDirectory'])
    return {'path': folder, 'realPath': os.path.realpath(folder), 'parent': os.path.dirname(folder), 'items': items[offset:offset + limit], 'total': len(items), 'offset': offset, 'hasMore': offset + limit < len(items), 'skipped': errors, 'writable': os.access(folder, os.W_OK), 'sort': sort, 'descending': descending, 'hidden': hidden}

class Progress:

    def __init__(self, callback, event):
        self.callback = callback
        self.event = event
        self.done = 0
        self.total = 0
        self.last = 0
        self.items = 0

    def report(self, name='', phase='copy', force=False):
        cancelled(self.event)
        now = time.monotonic()
        if self.callback and (force or now - self.last >= 0.1):
            self.callback({'phase': phase, 'name': name, 'bytesDone': self.done, 'bytesTotal': self.total, 'itemsDone': self.items})
            self.last = now

def no_replace(source, destination):
    """Linux atomic RENAME_NOREPLACE: never replace a raced-in file/empty folder."""
    libc = ctypes.CDLL(None, use_errno=True)
    fn = getattr(libc, 'renameat2', None)
    if fn is None:
        raise FileError('unsupported', 'Atomic no-overwrite moves are not supported on this system.')
    fn.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
    fn.restype = ctypes.c_int
    if fn(-100, os.fsencode(source), -100, os.fsencode(destination), 1):
        number = ctypes.get_errno()
        raise OSError(number, os.strerror(number))

def inventory(source, event=None):
    records = {}
    total = 0

    def visit(p):
        nonlocal total
        cancelled(event)
        st = os.lstat(p)
        records[p] = token(st)
        if len(records) > 100000:
            raise FileError('operation_limit', 'This folder contains too many entries for one operation.')
        if stat.S_ISREG(st.st_mode):
            total += st.st_size
        elif stat.S_ISDIR(st.st_mode):
            fd = os.open(p, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
            try:
                with os.scandir(fd) as it:
                    names = [e.name for e in it]
                for name in names:
                    visit(os.path.join(p, name))
            finally:
                os.close(fd)
    visit(source)
    return (records, total)

def verify(records):
    for p, expected in records.items():
        if snapshot(p) != expected:
            raise FileError('changed', 'The source folder changed during the operation.', path=p)

def copy_tree(source, destination, records, progress):
    cancelled(progress.event)
    expected = records[source]
    mode = int(expected[2])
    if stat.S_ISLNK(mode):
        value = os.readlink(source)
        if snapshot(source) != expected:
            raise FileError('changed', 'The link has changed.', path=source)
        os.symlink(value, destination)
        return
    if stat.S_ISDIR(mode):
        os.mkdir(destination, 448)
        fd = os.open(source, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            if token(os.fstat(fd)) != expected:
                raise FileError('changed', 'The source folder has changed.', path=source)
            with os.scandir(fd) as it:
                names = [e.name for e in it]
            for name in names:
                child = os.path.join(source, name)
                if child not in records:
                    raise FileError('changed', 'The source folder has changed.', path=child)
                copy_tree(child, os.path.join(destination, name), records, progress)
        finally:
            os.close(fd)
        os.chmod(destination, mode & 511)
        os.utime(destination, ns=(int(expected[4]), int(expected[4])), follow_symlinks=False)
        return
    if not stat.S_ISREG(mode):
        raise FileError('unsupported_type', 'This file type cannot be copied.', path=source)
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        if token(os.fstat(fd)) != expected:
            raise FileError('changed', 'The file has changed.', path=source)
        with os.fdopen(fd, 'rb', closefd=False) as reader, open(destination, 'xb') as writer:
            while True:
                cancelled(progress.event)
                chunk = reader.read(1024 * 1024)
                if not chunk:
                    break
                writer.write(chunk)
                progress.done += len(chunk)
                progress.report(os.path.basename(source))
            writer.flush()
            os.fsync(writer.fileno())
        if token(os.fstat(fd)) != expected:
            raise FileError('changed', 'The file changed while it was being copied.', path=source)
    finally:
        os.close(fd)
    os.chmod(destination, mode & 511)
    os.utime(destination, ns=(int(expected[4]), int(expected[4])), follow_symlinks=False)

def move_checked(source, target, expected):
    """No replacement; put a raced-in source back instead of claiming success."""
    no_replace(source, target)
    if snapshot(target) != expected:
        try:
            no_replace(target, source)
        except OSError:
            raise FileError('changed', 'The file changed. Check the source and destination.', source=source, destination=target)
        raise FileError('changed', 'The file changed and was put back.', path=source)

def transfer(payload, move=False, event=None, callback=None):
    sources = payload.get('sources', [])
    if not isinstance(sources, list):
        raise FileError('invalid_request', 'The selected files must be a list.')
    if not sources:
        raise FileError('empty_selection', 'Select files first.')
    destination = os.path.realpath(path(payload.get('destination', '')))
    if not os.path.isdir(destination):
        raise FileError('not_directory', 'The destination folder is unavailable.')
    plans = []
    seen = set()
    collisions = []
    for value in sources:
        source, expected = selected(value)
        target = os.path.join(destination, os.path.basename(source))
        if target in seen and payload.get('collisionPolicy') != 'keep_both':
            raise FileError('duplicate_target', 'Selected files would have the same destination name.')
        if stat.S_ISDIR(int(expected[2])) and os.path.commonpath([os.path.realpath(source), destination]) == os.path.realpath(source):
            raise FileError('recursive_destination', 'A folder cannot be copied into itself.')
        if (os.path.lexists(target) or target in seen) and payload.get('collisionPolicy') == 'keep_both':
            base = os.path.basename(source)
            stem, extension = os.path.splitext(base)
            if stat.S_ISDIR(int(expected[2])):
                stem, extension = (base, '')
            index = 1
            while os.path.lexists(target) or target in seen:
                label = ' (copy)' if index == 1 else ' (copy ' + str(index) + ')'
                target = os.path.join(destination, stem + label + extension)
                index += 1
        if os.path.lexists(target):
            collisions.append({'source': source, 'destination': target})
        seen.add(target)
        plans.append((source, target, expected))
    if collisions:
        raise FileError('collision', 'Items with these names already exist.', collisions=collisions)
    completed = []
    progress = Progress(callback, event)
    try:
        for source, target, expected in plans:
            cancelled(event)
            if snapshot(source) != expected:
                raise FileError('changed', 'The selection has changed.', path=source)
            if move:
                move_checked(source, target, expected)
            else:
                progress.report(os.path.basename(source), 'scan', True)
                records, size = inventory(source, event)
                progress.total += size
                if records[source] != expected:
                    raise FileError('changed', 'The selection has changed.', path=source)
                staging = tempfile.mkdtemp(prefix='.mobile-files-copy-', dir=destination)
                temporary = os.path.join(staging, 'item')
                try:
                    copy_tree(source, temporary, records, progress)
                    verify(records)
                    cancelled(event)
                    no_replace(temporary, target)
                finally:
                    shutil.rmtree(staging)
            completed.append({'source': source, 'destination': target})
            progress.items += 1
            progress.report(os.path.basename(source), force=True)
    except Exception as e:
        failure = convert_error(e)
        failure.details['completed'] = completed
        raise failure
    return {'completed': completed, 'cancelled': False}

def valid_name(name):
    if not isinstance(name, str) or name in ('', '.', '..') or '/' in name or ('\x00' in name):
        raise FileError('invalid_name', 'Enter a valid name.')
    return name

def trash(payload, event=None, callback=None, gio='gio'):
    completed = []
    sources = payload.get('sources', [])
    if not isinstance(sources, list):
        raise FileError('invalid_request', 'The selected files must be a list.')
    if not sources:
        raise FileError('empty_selection', 'Select files first.')
    plans = [selected(value) for value in sources]
    for source, expected in plans:
        cancelled(event)
        try:
            current = snapshot(source)
        except FileError as e:
            e.details['completed'] = completed
            raise
        if current != expected:
            raise FileError('changed', 'The selection has changed.', completed=completed, path=source)
        with subprocess.Popen([gio, 'trash', '--', source], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True) as child:
            deadline = time.monotonic() + 60
            while child.poll() is None:
                if event and event.is_set() or time.monotonic() > deadline:
                    child.terminate()
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
                    raise FileError('cancelled' if event and event.is_set() else 'timeout', 'The trash operation was interrupted.', completed=completed, path=source, sourceStillExists=os.path.lexists(source))
                time.sleep(0.04)
            error = child.stderr.read()
            if child.returncode:
                raise FileError('trash_failed', 'The item could not be moved to the trash.', completed=completed, path=source)
        if os.path.lexists(source):
            raise FileError('trash_failed', 'The item is still at its original location.', completed=completed, path=source)
        completed.append({'source': source, 'trashed': True})
        if callback:
            callback({'phase': 'trash', 'itemsDone': len(completed), 'itemsTotal': len(payload['sources'])})
    return {'completed': completed, 'reversible': True}

def thumbnail(payload, event=None):
    """Decode only immutable bounded local raster data, never SVG or device nodes."""
    source, expected = selected(payload.get('path', ''))
    if not stat.S_ISREG(int(expected[2])):
        raise FileError('unsupported_thumbnail', 'No preview is available for this file type.')
    if int(expected[3]) > 32 * 1024 ** 2:
        raise FileError('unsupported_thumbnail', 'This image is too large for a thumbnail.')
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        if token(os.fstat(stream.fileno())) != expected:
            raise FileError('changed', 'The image has changed.')
        data = stream.read(32 * 1024 ** 2 + 1)
        if len(data) > 32 * 1024 ** 2 or token(os.fstat(stream.fileno())) != expected:
            raise FileError('changed', 'The image has changed.')
    magic = data[:16]
    format_name = None
    for signature, name in [(b'\x89PNG\r\n\x1a\n', b'png'), (b'\xff\xd8\xff', b'jpeg'), (b'GIF87a', b'gif'), (b'GIF89a', b'gif'), (b'BM', b'bmp')]:
        if magic.startswith(signature):
            format_name = name
            break
    if magic.startswith(b'RIFF') and magic[8:12] == b'WEBP':
        format_name = b'webp'
    if not format_name:
        raise FileError('unsupported_thumbnail', 'Only local raster images receive thumbnails.')
    try:
        from PySide6.QtCore import QSize, Qt, QBuffer, QByteArray, QIODevice
        from PySide6.QtGui import QImageReader
    except ImportError:
        raise FileError('thumbnail_unavailable', 'Image thumbnails are unavailable on this system.')
    buffer = QBuffer()
    buffer.setData(QByteArray(data))
    buffer.open(QIODevice.ReadOnly)
    cancelled(event)
    reader = QImageReader(buffer, QByteArray(format_name))
    reader.setAutoDetectImageFormat(False)
    size = reader.size()
    if size.width() <= 0 or size.height() <= 0 or size.width() * size.height() > 32000000:
        raise FileError('unsupported_thumbnail', 'This image is too large or damaged.')
    edge = max(32, min(512, int(payload.get('size', 160))))
    reader.setScaledSize(size.scaled(QSize(edge, edge), Qt.KeepAspectRatio))
    image = reader.read()
    if image.isNull():
        raise FileError('unsupported_thumbnail', 'This image could not be read.')
    if snapshot(source) != expected:
        raise FileError('changed', 'The image has changed.')
    cancelled(event)
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache'))) / 'omamobile/files/thumbnails'
    cache.mkdir(parents=True, exist_ok=True, mode=448)
    key = hashlib.sha256((source + repr(expected) + str(edge)).encode()).hexdigest()
    target = cache / (key + '.png')
    fd, temp = tempfile.mkstemp(prefix='.thumb-', dir=cache)
    os.close(fd)
    try:
        if not image.save(temp, 'PNG'):
            raise FileError('thumbnail_failed', 'The thumbnail could not be saved.')
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    return {'path': str(target), 'source': source, 'token': expected}

def locations():
    home = str(Path.home())
    result = {'home': home, 'documents': home + '/Documents', 'downloads': home + '/Downloads', 'pictures': home + '/Pictures'}
    config = Path(os.environ.get('XDG_CONFIG_HOME', home + '/.config')) / 'user-dirs.dirs'
    import re
    try:
        for line in config.read_text().splitlines():
            match = re.fullmatch('XDG_(DOCUMENTS|DOWNLOAD|PICTURES)_DIR="([^"\\n]*)"', line.strip())
            if match:
                key = {'DOCUMENTS': 'documents', 'DOWNLOAD': 'downloads', 'PICTURES': 'pictures'}[match[1]]
                value = match[2].replace('$HOME', home)
                if value.startswith('/') and '\x00' not in value:
                    result[key] = value
    except OSError:
        pass
    return {**result, 'available': [key for key, value in result.items() if os.path.isdir(value)]}

def recent(payload, event=None):
    roots = payload.get('roots') or [value for key, value in locations().items() if key in ('documents', 'downloads', 'pictures')]
    if not isinstance(roots, list):
        raise FileError('invalid_request', 'Invalid recent-folder list.')
    items = []
    seen = set()
    visited = 0
    skipped = 0
    truncated = False

    def visit(folder, depth=0):
        nonlocal visited, skipped, truncated
        cancelled(event)
        if depth > 32 or visited >= 20000:
            truncated = True
            return
        try:
            with os.scandir(folder) as iterator:
                children = list(iterator)
        except OSError:
            skipped += 1
            return
        for child in children:
            cancelled(event)
            visited += 1
            if visited >= 20000:
                truncated = True
                return
            if child.name.startswith('.'):
                continue
            try:
                row = entry(os.path.join(folder, child.name))
            except OSError:
                skipped += 1
                continue
            if row['isSymlink']:
                continue
            if row['isDirectory']:
                visit(row['path'], depth + 1)
            elif row['kind'] == 'file' and row['path'] not in seen:
                seen.add(row['path'])
                items.append(row)
    for folder in roots:
        folder = path(folder)
        if os.path.isdir(folder) and (not os.path.islink(folder)):
            visit(folder)
    items.sort(key=lambda row: row['mtime'], reverse=True)
    limit = max(1, min(500, int(payload.get('limit', 100))))
    return {'items': items[:limit], 'total': len(items), 'truncated': truncated, 'skipped': skipped}

def trash_roots():
    """FDO home trash plus user-owned per-mount trash; never recurse mounts."""
    uid = os.geteuid()
    home = Path.home()
    base = Path(os.environ.get('XDG_DATA_HOME', str(home / '.local/share'))) / 'Trash'
    roots = [(str(base), None)]
    try:
        mounts = Path('/proc/self/mounts').read_text().splitlines()
        for line in mounts:
            fields = line.split()
            if len(fields) < 3 or fields[2] in ('proc', 'sysfs', 'devtmpfs', 'tmpfs', 'cgroup', 'cgroup2', 'securityfs', 'debugfs', 'tracefs', 'overlay', 'squashfs'):
                continue
            mount = fields[1].replace('\\040', ' ').replace('\\011', '\t').replace('\\134', '\\')
            for candidate in [Path(mount) / ('.Trash-' + str(uid)), Path(mount) / '.Trash' / str(uid)]:
                try:
                    st = candidate.lstat()
                    if stat.S_ISDIR(st.st_mode) and st.st_uid == uid and (not candidate.is_symlink()):
                        roots.append((str(candidate), mount))
                except OSError:
                    pass
    except OSError:
        pass
    unique = {}
    for root, mount in roots:
        unique.setdefault(os.path.realpath(root), (root, mount))
    return list(unique.values())

def trash_entries(event=None):
    import configparser, urllib.parse
    rows = []
    for root, mount in trash_roots():
        info_folder = Path(root) / 'info'
        files = Path(root) / 'files'
        try:
            infos = list(info_folder.iterdir())
        except OSError:
            continue
        for info in infos:
            cancelled(event)
            if not info.name.endswith('.trashinfo') or info.is_symlink():
                continue
            try:
                info_stat = info.lstat()
            except OSError:
                continue
            if not stat.S_ISREG(info_stat.st_mode) or info_stat.st_size > 65536:
                continue
            stored = files / info.name[:-10]
            try:
                parser = configparser.ConfigParser(interpolation=None)
                parser.read_string(info.read_text())
                if snapshot(str(info)) != token(info_stat):
                    continue
                original = os.fsdecode(urllib.parse.unquote_to_bytes(parser['Trash Info']['Path']))
                if not os.path.isabs(original):
                    if mount is None:
                        continue
                    original = os.path.normpath(os.path.join(mount, original))
                    if os.path.commonpath([mount, original]) != mount:
                        continue
                original = path(original)
                row = entry(str(stored), os.path.basename(original))
                info_token = snapshot(str(info))
                row.update(trashId=hashlib.sha256((root + '\x00' + info.name).encode(errors='surrogateescape')).hexdigest(), originalPath=original, deletedAt=parser['Trash Info'].get('DeletionDate', ''), token={'file': row['token'], 'info': info_token}, infoPath=str(info))
                rows.append(row)
            except (OSError, FileError, KeyError, ValueError, configparser.Error):
                continue
    return rows

def trash_list(payload, event=None):
    rows = trash_entries(event)
    rows.sort(key=lambda row: row['deletedAt'], reverse=True)
    limit = max(1, min(1000, int(payload.get('limit', 200))))
    offset = max(0, int(payload.get('offset', 0)))
    return {'items': [{k: v for k, v in row.items() if k != 'infoPath'} for row in rows[offset:offset + limit]], 'total': len(rows), 'hasMore': offset + limit < len(rows)}

def restore(payload, event=None, callback=None):
    chosen = payload.get('items', [])
    if not isinstance(chosen, list) or not chosen:
        raise FileError('empty_selection', 'Select files to restore first.')
    available = {row['trashId']: row for row in trash_entries(event)}
    plans = []
    collisions = []
    targets = set()
    for item in chosen:
        if not isinstance(item, dict) or item.get('trashId') not in available:
            raise FileError('not_found', 'This item is no longer in the trash.')
        row = available[item['trashId']]
        if item.get('token') is not None and item['token'] != row['token']:
            raise FileError('changed', 'This trash item has changed. Refresh the view.')
        destination = os.path.join(path(payload['destination']), row['name']) if payload.get('destination') else row['originalPath']
        if destination in targets:
            raise FileError('duplicate_target', 'Selected items would have the same destination name.')
        targets.add(destination)
        if os.path.lexists(destination):
            collisions.append({'source': row['path'], 'destination': destination})
        if not os.path.isdir(os.path.dirname(destination)):
            raise FileError('missing_parent', 'The original folder is missing. Choose another folder.', originalPath=row['originalPath'])
        plans.append((row, destination))
    if collisions:
        raise FileError('collision', 'An item with this name already exists.', collisions=collisions)
    completed = []
    warnings = []
    try:
        for row, destination in plans:
            cancelled(event)
            if snapshot(row['path']) != row['token']['file'] or snapshot(row['infoPath']) != row['token']['info']:
                raise FileError('changed', 'The trash item has changed.')
            move_checked(row['path'], destination, row['token']['file'])
            completed.append({'source': row['path'], 'destination': destination, 'restored': True})
            try:
                os.unlink(row['infoPath'])
            except OSError:
                warnings.append('The restored item is safe, but its old trash metadata could not be removed.')
            if callback:
                callback({'phase': 'restore', 'itemsDone': len(completed), 'itemsTotal': len(plans)})
    except Exception as e:
        failure = convert_error(e)
        failure.details['completed'] = completed
        raise failure
    return {'completed': completed, 'warnings': warnings}

IMAGE_SUFFIXES = frozenset(('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'))


def pick_image(payload, event=None):
    """Read-only local raster selection; preview decode remains caller's gate."""
    source, expected = selected(payload.get('source', ''))
    if not stat.S_ISREG(int(expected[2])) or Path(source).suffix.lower() not in IMAGE_SUFFIXES:
        raise FileError('unsupported_image', 'Choose a supported local raster image.')
    cancelled(event)
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        if token(os.fstat(fd)) != expected:
            raise FileError('changed', 'The selected image has changed.')
        magic = os.read(fd, 32)
        if token(os.fstat(fd)) != expected:
            raise FileError('changed', 'The selected image has changed.')
    finally:
        os.close(fd)
    suffix = Path(source).suffix.lower()
    valid = (suffix == '.png' and magic.startswith(b'\x89PNG\r\n\x1a\n') and len(magic) >= 24 or
             suffix in ('.jpg', '.jpeg') and magic.startswith(b'\xff\xd8\xff') or
             suffix == '.gif' and magic[:6] in (b'GIF87a', b'GIF89a') and len(magic) >= 10 or
             suffix == '.bmp' and magic.startswith(b'BM') and len(magic) >= 26 or
             suffix == '.webp' and magic.startswith(b'RIFF') and magic[8:12] == b'WEBP' and len(magic) >= 20)
    if not valid:
        raise FileError('unsupported_image', 'The file does not have a supported image header.')
    if snapshot(source) != expected:
        raise FileError('changed', 'The selected image has changed.')
    return {'path': source, 'token': expected}


def dispatch(action, payload, event=None, progress=None):
    try:
        if os.geteuid() == 0:
            raise FileError('root_forbidden', 'Run Files as a normal user.')
        if not isinstance(payload, dict):
            raise FileError('invalid_request', 'Invalid request.')
        if action == 'pick-image':
            return pick_image(payload, event)
        if action == 'locations':
            return locations()
        if action == 'recent':
            return recent(payload, event)
        if action == 'capacity':
            location = path(payload.get('path', '~'))
            usage = shutil.disk_usage(location)
            return {'path': location, 'total': usage.total, 'free': usage.free, 'used': usage.used}
        if action == 'trash-list':
            return trash_list(payload, event)
        if action == 'restore':
            return restore(payload, event, progress)
        if action in ('list', 'search'):
            return browse(payload, event, progress)
        if action in ('copy', 'move'):
            return transfer(payload, action == 'move', event, progress)
        if action == 'trash':
            return trash(payload, event, progress)
        if action == 'thumbnail':
            return thumbnail(payload, event)
        if action == 'mkdir':
            folder = path(payload.get('path', ''))
            target = os.path.join(folder, valid_name(payload.get('name')))
            os.mkdir(target)
            return {'created': entry(target)}
        if action == 'rename':
            source, expected = selected(payload.get('source', ''))
            target = os.path.join(os.path.dirname(source), valid_name(payload.get('name')))
            move_checked(source, target, expected)
            return {'renamed': entry(target), 'source': source}
        if action == 'open':
            source = path(payload.get('path', ''))
            os.lstat(source)
            if os.path.isdir(source):
                return {'navigate': source}
            if not os.path.isfile(source):
                raise FileError('unsupported_type', 'This file type cannot be opened.')
            cancelled(event)
            result = subprocess.run(['xdg-open', source], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, text=True, timeout=20)
            if result.returncode:
                raise FileError('open_failed', 'No suitable application could open this file.')
            return {'opened': source}
        raise FileError('unknown_action', 'Unknown file action.')
    except Exception as e:
        raise convert_error(e) from e
