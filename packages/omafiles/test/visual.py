#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
from pathlib import Path
import os,shutil,subprocess,tempfile,argparse,json,stat
HERE=Path(__file__).resolve().parent
PKG=HERE.parent
BACKEND=PKG/'runtime'
parser=argparse.ArgumentParser(description='Actual Files UI with neutral temporary fixtures; no phone or real desktop session.')
parser.add_argument('--theme',choices=('dark','light'),default='dark')
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--record',action='store_true')
parser.add_argument('--fps',type=int,choices=(15,30),default=30)
parser.add_argument('--width',type=int,default=420)
parser.add_argument('--height',type=int,default=935)
parser.add_argument('--capture-only',action='store_true')
args=parser.parse_args()
assert 320<=args.width<=1440 and 320<=args.height<=1440
args.output=args.output.resolve();args.output.mkdir(parents=True,exist_ok=True)
short=Path('/tmp/kfpub10');short.mkdir(mode=0o700,exist_ok=True)
st=short.lstat();assert stat.S_ISDIR(st.st_mode) and not short.is_symlink() and st.st_uid==os.geteuid() and stat.S_IMODE(st.st_mode)==0o700
frames=args.output/'frames'
if args.record:frames.mkdir(exist_ok=False)
palettes={'dark':{'background':'#14171c','foreground':'#e5e9f0','accent':'#8ec5ff','red':'#ff99a5'},'light':{'background':'#f7f5ef','foreground':'#20252d','accent':'#2355a4','red':'#9d253a'}}
palette=palettes[args.theme]

