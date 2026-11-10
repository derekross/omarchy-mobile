# SPDX-License-Identifier: MIT
"""Optional PySide6 QObject glue; core+CLI do not require Qt."""
from concurrent.futures import ThreadPoolExecutor
import threading, uuid, os, time
from PySide6.QtCore import QObject, Signal, Slot
from files_core import dispatch, convert_error

class FilesBackend(QObject):
    result = Signal(str, str, object)
    progress = Signal(str, object)
    failure = Signal(str, str, object)

    def __init__(self, parent=None):
        if os.geteuid() == 0:
            raise RuntimeError('Run Files as a normal user.')
        super().__init__(parent)
        self.pool = ThreadPoolExecutor(max_workers=2, thread_name_prefix='mobile-files')
        self.jobs = {}
        self.lock = threading.Lock()

    @Slot(str, 'QVariantMap', result=str)
    def request(self, action, payload):
        identifier = uuid.uuid4().hex
        cancel = threading.Event()
        with self.lock:
            self.jobs[identifier] = cancel

        def worker():
            last = [0.0]

            def notify(data):
                now = time.monotonic()
                if now - last[0] >= 0.1:
                    self.progress.emit(identifier, data)
                    last[0] = now
            try:
                self.result.emit(identifier, action, dispatch(action, payload, cancel, notify))
            except Exception as error:
                self.failure.emit(identifier, action, convert_error(error).json())
            finally:
                with self.lock:
                    self.jobs.pop(identifier, None)
        self.pool.submit(worker)
        return identifier

    @Slot(str)
    def cancel(self, identifier):
        with self.lock:
            event = self.jobs.get(identifier)
        if event:
            event.set()

    @Slot()
    def shutdown(self):
        with self.lock:
            for event in self.jobs.values():
                event.set()
        self.pool.shutdown(wait=False, cancel_futures=True)
