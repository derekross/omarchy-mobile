#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Actual picker/backend functions; private fixture files, no real GUI or opener."""
from pathlib import Path
from unittest.mock import patch
import base64,json,os,runpy,subprocess,sys,tempfile,unittest
PKG=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(PKG/'runtime'))
import files_core as core
wrapper=runpy.run_path(str(PKG/'bin/omamobile-files'),run_name='picker_fixture')
PNG=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jg7sAAAAASUVORK5CYII=')

class Picker(unittest.TestCase):
 def test_real_backend_selection_unicode_and_stale(self):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp)/'Winding road Straße # %.PNG';p.write_bytes(PNG)
   selected={'path':str(p),'token':core.snapshot(str(p))}
   request=json.dumps({'action':'pick-image','payload':{'source':selected}},ensure_ascii=True)+'\n'
   result=subprocess.run([sys.executable,str(PKG/'runtime/files_backend.py')],input=request,text=True,capture_output=True,check=True)
   self.assertEqual(json.loads(result.stdout)['result']['path'],str(p))
   self.assertEqual(wrapper['validate_pick']({'ok':True,**core.dispatch('pick-image',{'source':selected})},PKG/'runtime'),{'ok':True,'path':str(p)})
   p.write_bytes(PNG+b'changed')
   with self.assertRaises(core.FileError) as error:core.dispatch('pick-image',{'source':selected})
   self.assertEqual(error.exception.code,'changed')
 def test_filter_and_unsupported_symlink_header(self):
  with tempfile.TemporaryDirectory() as tmp:
   folder=Path(tmp);(folder/'folder').mkdir();(folder/'photo.jpg').write_bytes(b'not jpeg');(folder/'text.txt').write_text('text');(folder/'vector.svg').write_text('<svg/>');(folder/'valid.png').write_bytes(PNG);(folder/'link.png').symlink_to(folder/'valid.png')
   rows=core.dispatch('list',{'path':tmp,'imagesOnly':True})['items']
   self.assertEqual({r['name'] for r in rows},{'folder','photo.jpg','valid.png'})
   for name in ('photo.jpg','text.txt','vector.svg','link.png','folder'):
    with self.assertRaises(core.FileError):core.dispatch('pick-image',{'source':str(folder/name)})
 def picker_fixture(self,result=None,cancel_signal=False):
  with tempfile.TemporaryDirectory() as tmp:
   p=Path(tmp);runtime=p/'runtime';runtime.mkdir(mode=0o700);app=p/'app';app.mkdir()
   (app/'shell.qml').write_bytes((PKG/'ui/shell.qml').read_bytes())
   for name in ('FilesBridge.qml','FilesModel.js','Icon.qml'):(app/name).write_bytes((PKG/'ui'/name).read_bytes())
   for name in ('files_backend.py','files_core.py','qt_backend.py'):(app/name).write_bytes((PKG/'runtime'/name).read_bytes())
   (app/'fonts').mkdir();commons=p/'packaged-Commons';commons.mkdir();(commons/'qmldir').write_text('module qs.Commons\n');(app/'Commons').symlink_to(commons,target_is_directory=True);image=p/'Straße % #.png';image.write_bytes(PNG)
   expected=result if result is not None else {'ok':True,'path':str(image),'token':core.snapshot(str(image))}
   child_state={'terminated':False};commands=[];handlers={}
   class Child:
    def poll(self):return 0 if child_state['terminated'] else None
    def terminate(self):child_state['terminated']=True
    def wait(self,**kwargs):return 0
    def kill(self):raise AssertionError('clean owned child should not require kill')
   def launch(command,**kwargs):
    self.assertEqual(command[:3],['quickshell','--no-duplicate','--path'])
    config=Path(command[3]);self.assertEqual(config.parent.parent,runtime)
    self.assertEqual(config.parent.stat().st_mode&0o777,0o700)
    namespace=config.parent/'Commons'
    self.assertTrue(namespace.is_symlink());self.assertEqual(namespace.readlink(),app/'Commons')
    self.assertEqual((namespace/'qmldir').read_text(),'module qs.Commons\n')
    source=config.read_text();self.assertIn('org.omamobile.Files.Picker.',source)
    self.assertNotEqual(config,app/'shell.qml');self.assertEqual((app/'shell.qml').read_bytes(),(PKG/'ui/shell.qml').read_bytes())
    child_state['config']=config;child_state['nonce']=kwargs['env']['OMAMOBILE_FILES_PICKER_NONCE']
    self.assertEqual(kwargs['umask'],0o077)
    output=config.parent/'picker-result.json';self.assertEqual(output.stat().st_mode&0o777,0o600)
    output.write_text(json.dumps({'nonce':child_state['nonce'],'result':expected}))
    if cancel_signal:handlers[wrapper['signal'].SIGTERM](15,None)
    return Child()
   def ipc(command,**kwargs):
    raise AssertionError('Picker result polling must not spawn any process')
   def handler(signum,callback):handlers[signum]=callback;return wrapper['signal'].SIG_DFL
   with patch.dict(os.environ,{'XDG_RUNTIME_DIR':str(runtime)}),patch.object(wrapper['subprocess'],'Popen',side_effect=launch),patch.object(wrapper['subprocess'],'run',side_effect=ipc),patch.object(wrapper['signal'],'signal',side_effect=handler):
    outcome=wrapper['pick_image'](app,str(p),timeout_seconds=1)
   self.assertTrue(child_state['terminated']);self.assertFalse(list(runtime.iterdir()))
   return outcome,commands
 def test_owned_instance_selection_and_cleanup(self):
  result,commands=self.picker_fixture();self.assertTrue(result['ok']);self.assertIn('Straße % #.png',result['path']);self.assertEqual(len(commands),0)
 def test_cancel_and_owned_sigterm_do_not_select_or_touch_user_files(self):
  result,commands=self.picker_fixture({'ok':False,'cancelled':True});self.assertEqual(result,{'ok':False,'cancelled':True})
  result,commands=self.picker_fixture(cancel_signal=True);self.assertEqual(result,{'ok':False,'cancelled':True});self.assertFalse(commands)
 def test_bad_result_and_insecure_runtime_refused(self):
  for result in ({'ok':True,'path':'/not-selected'},{'pending':False},{'ok':False,'cancelled':False}):
   with self.assertRaises(ValueError):wrapper['validate_pick'](result,PKG/'runtime')
  with tempfile.TemporaryDirectory() as tmp:
   os.chmod(tmp,0o755)
   with patch.dict(os.environ,{'XDG_RUNTIME_DIR':tmp}),patch.object(wrapper['subprocess'],'Popen') as launch:
    with self.assertRaises(RuntimeError):wrapper['pick_image'](PKG/'ui',tmp)
    launch.assert_not_called()

if __name__=='__main__':unittest.main()