with tempfile.TemporaryDirectory(prefix='files-ui-',dir=short) as directory:
 root=Path(directory);app=root/'app';app.mkdir()
 for name in ('shell.qml','FilesBridge.qml','FilesModel.js','Icon.qml'):shutil.copy(PKG/'ui'/name,app/name)
 for name in ('files_core.py','files_backend.py'):shutil.copy(BACKEND/name,app/name)
 # Confine trash discovery to this fixture's real private GIO trash. All
 # parsing/trashing/restoring code remains actual; no host mount is examined.
 core=(app/'files_core.py').read_text();start=core.index('def trash_roots():');end=core.index('def trash_entries(',start)
 core=core[:start]+"def trash_roots():\n    return [(str(Path(os.environ['XDG_DATA_HOME']) / 'Trash'), None)]\n\n"+core[end:];(app/'files_core.py').write_text(core)
 shutil.copytree(PKG/'ui/fonts',app/'fonts');(app/'Commons').symlink_to('/usr/share/omarchy/shell/Commons',target_is_directory=True)
 home=root/'home';home.mkdir()
 theme=home/'.local/state/omarchy/current/theme';theme.mkdir(parents=True)
 (theme/'colors.toml').write_text('\n'.join(k+' = "'+v+'"' for k,v in palette.items())+'\n')
 (theme/'shell.toml').write_text('[font]\nbase-size = 12\n')
 bindir=root/'bin';bindir.mkdir()
 for name in ('fbcli','xdg-open'):
  stub=bindir/name;stub.write_text('#!/bin/sh\nexit 0\n');stub.chmod(0o700)
 stub=bindir/'hyprctl';stub.write_text('#!/usr/bin/python3\nimport json,sys\nkey=sys.argv[-1]\nvalues={"decoration:rounding":{"int":12},"animations:enabled":{"bool":True},"general:gaps_out":{"custom":"10 10 10 10"}}\nif key not in values:sys.exit(1)\nprint(json.dumps(values[key]))\n');stub.chmod(0o700)
 for name in ('Downloads','Documents','Pictures'):(home/name).mkdir()
 (home/'Downloads/Trip.txt').write_text('trip fixture')
 (home/'Downloads/Notes.txt').write_text('notes fixture')
 (home/'Documents/Notes.txt').write_text('keep this original')
 (home/'Empty').mkdir()
 (home/'Private').mkdir(mode=0)
 (home/'Archive').mkdir()
 for index in range(250):(home/'Archive'/('Entry%03d.txt'%index)).write_text('pagination fixture')
 runtime=root/'run';runtime.mkdir(mode=0o700)
 source=(app/'shell.qml').read_text().replace('implicitWidth:420;implicitHeight:935','implicitWidth:'+str(args.width)+';implicitHeight:'+str(args.height),1);test=r'''
  TestCase {
    name:"NativeFilesActualBackend";when:true
    function initTestCase(){qtest_results.startLogging();tryVerify(function(){return root.page==="home"&&!bridge.loading&&root.locations.available.length===4},4000);tryCompare(face,"status",FontLoader.Ready,2000)}
    function init(){root.modal="";root.selection=({});root.query="";search.text="";search.focus=false}
    function cleanup(){console.log("FILES_CASE",Date.now(),qtest_results.functionName,qtest_results.failed,root.page,root.query,root.items.length,root.message)}
    function findButton(label){var all=[];function walk(item){if(item.objectName==="action-"+label&&item.visible&&item.opacity>0)all.push(item);var children=item.children||[];for(var i=0;i<children.length;i++)walk(children[i])}walk(window.contentItem);for(var j=0;j<all.length;j++){var p=all[j];var visible=true;while(p){if(!p.visible){visible=false;break}p=p.parent}if(visible)return all[j]}return null}
    function button(label){var item=findButton(label);console.log("BUTTON",label,!!item,root.page,root.selectedCount,item?JSON.stringify(item.mapToItem(screen,0,0)):"",item?item.width:0,item?item.height:0);verify(item,"visible button "+label);waitForRendering(item,250);wait(30);var position=item.mapToItem(screen,0,0);verify(position.y>=0&&position.y+item.height<=screen.height,"action inside viewport "+label);mouseClick(item,item.width/2,item.height/2);wait(30);console.log("AFTER_BUTTON",label,root.page,root.modal,root.selectedCount)}
    function browse(path){root.navigate(path);tryVerify(function(){return !bridge.loading&&root.path===path},3000)}
    function row(name){waitForRendering(list,250);wait(30);var found=null;function walk(item){var ok=item.visible;var ancestor=item.parent;while(ancestor){if(!ancestor.visible)ok=false;ancestor=ancestor.parent}if(ok&&item.objectName==="file-"+name)found=item;var children=item.children||[];for(var i=0;i<children.length;i++)walk(children[i])}walk(window.contentItem);verify(found,"visible row "+name);return found}
    function more(name){var item=row(name);mouseClick(item,item.width-26,40);tryCompare(root,"modal","context")}
    function select(name){var item=row(name),finger=touchEvent(window.contentItem);finger.press(0,item,100,40).commit();wait(520);console.log("AFTER_HOLD",name,root.selectedCount,JSON.stringify(root.selection));finger.release(0,item,100,40).commit();tryCompare(root,"selectedCount",1)}
    function chooseDocuments(){tryCompare(root,"page","target");tryVerify(function(){return !bridge.loading},2000);var item=row("Documents");mouseClick(item,100,40);tryVerify(function(){return !bridge.loading&&root.path===root.locations.documents},3000)}
    function test_a_real_browse_and_keyboard_search(){browse(root.locations.downloads);compare(root.items.length,2);mouseClick(search,10,20);keyClick(Qt.Key_N);keyClick(Qt.Key_O);keyClick(Qt.Key_T);keyClick(Qt.Key_E);keyClick(Qt.Key_S);tryCompare(root,"query","notes");tryVerify(function(){return !bridge.loading&&root.items.length===1},3000);compare(root.items[0].name,"Notes.txt");root.query="";search.text="";search.focus=false;root.refresh();tryVerify(function(){return !bridge.loading&&root.items.length===2},3000)}
    function test_b_actual_hold_copy_and_target_picker(){browse(root.locations.downloads);select("Trip.txt");button("Copy");chooseDocuments();button("Copy here");tryVerify(function(){return !bridge.busy&&root.page==="browse"},3000);browse(root.locations.documents);verify(root.items.some(function(item){return item.name==="Trip.txt"}));compare(root.selectedCount,0)}
    function test_c_context_rename_with_actual_keys(){browse(root.locations.documents);more("Trip.txt");screen.grabToImage(function(result){result.saveToFile(CONTEXTSHOT)});wait(100);button("Rename");tryCompare(root,"modal","rename");keyClick(Qt.Key_A,Qt.ControlModifier);keyClick(Qt.Key_R);keyClick(Qt.Key_Period);keyClick(Qt.Key_T);keyClick(Qt.Key_X);keyClick(Qt.Key_T);compare(editor.text,"r.txt");button("Save");tryVerify(function(){return !bridge.busy&&!bridge.loading&&root.items.some(function(item){return item.name==="r.txt"})},3000)}
    function test_d_collision_cancel_then_keep_both(){browse(root.locations.downloads);select("Notes.txt");button("Copy");chooseDocuments();button("Copy here");tryCompare(root,"modal","collision",3000);button("Cancel");compare(root.modal,"");button("Copy here");tryCompare(root,"modal","collision",3000);button("Keep both");tryVerify(function(){return !bridge.busy&&root.page==="browse"},3000);browse(root.locations.documents);verify(root.items.filter(function(item){return item.name.indexOf("Notes")===0}).length===2)}
    function test_e_actual_move(){browse(root.locations.documents);more("r.txt");button("Move");tryCompare(root,"page","target");tryVerify(function(){return !bridge.loading},2000);var folder=row("Downloads");mouseClick(folder,100,40);tryVerify(function(){return !bridge.loading&&root.path===root.locations.downloads},3000);button("Move here");tryVerify(function(){return !bridge.busy&&root.page==="browse"},3000);browse(root.locations.downloads);verify(root.items.some(function(item){return item.name==="r.txt"}))}
    function test_f_private_fixture_trash_restore(){browse(root.locations.downloads);more("r.txt");button("Move to Trash");tryCompare(root,"modal","trashConfirm");button("Move to Trash");tryVerify(function(){return !bridge.busy&&!bridge.loading&&!root.items.some(function(item){return item.name==="r.txt"})},3000);root.tab("trash");tryVerify(function(){return !bridge.loading&&root.items.some(function(item){return item.name==="r.txt"})},3000);var item=row("r.txt");mouseClick(item,100,40);tryCompare(root,"modal","context");button("Restore");tryVerify(function(){return !bridge.busy&&!bridge.loading&&!root.items.some(function(item){return item.name==="r.txt"})},3000);browse(root.locations.downloads);verify(root.items.some(function(item){return item.name==="r.txt"}))}
    function test_g_theme_tokens_and_capture(){root.tab("home");tryVerify(function(){return !bridge.loading},3000);compare(root.family,Commons.Style.font.family);compare(root.danger,Commons.Color.urgent);compare(root.cornerRadius,Commons.Style.cornerRadius);compare(root.bg.toString(),Quickshell.env("OMAFILES_EXPECTED_BG"));compare(screen.width,Number(Quickshell.env("OMAFILES_WIDTH")));compare(screen.height,Number(Quickshell.env("OMAFILES_HEIGHT")));screen.grabToImage(function(result){result.saveToFile(SHOT);root.testCaptureDone=true});tryCompare(root,"testCaptureDone",true,3000);root.testCaptureDone=false;root.context(root.recent[0]);tryCompare(root,"modal","context");waitForRendering(modalScroll,250);verify(modalScroll.height<=screen.height-24);screen.grabToImage(function(result){result.saveToFile(CONTEXTSHOT);root.testCaptureDone=true});tryCompare(root,"testCaptureDone",true,3000);if(screen.height<480){verify(modalScroll.contentHeight>modalScroll.height);modalScroll.contentY=modalScroll.contentHeight-modalScroll.height;wait(50);var last=findButton("Move to Trash");verify(last!==null);var pos=last.mapToItem(screen,0,0);verify(pos.y>=0&&pos.y+last.height<=screen.height)};root.modal=""}
    function test_h_directory_pagination_keeps_previous_rows(){browse(root.home+"/Archive");compare(root.items.length,200);compare(root.more,true);root.refresh(root.items.length);tryVerify(function(){return !bridge.loading&&root.items.length===250},3000);compare(root.more,false);verify(root.items.some(function(item){return item.name==="Entry000.txt"}));verify(root.items.some(function(item){return item.name==="Entry249.txt"}))}
    function test_i_back_hides_own_editor_before_dismissing_without_writes(){browse(root.locations.downloads);more("Trip.txt");button("Rename");tryCompare(root,"modal","rename");verify(editor.activeFocus);root.back();compare(root.modal,"rename");compare(editor.activeFocus,false);root.back();compare(root.modal,"");verify(root.items.some(function(item){return item.name==="Trip.txt"}))}
    function test_j_double_start_guard_and_immediate_cancel(){browse(root.locations.downloads);var item=root.items.filter(function(value){return value.name==="Trip.txt"})[0];verify(bridge.act("copy",{sources:[{path:item.path,token:item.token}],destination:root.locations.pictures}));compare(bridge.busy,true);compare(bridge.act("copy",{sources:[],destination:root.locations.pictures}),false);bridge.cancel();compare(bridge.cancelling,true);tryVerify(function(){return !bridge.busy},3000);compare(root.failureCode,"cancelled")}
    function test_k_empty_and_real_permission_failure_have_no_stale_rows(){browse(root.locations.downloads);verify(root.items.length>0);browse(root.home+"/Empty");compare(root.items.length,0);var empty=findChild(window.contentItem,"filesEmptyState");verify(empty.visible);compare(empty.text,"Nothing here yet.");browse(root.locations.downloads);verify(root.items.length>0);root.navigate(root.home+"/Private");tryVerify(function(){return !bridge.loading&&root.message.length>0},3000);compare(root.items.length,0);compare(root.more,false);verify(empty.visible);compare(empty.text,"This folder is unavailable.")}
    function test_l_palette_file_changes_update_the_standalone_window(){
      themeOutput.setText('background = "#182020"\nforeground = "#efffff"\naccent = "#22aaaa"\nred = "#ff8899"\n')
      tryVerify(function(){return root.bg.toString()==="#182020"&&root.danger.toString()==="#ff8899"},2000)
      compare(window.color,root.bg)
      const original=Commons.Style.fontFamily
      Commons.Style.fontFamily="serif";compare(root.family,"serif");Commons.Style.fontFamily=original
      Commons.Style.applyShellValues({"font.base-size":"14"});compare(search.font.pixelSize,Math.round(15*14/12));Commons.Style.applyShellValues({"font.base-size":"12"})
      Commons.Style.applyRoundingJson('{"int":0}');compare(root.cornerRadius,0)
      Commons.Style.applyRoundingJson('{"int":12}');compare(root.cornerRadius,12)
    }
    function cleanupTestCase(){root.testRecording=false;tryCompare(root,"testCaptureBusy",false,2000);if(Quickshell.env("OMAFILES_RECORD")==="1"){framesOutput.setText(JSON.stringify(root.testFrameTimes));tryCompare(root,"testManifestSaved",true,2000)};console.log("FILES_RESULT",qtest_results.failCount,qtest_results.passCount);qtest_results.stopLogging();Qt.quit()}
  }
  Timer {
    interval:Math.round(1000/Number(Quickshell.env("OMAFILES_FPS")));repeat:true;running:root.testRecording
    onTriggered: {
      if(root.testCaptureBusy||root.testFrame>=600)return
      root.testCaptureBusy=true
      const index=root.testFrame++
      screen.grabToImage(function(result){const file="frame"+String(index).padStart(4,"0")+".png";result.saveToFile(Quickshell.env("OMAFILES_FRAME_DIR")+"/"+file);root.testFrameTimes.push({file:file,ms:Date.now()-root.testStarted});root.testCaptureBusy=false})
    }
  }
  Timer {interval:45000;running:true;onTriggered:Qt.quit()}
'''
 if args.capture_only:
  import re
  for match in reversed(list(re.finditer(r'    function (test_[A-Za-z0-9_]+)\(',test))):
   if match[1].startswith('test_g_'):continue
   start=match.start();opening=test.index('{',match.end());depth=1;end=opening+1
   while depth:
    if test[end]=='{':depth+=1
    elif test[end]=='}':depth-=1
    end+=1
   test=test[:start]+test[end:]
 source=source.replace('import Quickshell.Io','import Quickshell.Io\nimport QtTest',1).replace('  id: root','  id: root\n  property bool testCaptureDone:false\n  property bool testRecording:Quickshell.env("OMAFILES_RECORD")==="1"\n  property bool testCaptureBusy:false\n  property int testFrame:0\n  property double testStarted:Date.now()\n  property var testFrameTimes:[]\n  property bool testManifestSaved:false\n  FileView {id:framesOutput;path:Quickshell.env("OMAFILES_FRAME_DIR")+"/frames.json";onSaved:root.testManifestSaved=true}\n  FileView {id:themeOutput;path:Quickshell.env("OMAFILES_THEME_PATH");atomicWrites:true}',1)
 import json
 test=test.replace('CONTEXTSHOT',json.dumps(str(args.output/'files-context.png'))).replace('SHOT',json.dumps(str(args.output/'files-home.png')))
 source=source.replace('id:screen;anchors.fill:parent;focus:true','id:screen;anchors.fill:parent;focus:true\n'+test,1);(app/'shell.qml').write_text(source)
 env=os.environ|{'HOME':str(home),'XDG_CONFIG_HOME':str(home/'.config'),'XDG_DATA_HOME':str(root/'data'),'XDG_CACHE_HOME':str(root/'cache'),'XDG_RUNTIME_DIR':str(runtime),'QT_QPA_PLATFORM':'offscreen','QT_QPA_PLATFORMTHEME':'','QT_QUICK_CONTROLS_STYLE':'Basic','QT_QUICK_BACKEND':'software','QML_DISABLE_DISK_CACHE':'1','DBUS_SESSION_BUS_ADDRESS':'unix:path=/nonexistent','DBUS_SYSTEM_BUS_ADDRESS':'unix:path=/nonexistent','PATH':str(bindir)+':/usr/bin:/bin','OMAFILES_EXPECTED_BG':palette['background'],'OMAFILES_WIDTH':str(args.width),'OMAFILES_HEIGHT':str(args.height),'OMAFILES_THEME_PATH':str(theme/'colors.toml'),'OMAFILES_RECORD':'1' if args.record else '0','OMAFILES_FRAME_DIR':str(frames),'OMAFILES_FPS':str(args.fps)}
 for name in ('WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE'):env.pop(name,None)
 try:
  result=subprocess.run(['/usr/bin/quickshell','--path',str(app/'shell.qml'),'--no-color'],env=env,capture_output=True,text=True,timeout=52)
 except subprocess.TimeoutExpired as error:
  output=error.stdout or b''
  if isinstance(output,bytes):output=output.decode(errors='replace')
  (args.output/'qml-ui-timeout.log').write_text(output);print(output[-18000:]);raise

 (home/'Private').chmod(0o700)
 output=result.stdout+result.stderr;(args.output/'qml-ui.log').write_text(output);print(output[-14000:])
 expected='FILES_RESULT 0 '+('2' if args.capture_only else '13')
 assert result.returncode==0 and expected in output
 assert not any(value in output for value in ('ReferenceError:','TypeError:','Failed to load configuration'))
 assert (home/'Documents/Notes.txt').read_text()=='keep this original'
 if not args.capture_only:assert (home/'Downloads/r.txt').read_text()=='trip fixture'
 if args.record:assert len(list(frames.glob('frame*.png')))>15,'recording must contain actual UI frames'
 (args.output/'RESULT.json').write_text(json.dumps({'result':'PASS','theme':args.theme,'palette':palette,'functionalCases':1 if args.capture_only else 12,'viewport':[args.width,args.height],'offscreen':True,'phoneCapture':False,'actualBackend':True,'fixtureTrashDiscoveryOnly':True,'frames':len(list(frames.glob('frame*.png'))) if args.record else 0,'requestedCaptureFPS':args.fps if args.record else None},indent=2)+'\n')
 print('PASS real Files UI, temporary filesystem operations and standalone theme reload; offscreen fixtures, not a phone-performance result')
