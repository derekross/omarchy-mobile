#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Offline bridge fixtures: only inert temporary executables, never real agents."""
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import patch

PKG = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('chat', PKG/'lib/agent_chat.py')
chat = importlib.util.module_from_spec(spec); spec.loader.exec_module(chat)
FAKE = '''#!/usr/bin/python3
import json,os,sys,time
if os.environ.get('FIXTURE_NO_READ')=='1':time.sleep(30)
prompt=sys.stdin.read()
with open(os.environ['FIXTURE_LOG'],'a') as f:f.write(json.dumps({'argv':sys.argv[1:],'prompt':prompt,'home':os.environ.get('CODEX_HOME'),'keep':os.environ.get('KEEP_ME'),'cwd':os.getcwd()})+'\\n')
if prompt=='hang':
 time.sleep(30)
if prompt=='fail':
 print(json.dumps({'type':'error','message':'private raw token'}),flush=True);sys.exit(2)
if prompt!='missing-thread':print(json.dumps({'type':'thread.started','thread_id':('different-thread' if prompt=='mismatch' else 'fixture-thread')}),flush=True)
print(json.dumps({'type':'item.completed','item':{'type':'command_execution','aggregated_output':'private tool output'}}),flush=True)
print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':('😀'*23000 if prompt=='huge-unicode' else '界'*10000 if prompt=='bounded-unicode' else 'Reply: '+prompt)}},ensure_ascii=False),flush=True)
print(json.dumps({'type':'turn.completed'}),flush=True)
'''

