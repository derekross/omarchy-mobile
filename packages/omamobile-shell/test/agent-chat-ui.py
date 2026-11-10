#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Real QML controller -> real Python server -> inert CLI; no account/client calls."""
from pathlib import Path
import json, os, shutil, subprocess, tempfile

PKG = Path(__file__).resolve().parent.parent
FAKE = '''#!/usr/bin/python3
import json,os,sys,time
prompt=sys.stdin.read()
with open(os.environ['FIXTURE_CALLS'],'a') as stream: stream.write(json.dumps({'argv':sys.argv[1:],'prompt':prompt,'home':os.environ.get('CODEX_HOME')})+'\\n')
if prompt=='wait until cancelled': time.sleep(30)
if prompt=='fail after prior turn':
 print(json.dumps({'type':'turn.failed','error':{'message':'401 authentication PRIVATE_FIXTURE_DIAGNOSTIC'}}),flush=True);sys.exit(1)
print(json.dumps({'type':'thread.started','thread_id':'fixture-thread'}),flush=True)
print(json.dumps({'type':'item.completed','item':{'type':'agent_message','text':'Reply: '+prompt}}),flush=True)
print(json.dumps({'type':'turn.completed'}),flush=True)
'''
QML = '''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
ShellRoot {
  AgentChatController { id: chat; provider: "codex"; enabled: true }
  SignalSpy { id: accepted; target: chat; signalName: "accepted" }
  FileView { id: account; path: Quickshell.env("FIXTURE_ACCOUNT_FILE"); atomicWrites: true }
  FileView { id: selection; path: Quickshell.env("FIXTURE_PROVIDER_FILE"); atomicWrites: true }
  TestCase {
    name: "AgentControllerRealTransport"
    when: true
    function initTestCase() { qtest_results.startLogging(); wait(100); console.log("TRANSPORT_INITIAL",chat.capabilityKnown,chat.available,chat.resetPending,chat.error); tryCompare(chat,"capabilityKnown",true,4000); verify(chat.available) }
    function test_real_transport_reply_resume_account_reset_and_cancellation() {
      verify(chat.send("first editable request")); tryCompare(chat,"busy",false,4000)
      compare(accepted.count,1); compare(chat.messages[1].text,"Reply: first editable request")
      verify(chat.send("second request")); tryCompare(chat,"busy",false,4000)
      compare(accepted.count,2); compare(chat.messages[3].text,"Reply: second request")
      verify(chat.send("fail after prior turn"));tryCompare(chat,"busy",false,4000)
      compare(accepted.count,3)
      verify(chat.error.indexOf("Sign in")>=0)
      verify(chat.error.indexOf("PRIVATE_FIXTURE_DIAGNOSTIC")<0)
      compare(chat.messages[1].text,"Reply: first editable request")
      compare(chat.messages[3].text,"Reply: second request")
      verify(chat.send("continue after structured failure"));tryCompare(chat,"busy",false,4000)
      compare(chat.messages[7].text,"Reply: continue after structured failure")
      compare(chat.messages[1].text,"Reply: first editable request")
      account.setText("account-two"); wait(100)
      verify(chat.send("changed account request")); tryCompare(chat,"busy",false,4000)
      compare(chat.messages.length,2); compare(chat.messages[1].text,"Reply: changed account request")
      var beforeCancel=accepted.count
      verify(chat.send("wait until cancelled")); tryCompare(accepted,"count",beforeCancel+1,3000)
      var oldId=chat.activeId
      chat.reset(); verify(chat.resetPending); verify(!chat.send("must not race reset"))
      tryCompare(chat,"resetPending",false,4000); tryCompare(chat,"available",true,3000)
      compare(chat.messages.length,0)
      chat.receive({type:"reply",id:oldId,text:"stale reply"}); compare(chat.messages.length,0)
      verify(chat.send("after reset")); tryCompare(chat,"busy",false,4000)
      compare(chat.messages[1].text,"Reply: after reset")
      chat.process.signal(15)
      tryCompare(chat,"processWanted",false,4000);verify(!chat.busy)
      chat.reset() // explicit New chat restarts local serve, never model work
      verify(chat.resetPending)
      tryCompare(chat,"resetPending",false,4000);tryCompare(chat,"available",true,3000)
      verify(chat.send("after local service restart"));tryCompare(chat,"busy",false,4000)
      compare(chat.messages[1].text,"Reply: after local service restart")
      selection.setText("claude\\n"); wait(100); chat.provider="claude"
      tryCompare(chat,"resetPending",false,4000); tryCompare(chat,"capabilityKnown",true,3000)
      verify(!chat.available); verify(!chat.send("unsupported provider"))
    }
    function cleanupTestCase() {
      console.log("AGENT_TRANSPORT_RESULT",qtest_results.failCount,qtest_results.passCount)
      chat.enabled=false
      qtest_results.stopLogging(); Qt.quit()
    }
  }
  Timer { interval:25000; running:true; onTriggered:Qt.quit() }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='omamobile-agent-ui-') as directory:
        root=Path(directory); home=root/'home'; home.mkdir(); bindir=root/'bin'; bindir.mkdir(); app=root/'app'; app.mkdir()
        config=home/'.config/omarchy/defaults'; config.mkdir(parents=True); provider=config/'agent'; provider.write_text('codex\n')
        account=root/'account'; account.write_text('account-one')
        runtime=root/'run'; runtime.mkdir(mode=0o700)
        shutil.copy(PKG/'plugins/omamobile.launcher/AgentChatController.qml', app/'AgentChatController.qml')
        (app/'shell.qml').write_text(QML)
        scripts={'codex':FAKE,'claude':'#!/bin/sh\nexit 0\n',
                 'omarchy-agent-account-home':'#!/usr/bin/python3\nimport os\nfrom pathlib import Path\nprint(Path(os.environ["FIXTURE_ACCOUNT_FILE"]).read_text().strip())\n',
                 'omamobile-agent-chat':'#!/usr/bin/python3\nimport sys\nsys.path.insert(0,'+repr(str(PKG/'lib'))+')\nfrom agent_chat import main\nraise SystemExit(main())\n'}
        for name, source in scripts.items():
            p=bindir/name; p.write_text(source); p.chmod(0o700)
        env={'HOME':str(home),'PATH':str(bindir)+':/usr/bin:/bin','XDG_STATE_HOME':str(root/'state'),'XDG_RUNTIME_DIR':str(runtime),
             'QT_QPA_PLATFORM':'offscreen','QT_QUICK_BACKEND':'software','QML_DISABLE_DISK_CACHE':'1','QT_QUICK_CONTROLS_STYLE':'Basic',
             'DBUS_SESSION_BUS_ADDRESS':'unix:path=/nonexistent','DBUS_SYSTEM_BUS_ADDRESS':'unix:path=/nonexistent',
             'FIXTURE_CALLS':str(root/'calls'),'FIXTURE_ACCOUNT_FILE':str(account),'FIXTURE_PROVIDER_FILE':str(provider)}
        result=subprocess.run(['/usr/bin/quickshell','--path',str(app/'shell.qml'),'--no-color'],env=env,capture_output=True,text=True,timeout=30)
        output=result.stdout+result.stderr; print(output)
        assert result.returncode==0 and 'AGENT_TRANSPORT_RESULT 0 2' in output
        assert not any(x in output for x in ('ReferenceError:','TypeError:','Failed to load configuration'))
        calls=[json.loads(line) for line in (root/'calls').read_text().splitlines()]
        expected=['first editable request','second request','fail after prior turn','continue after structured failure','changed account request','wait until cancelled','after reset','after local service restart']
        assert [call['prompt'] for call in calls]==expected, calls
        by_prompt={call['prompt']:call for call in calls}
        first=by_prompt['first editable request']
        assert first['argv'][:3]==['exec','--sandbox','workspace-write']
        assert 'resume' not in first['argv']
        for prompt in ('second request','fail after prior turn','continue after structured failure'):
            argv=by_prompt[prompt]['argv']
            assert argv[3:5]==['resume','fixture-thread'], (prompt,argv)
        changed=by_prompt['changed account request']
        assert 'resume' not in changed['argv'] and changed['home']=='account-two'
        assert 'resume' not in by_prompt['after reset']['argv']
        assert 'resume' not in by_prompt['after local service restart']['argv']
        assert all('--last' not in value['argv'] for value in calls)
        print('PASS actual QML/Python/fake-CLI transport, accepted send, exact resume after structured failure, account/provider reset and cancellation')

if __name__=='__main__': main()