class Bridge(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        self.bin = self.root/'bin'; self.bin.mkdir()
        self.config = self.root/'.config/omarchy/defaults'; self.config.mkdir(parents=True)
        (self.config/'agent').write_text('codex\n')
        for name, source in [('codex', FAKE), ('omarchy-agent-account-home', '#!/bin/sh\nexit 0\n')]:
            f = self.bin/name; f.write_text(source); f.chmod(0o700)
        self.env = patch.dict(os.environ, {'HOME':str(self.root), 'XDG_STATE_HOME':str(self.root/'state'), 'PATH':str(self.bin), 'CODEX_HOME':str(self.root/'account-one'), 'FIXTURE_LOG':str(self.root/'calls'), 'KEEP_ME':'retained'}, clear=True)
        self.env.start(); self.output = io.StringIO(); self.server = chat.Server(self.output)
    def tearDown(self):
        self.server.close(); self.env.stop(); self.tmp.cleanup()
    def events(self): return [json.loads(x) for x in self.output.getvalue().splitlines()]
    def send(self, request, prompt): self.server.handle(dict(op='send',id=request,provider='codex',prompt=prompt))
    def wait(self):
        end=time.monotonic()+3
        while self.server.active and time.monotonic()<end:time.sleep(.01)
        self.assertIsNone(self.server.active)
    def calls(self): return [json.loads(x) for x in (self.root/'calls').read_text().splitlines()]
    def test_real_argv_stdin_reply_resume_and_environment(self):
        self.send('one','literal $(no-shell)'); self.wait(); self.send('two','followup'); self.wait()
        calls=self.calls(); self.assertEqual(calls[0]['prompt'],'literal $(no-shell)')
        self.assertNotIn('literal $(no-shell)',calls[0]['argv']); self.assertEqual(calls[0]['argv'][:3],['exec','--sandbox','workspace-write'])
        self.assertIn('fixture-thread',calls[1]['argv']); self.assertNotIn('--last',calls[1]['argv'])
        self.assertEqual(calls[0]['keep'],'retained'); self.assertEqual(Path(calls[0]['cwd']).stat().st_mode&0o777,0o700)
        self.assertEqual([e['type'] for e in self.events()],['started','reply','done','started','reply','done'])
        self.assertNotIn('private tool',self.output.getvalue())
    def test_cancel_busy_and_late_event_terminal_once(self):
        self.send('one','hang'); time.sleep(.1); self.send('two','other'); self.server.handle(dict(op='cancel',id='wrong'))
        self.assertIsNotNone(self.server.active); self.server.handle(dict(op='cancel',id='one')); self.wait()
        self.assertEqual([e['type'] for e in self.events() if e.get('id')=='one'],['started','cancelled'])
        self.assertTrue(any(e.get('code')=='busy' for e in self.events()))
    def test_stop_preserves_last_completed_conversation(self):
        self.send('one','completed'); self.wait()
        self.send('two','hang'); time.sleep(.1); self.server.cancel('two'); self.wait()
        self.assertEqual(self.server.thread,'fixture-thread')
        self.send('three','continue'); self.wait()
        self.assertIn('resume',self.calls()[2]['argv'])
        self.assertIn('fixture-thread',self.calls()[2]['argv'])
    def test_explicit_reset_discards_completed_conversation(self):
        self.send('one','completed'); self.wait(); self.server.handle(dict(op='reset'))
        self.send('two','new'); self.wait()
        self.assertNotIn('resume',self.calls()[1]['argv'])
    def test_failed_followup_preserves_completed_context(self):
        self.send('one','completed'); self.wait()
        self.send('two','fail'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'agent_failed')
        self.assertEqual(self.server.thread,'fixture-thread')
        self.send('three','continue'); self.wait()
        self.assertIn('resume',self.calls()[2]['argv'])
        self.assertIn('fixture-thread',self.calls()[2]['argv'])
    def test_resumed_thread_mismatch_never_replaces_owned_session(self):
        self.send('one','completed'); self.wait()
        self.send('two','mismatch'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'session_mismatch')
        self.assertEqual(self.server.thread,'fixture-thread')
        self.assertFalse(any(e['type']=='reply' and e.get('id')=='two' for e in self.events()))
    def test_missing_initial_thread_rejects_false_continuity(self):
        self.send('one','missing-thread'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'session_unavailable')
        self.assertFalse(any(e['type']=='reply' for e in self.events()))
        self.assertIsNone(self.server.thread)
    def test_completed_reaped_cli_receives_no_cleanup_signal(self):
        with patch.object(chat.os,'killpg',wraps=os.killpg) as kill:
            self.send('one','completed'); self.wait()
            self.assertEqual(self.events()[-1]['type'],'done')
            kill.assert_not_called()
    def test_reset_after_cancel_ack(self):
        self.send('one','hang'); time.sleep(.1); self.server.handle(dict(op='reset')); self.wait()
        self.assertEqual(self.events()[-2]['type'],'cancelled'); self.assertEqual(self.events()[-1]['type'],'reset')
    def test_account_change_never_resumes_previous_thread(self):
        self.send('one','a'); self.wait(); os.environ['CODEX_HOME']=str(self.root/'account-two'); self.send('two','b'); self.wait()
        self.assertNotIn('resume',self.calls()[1]['argv']); self.assertTrue(any(e['type']=='reset' and e.get('reason')=='account_changed' for e in self.events()))
    def test_capabilities_unsupported_and_errors_are_constant(self):
        self.server.capabilities(); self.assertTrue(self.events()[-1]['nativeChat'])
        (self.config/'agent').write_text('other'); self.server.capabilities(); self.assertFalse(self.events()[-1]['nativeChat'])
        self.send('one','x'); self.assertEqual(self.events()[-1]['code'],'provider_changed')
        (self.config/'agent').write_text('codex'); self.send('two','fail'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'agent_failed'); self.assertNotIn('private raw token',self.output.getvalue())
    def test_bounds_duplicate_and_no_prompt_in_error(self):
        self.send('one','x'*32769); self.assertEqual(self.events()[-1]['code'],'invalid_prompt')
        self.send('two','a'); self.wait(); self.send('two','b'); self.assertEqual(self.events()[-1]['code'],'request_id_used')
    def test_timeout_terminates_owned_process(self):
        with patch.object(chat,'DEADLINE',.1): self.send('one','hang'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'timeout')
    def test_cancellation_while_agent_does_not_read_large_stdin(self):
        os.environ['FIXTURE_NO_READ']='1'
        self.send('one','x'*32768); time.sleep(.1); self.server.cancel('one'); self.wait()
        self.assertEqual(self.events()[-1]['type'],'cancelled')
    def test_wrappers_cannot_trigger_auto_install(self):
        (self.bin/'codex').write_text('#!/bin/sh\nmise install codex\n')
        self.assertFalse(chat.qualified(self.bin/'codex'))
        (self.bin/'codex').write_text('#!/bin/sh\nexec omarchy-agent-account-exec codex "$@"\n')
        self.assertFalse(chat.qualified(self.bin/'codex'))
    def test_selected_provider_first_line_and_bounded_read(self):
        (self.config/'agent').write_text('codex\nclaude\n')
        self.assertEqual(chat.selected_provider(),'codex')
        (self.config/'agent').write_text('x'*129+'\ncodex')
        self.assertEqual(chat.selected_provider(),'')
    def test_safe_structured_failure_classification(self):
        for text, code in [('401 authentication token PRIVATE','auth_required'),('sandbox bwrap PRIVATE','sandbox_failed'),('approval required PRIVATE','approval_required'),('PRIVATE','agent_failed')]:
            kind, value=chat.Codex.event(dict(type='turn.failed',error={'message':text}))
            self.assertEqual((kind,value),('failure',code))
    def test_state_rejects_symlink_parent(self):
        target=self.root/'target'; target.mkdir()
        link=self.root/'link'; link.symlink_to(target,target_is_directory=True)
        with self.assertRaises(OSError): chat.private_state(link/'child')
        self.assertFalse((target/'child').exists())
    def test_close_does_not_delete_workspace_with_live_worker(self):
        class Stuck:
            def join(self,timeout): pass
            def is_alive(self): return True
        self.server.active=dict(id='one',cancel=__import__('threading').Event(),worker=Stuck())
        workspace=self.server.workspace
        self.server.close(); self.assertTrue(workspace.exists())
        self.server.active=None
    def test_close_preserves_client_created_artifacts(self):
        workspace=self.server.workspace
        artifact=workspace/'answer.txt'; artifact.write_text('created task result')
        self.server.close()
        self.assertEqual(artifact.read_text(),'created task result')
    def test_close_removes_only_empty_owned_workspace(self):
        workspace=self.server.workspace
        self.server.close(); self.assertFalse(workspace.exists())
    def test_reply_wire_expansion_is_rejected_without_partial_text(self):
        self.send('one','huge-unicode'); self.wait()
        self.assertEqual([e['type'] for e in self.events()],['started','error'])
        self.assertEqual(self.events()[-1]['code'],'output_limit')
    def test_bounded_unicode_reply_is_preserved_without_truncation(self):
        self.send('one','bounded-unicode'); self.wait()
        self.assertEqual(self.events()[-2]['text'],'界'*10000)
        self.assertEqual(self.events()[-1]['type'],'done')
    def test_output_limit(self):
        with patch.object(chat,'MAX_OUTPUT',16): self.send('one','a'); self.wait()
        self.assertEqual(self.events()[-1]['code'],'output_limit')

if __name__=='__main__': unittest.main()
