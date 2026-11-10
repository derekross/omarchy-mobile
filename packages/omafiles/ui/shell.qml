//@ pragma AppId org.omamobile.Files
// SPDX-License-Identifier: MIT
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "file:///usr/share/omarchy/shell/Commons" as Commons
import "FilesModel.js" as Model
ShellRoot {
  id: root
  readonly property string pickerNonce: Quickshell.env("OMAMOBILE_FILES_PICKER_NONCE")
  readonly property bool pickerMode: pickerNonce.length>0
  property var pickerResult: ({pending:true})
  function finishPicker(result) {if(!pickerMode||!pickerResult.pending)return;pickerResult=result;pickerOutput.setText(JSON.stringify({nonce:pickerNonce,result:result}))}
  FileView {
    id:pickerOutput
    path:root.pickerMode?decodeURIComponent(String(Qt.resolvedUrl("picker-result.json")).replace("file://","")):""
    atomicWrites:true
    printErrors:false
    onSaved:if(root.pickerMode&&!root.pickerResult.pending)window.visible=false
    onSaveFailed:{root.pickerResult=({pending:true});root.message="The selection could not be returned. Try again or Cancel."}
  }
  // Standalone applications do not receive the main shell's theme IPC.
  // Watch the same theme files and update the shared palette/style objects.
  FileView {
    path: Commons.Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: Commons.Color.loadColors(text())
    onFileChanged: reload()
  }
  FileView {
    path: Commons.Color.currentThemePath + "/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: Commons.Color.loadShell(text())
    onLoadFailed: Commons.Color.loadShell("")
    onFileChanged: reload()
  }
  readonly property color bg: Commons.Color.background
  readonly property color fg: Commons.Color.foreground
  readonly property color accent: Commons.Color.accent
  readonly property color muted: Qt.tint(bg,Qt.rgba(fg.r,fg.g,fg.b,0.68))
  readonly property color surface: Qt.tint(bg,Qt.rgba(fg.r,fg.g,fg.b,0.04))
  readonly property color deep: Qt.tint(bg,Qt.rgba(0,0,0,0.2))
  readonly property color line: Qt.tint(bg,Qt.rgba(fg.r,fg.g,fg.b,0.23))
  readonly property color danger: Commons.Color.urgent
  readonly property string family: Commons.Style.font.family || (face.status===FontLoader.Ready?face.name:"monospace")
  readonly property string mono: Commons.Style.font.family
  readonly property real cornerRadius: Math.max(0, Commons.Style.cornerRadius)
  function fontSize(px) { return Math.max(1, Math.round(px * Commons.Style.fontScale)) }
  readonly property string home: Quickshell.env("HOME")
  FontLoader {id:face;source:Qt.resolvedUrl("fonts/Geist.ttf")}
  property string page: "home"
  property string path: home
  property var locations: ({home:home,downloads:home+"/Downloads",pictures:home+"/Pictures",documents:home+"/Documents",available:[]})
  property var capacity: ({})
  property string parentPath: ""
  property var items: []
  property var recent: []
  property int total: 0
  property bool more: false
  property bool hidden: false
  property string sorting: "name"
  property bool descending: false
  property string query: ""
  property string pendingLocation: ""
  function flushLocation(){if(pendingLocation&&!bridge.busy&&!targeting&&!modal){var value=pendingLocation;pendingLocation="";navigate(value)}}
  onModalChanged: Qt.callLater(flushLocation)
  onPageChanged: Qt.callLater(flushLocation)
  property var selection: ({})
  readonly property int selectedCount: Object.keys(selection).length
  property var contextItem: null
  property string modal: ""
  property string message: ""
  property string failureCode: ""
  property var failureDetails: ({})
  property var planned: ({action:"",sources:[]})
  property string returnPage: "browse"
  property string returnPath: home
  property string editText: ""
  readonly property bool targeting: page==="target"
  readonly property string title: selectedCount>0?selectedCount+" selected":targeting?"Where to?":page==="home"?"Files":page==="recent"?"Recent":page==="trash"?"Trash":Model.title(path,home)
  function refresh(offset) {
    message="";failureCode=""
    if(page==="home") bridge.query("locations",{})
    else if(page==="recent") bridge.query("recent",{limit:200})
    else if(page==="trash") bridge.query("trash-list",{limit:200,offset:offset||0})
    else bridge.query("list",{path:path,hidden:hidden,query:query,recursive:query.length>0,sort:sorting,descending:descending,offset:offset||0,limit:200,imagesOnly:pickerMode})
  }
  function dismissKeyboard(){search.focus=false;editor.focus=false;Qt.inputMethod.hide()}
  function navigate(folder) {dismissKeyboard();items=[];total=0;more=false;parentPath="";path=folder;page=targeting?"target":"browse";query="";search.text="";selection=({});refresh()}
  function tab(which) {if(bridge.busy)return;dismissKeyboard();page=which;if(which==="home")path=locations.home;selection=({});query="";search.text="";modal="";refresh()}
  function openItem(item) {
    if(bridge.busy)return
    if(pickerMode){if(item.isDirectory||item.targetIsDirectory)navigate(item.path);else bridge.act("pick-image",{source:{path:item.path,token:item.token}});return}
    if(selectedCount>0){selection=Model.toggle(selection,item);return}
    if(page==="trash"){context(item);return}
    if(item.isDirectory||item.targetIsDirectory){navigate(item.path);return}
    if(!targeting)bridge.act("open",{path:item.path})
  }
  function feedback(event) { Quickshell.execDetached(["sh","-c","command -v fbcli >/dev/null 2>&1 && exec fbcli -E button-pressed"]) }
  // Only accepted semantic transitions tick; never pointer motion or list scroll.
  function holdItem(item) {if(bridge.busy||targeting||pickerMode)return;selection=Model.toggle(selection,item);feedback("long-press")}
  function context(item) {if(bridge.busy||targeting||pickerMode)return;if(modal==="context"&&contextItem&&contextItem.path===item.path)return;contextItem=item;modal="context";feedback("context-open")}
  function sources() {return selectedCount>0?Model.sources(selection):contextItem?[{path:contextItem.path,token:contextItem.token}]:[]}
  function target(action) {
    dismissKeyboard()
    planned={action:action,sources:sources(),trashItems:page==="trash"?(selectedCount>0?Object.keys(selection).map(function(key){return selection[key]}):[contextItem]):[]}
    returnPage=page;returnPath=path;page="target";path=locations.home;selection=({});query="";search.text="";modal="";refresh()
  }
  function commitTarget(keepBoth) {
    var payload=planned.action==="restore"?{items:planned.trashItems.map(function(item){return {trashId:item.trashId,token:item.token}}),destination:path}:{sources:planned.sources,destination:path}
    if(keepBoth)payload.collisionPolicy="keep_both"
    modal="";bridge.act(planned.action,payload)
  }
  function trashSelected() {planned={action:"trash",sources:sources()};modal="trashConfirm"}
  function restoreSelected() {
    var chosen=selectedCount>0?Object.keys(selection).map(function(key){return selection[key]}):[contextItem]
    planned={action:"restore",trashItems:chosen};modal="";bridge.act("restore",{items:chosen.map(function(item){return {trashId:item.trashId,token:item.token}})})
  }
  function back() {
    if(bridge.busy)return
    if((editor.visible&&editor.activeFocus)||(search.visible&&search.activeFocus)){dismissKeyboard();return}
    if(modal){modal="";return}
    if(selectedCount){selection=({});return}
    if(targeting){if(path!==locations.home&&parentPath){navigate(parentPath);return}page=returnPage;path=returnPath;refresh();return}
    if(page==="browse"&&path!==home&&parentPath){navigate(parentPath);return}
    if(pickerMode){finishPicker({ok:false,cancelled:true});return}
    if(page!=="home"){tab("home");return}
    if(pickerMode){finishPicker({ok:false,cancelled:true});return}
    window.visible=false
  }
  IpcHandler {
    target:"files"
    function state():string{return JSON.stringify({pid:Quickshell.processId,appId:Quickshell.appId})}
    function activate(location:string):string {
      window.visible=true
      if(location){root.pendingLocation=location;Qt.callLater(root.flushLocation)}
      focusProcess.running=true
      return "ok"
    }
  }
  IpcHandler {
    target:"picker"
    function result(nonce:string):string {return nonce===root.pickerNonce&&root.pickerMode?JSON.stringify(root.pickerResult):JSON.stringify({ok:false,error:"invalid_request"})}
    function cancel(nonce:string):string {if(nonce!==root.pickerNonce||!root.pickerMode)return "refused";root.finishPicker({ok:false,cancelled:true});return "ok"}
  }
  Process {id:focusProcess;command:["hyprctl","dispatch",'hl.dsp.focus({ window = "class:^('+Quickshell.appId.replace(/[^A-Za-z0-9_.-]/g,"").replace(/[.]/g,"[.]")+')$" })']}
  FilesBridge {
    id:bridge
    onBusyChanged: Qt.callLater(root.flushLocation)
    onAnswer:function(action,result,request){
      if(action==="locations"){root.locations=result;if(root.page==="home")bridge.query("capacity",{path:root.home})}
      else if(action==="capacity"){root.capacity=result;if(root.page==="home")bridge.query("recent",{limit:2})}
      else if(action==="recent"){if(root.page==="home")root.recent=result.items;else{root.items=result.items;root.total=result.total;root.more=false}}
      else if(action==="list"||action==="trash-list"){
        root.items=request&&request.payload.offset>0?root.items.concat(result.items):result.items;root.total=result.total;root.more=!!result.hasMore
        if(action==="list"){root.path=result.path;root.parentPath=result.parent}
        root.selection=Model.prune(root.selection,root.items)
      }
    }
    onCompleted:function(action,result){
      if(action==="pick-image"){root.finishPicker({ok:true,path:result.path,token:result.token});return}
      if(action==="open"){if(result.navigate)root.navigate(result.navigate);return}
      root.modal="";root.selection=({});root.contextItem=null
      if(root.targeting){root.page=root.returnPage;root.path=root.returnPath}
      root.refresh();root.message=action==="trash"?"Moved to Trash.":action==="restore"?"Files restored.":"Done."
    }
    onFailure:function(action,code,message,details){
      root.failureCode=code;root.failureDetails=details;root.message=message
      if(action==="list"||action==="trash-list"||(action==="recent"&&root.page!=="home")){root.items=[];root.total=0;root.more=false;root.selection=({})}
      if(action==="recent"&&root.page==="home")root.recent=[]
      if(details.completed&&details.completed.length){root.message+=" "+details.completed.length+" item(s) completed before stopping.";if(action==="copy"||action==="move"){var done=details.completed.map(function(item){return item.source});root.planned.sources=root.planned.sources.filter(function(item){return done.indexOf(item.path)<0})}}
      if(code==="collision"&&(action==="copy"||action==="move"))root.modal="collision"
      else if(code==="missing_parent"&&action==="restore")root.modal="restoreTarget"
    }
  }
  Component.onCompleted: {
    if(pickerMode){var initial=Quickshell.env("OMAMOBILE_FILES_PICKER_INITIAL");if(initial){navigate(initial);return}}
    refresh()
  }
  Timer {id:searchDelay;interval:250;onTriggered:{if(root.page==="home"){root.page="browse";root.path=root.home}root.refresh()}}
  component Label: Text {textFormat:Text.PlainText;color:root.fg;font.family:root.family;font.pixelSize:root.fontSize(16);elide:Text.ElideRight}
  component Button: Rectangle {
    id:button
    objectName: "action-"+label
    property string label:""
    property string icon:""
    property bool primary:false
    property bool destructive:false
    property bool quiet:false
    property bool alignLeft:false
    signal tapped()
    height:52;radius:Math.min(root.cornerRadius,height/2);color:quiet?(buttonTouch.pressed?root.surface:"transparent"):primary?(destructive?root.danger:root.accent):root.surface
    border.width:quiet?0:1;border.color:primary?color:root.line;opacity:enabled?1:0.45
    Row {x:button.alignLeft?0:(parent.width-width)/2;anchors.verticalCenter:parent.verticalCenter;spacing:button.alignLeft?16:10
      Icon {visible:button.icon!=="";name:button.icon;ink:button.primary?root.bg:button.destructive?root.danger:root.fg;width:24;height:24}
      Label {visible:text!=="";text:button.label;height:Math.max(24,implicitHeight);verticalAlignment:Text.AlignVCenter;color:button.primary?root.bg:button.destructive?root.danger:root.fg;font.weight:Font.DemiBold}
    }
    Rectangle {visible:button.alignLeft;anchors.bottom:parent.bottom;width:parent.width;height:1;color:root.line}
    MouseArea {id:buttonTouch;anchors.fill:parent;onClicked:button.tapped()}
  }
  component FileRow: Item {
    id:row
    objectName: "file-"+entry.name
    Accessible.role: Accessible.ListItem
    Accessible.name: entry.name
    required property var entry
    property bool chosen:root.selection[entry.path]!==undefined
    signal tapped()
    signal held()
    height:80
    Rectangle {x:0;y:18;width:44;height:44;radius:Math.min(root.cornerRadius,height/2);color:root.surface
      Icon {anchors.centerIn:parent;name:Model.icon(row.entry);ink:row.entry.isDirectory?root.accent:root.fg;width:24;height:24}
    }
    Column {x:60;anchors.verticalCenter:parent.verticalCenter;width:parent.width-100;spacing:5
      Label {width:parent.width;text:row.entry.name;font.weight:Font.Medium}
      Label {width:parent.width;text:row.entry.isDirectory?"Folder":Model.bytes(row.entry.size)+(row.entry.deletedAt?" · Deleted "+row.entry.deletedAt.slice(0,10):"");color:root.muted;font.family:root.mono;font.pixelSize:root.fontSize(12)}
    }
    Rectangle {anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:24;height:24;radius:Math.min(root.cornerRadius,height/2);color:row.chosen?root.accent:"transparent"
      Icon {anchors.centerIn:parent;width:24;height:24;name:row.chosen?"check":row.entry.isDirectory||row.entry.targetIsDirectory?"chevron":"more";ink:row.chosen?root.bg:root.muted}
    }
    Rectangle {anchors.bottom:parent.bottom;width:parent.width;height:1;color:root.line}
    MouseArea {anchors.fill:parent;enabled:!bridge.busy&&!bridge.loading;pressAndHoldInterval:450;property bool consumed:false
      onPressed:consumed=false
      onPressAndHold:{consumed=true;row.held()}
      onClicked:if(!consumed)row.tapped()
    }
    MouseArea {anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:52;height:64;enabled:!root.pickerMode&&!root.targeting&&!root.selectedCount&&!bridge.busy&&!bridge.loading;onClicked:{if(row.entry.isDirectory||row.entry.targetIsDirectory)row.tapped();else root.context(row.entry)}}
  }
  FloatingWindow {
    id:window;onVisibleChanged:if(root.pickerMode&&!visible&&root.pickerResult.pending)root.finishPicker({ok:false,cancelled:true});title:root.pickerMode?"Choose image":"Files";visible:true;color:root.bg;implicitWidth:420;implicitHeight:935;minimumSize:Qt.size(320,320)
    Item {
      id:screen;anchors.fill:parent;focus:true
      Rectangle {anchors.fill:parent;color:root.bg}
      Shortcut {sequence:"Escape";context:Qt.WindowShortcut;onActivated:root.back()}
      Shortcut {sequence:"Back";context:Qt.WindowShortcut;onActivated:root.back()}
      Item {
        id:header;anchors{left:parent.left;right:parent.right;top:parent.top}
height:84
        Button {id:backButton;x:12;y:16;width:52;icon:root.selectedCount?"close":"back";quiet:true;visible:root.page!=="home"||root.selectedCount>0;onTapped:root.back()}
        Label {anchors{left:parent.left;leftMargin:backButton.visible?72:24;right:menuButton.left;verticalCenter:parent.verticalCenter}
text:root.title;font.pixelSize:root.fontSize(28);font.weight:Font.DemiBold}
        Button {id:menuButton;anchors.right:parent.right;anchors.rightMargin:12;y:16;width:52;icon:"more";quiet:true;visible:!root.pickerMode;enabled:!bridge.busy;onTapped:root.modal="options"}
      }
      Item {
        id:searchBox;anchors{left:parent.left;leftMargin:24;right:parent.right;rightMargin:24;top:header.bottom}
height:root.page==="trash"||root.selectedCount>0?0:52;visible:height>0
        Rectangle {anchors.fill:parent;radius:Math.min(root.cornerRadius,height/2);color:root.surface;border.width:1;border.color:search.activeFocus?root.accent:root.line}
        Icon {x:16;anchors.verticalCenter:parent.verticalCenter;name:"search";ink:root.muted;width:24;height:24}
        TextInput {id:search;objectName:"filesSearch";x:52;width:parent.width-68;height:parent.height;verticalAlignment:TextInput.AlignVCenter;color:root.fg;font.family:root.family;font.pixelSize:root.fontSize(15);selectByMouse:true;clip:true;inputMethodHints:Qt.ImhNoAutoUppercase;Accessible.name:"Search files"
          onTextEdited:{root.query=text;searchDelay.restart()}
          Text {anchors.fill:parent;verticalAlignment:Text.AlignVCenter;text:root.page==="home"?"Search files":"Search this folder";visible:search.text.length===0;color:root.muted;font.family:root.family;font.pixelSize:root.fontSize(15);textFormat:Text.PlainText}
        }
      }
      Flickable {
        id:overview;visible:root.page==="home";anchors{left:parent.left;right:parent.right;top:searchBox.bottom;bottom:bottomBar.top}
contentWidth:width;contentHeight:homeColumn.height+24;clip:true
        Column {id:homeColumn;x:24;y:16;width:parent.width-48;spacing:16
          Label {text:"ON THIS PHONE";color:root.muted;font.pixelSize:root.fontSize(12);font.weight:Font.DemiBold}
          Grid {columns:2;spacing:12;width:parent.width
            Repeater {model:[{key:"downloads",title:"Downloads",icon:"download"},{key:"pictures",title:"Pictures",icon:"image"},{key:"documents",title:"Documents",icon:"file"},{key:"home",title:"All files",icon:"folder"}]
              Rectangle {required property var modelData;width:(homeColumn.width-12)/2;height:120;radius:Math.min(root.cornerRadius,height/2);color:root.surface;border.width:1;border.color:root.line
                Icon {x:16;y:16;name:parent.modelData.icon;ink:root.accent;width:24;height:24}
                Label {x:16;y:58;width:parent.width-32;text:parent.modelData.title;font.weight:Font.DemiBold}
                Label {x:16;y:86;width:parent.width-32;text:root.locations.available.indexOf(parent.modelData.key)>=0?"On this phone":"Not set up";color:root.muted;font.pixelSize:root.fontSize(11)}
                MouseArea {anchors.fill:parent;enabled:root.locations.available.indexOf(parent.modelData.key)>=0;onClicked:root.navigate(root.locations[parent.modelData.key])}
              }
            }
          }
          Item {width:parent.width;height:28
            Label {anchors.verticalCenter:parent.verticalCenter;text:"RECENTLY MODIFIED";color:root.muted;font.pixelSize:root.fontSize(12);font.weight:Font.DemiBold}
            Button {anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:52;label:"All";quiet:true;onTapped:root.tab("recent")}
          }
          Column {width:parent.width
            Repeater {model:root.recent;FileRow {required property var modelData;entry:modelData;width:homeColumn.width;onTapped:root.openItem(entry);onHeld:{root.page="recent";root.items=root.recent;root.holdItem(entry)}}}
            Label {visible:root.recent.length===0;text:bridge.loading?"Loading files…":"Your recent changes will appear here.";color:root.muted;font.pixelSize:root.fontSize(13);width:parent.width;wrapMode:Text.Wrap}
          }
          Rectangle {width:parent.width;height:64;radius:Math.min(root.cornerRadius,height/2);color:root.surface;visible:root.capacity.total>0
            Icon {x:16;anchors.verticalCenter:parent.verticalCenter;name:"phone";ink:root.muted;width:24;height:24}
            Label {x:56;y:12;text:"Phone storage";font.pixelSize:root.fontSize(13)}
            Label {anchors.right:parent.right;anchors.rightMargin:16;y:14;text:root.capacity.total?Math.round(root.capacity.used/root.capacity.total*100)+"%":"";color:root.muted;font.family:root.mono;font.pixelSize:root.fontSize(11)}
            Rectangle {x:56;y:42;width:parent.width-72;height:3;color:root.line;Rectangle {height:3;width:parent.width*Math.max(0,Math.min(1,root.capacity.used/root.capacity.total));color:root.accent}}
          }
        }
      }
      ListView {
        id:list;objectName:"filesList";visible:root.page!=="home";anchors{left:parent.left;leftMargin:24;right:parent.right;rightMargin:24;top:searchBox.bottom;topMargin:16;bottom:bottomBar.top}
clip:true;model:root.items
        delegate:FileRow {required property var modelData;entry:modelData;width:list.width;visible:!root.targeting||entry.isDirectory||entry.targetIsDirectory;height:visible?80:0;onTapped:root.openItem(entry);onHeld:root.holdItem(entry)}
        footer:Item {width:list.width;height:root.more?72:0;Button {anchors.centerIn:parent;width:parent.width;visible:root.more;label:"Show more";onTapped:root.refresh(root.items.length)}}
      }
      Column {visible:root.page!=="home"&&root.items.length===0&&!bridge.loading;anchors.centerIn:list;width:list.width;spacing:16
        Icon {anchors.horizontalCenter:parent.horizontalCenter;name:root.failureCode==="permission_denied"?"folder":root.page==="trash"?"trash":"search";ink:root.muted;width:40;height:40}
        Label {objectName:"filesEmptyState";width:parent.width;horizontalAlignment:Text.AlignHCenter;text:root.message?"This folder is unavailable.":root.query?"Nothing found.":root.page==="trash"?"Your Trash is empty.":"Nothing here yet.";font.pixelSize:root.fontSize(22);wrapMode:Text.Wrap}
      }
      Rectangle {
        id:bottomBar;anchors{left:parent.left;right:parent.right;bottom:parent.bottom}
height:root.targeting||bridge.busy?96:76;color:root.deep
        Rectangle {width:parent.width;height:1;color:root.line}
        Row {anchors.fill:parent;anchors.margins:12;visible:!root.pickerMode&&!root.targeting&&!bridge.busy
          Repeater {model:root.selectedCount>0?(root.page==="trash"?[{title:"Restore",icon:"restore",action:"restore"},{title:"Restore to",icon:"move",action:"restoreTarget"}]:[{title:"Copy",icon:"copy",action:"copy"},{title:"Move",icon:"move",action:"move"},{title:"Trash",icon:"trash",action:"trash"},{title:"More",icon:"more",action:"selectedMore"}]):[{title:"Files",icon:"folder",action:"home"},{title:"Recent",icon:"clock",action:"recent"},{title:"Trash",icon:"trash",action:"trashTab"}]
            Item {required property var modelData;objectName:"action-"+modelData.title;Accessible.role:Accessible.Button;Accessible.name:modelData.title;width:(bottomBar.width-24)/(root.selectedCount>0?(root.page==="trash"?2:4):3);height:52
              Column {anchors.centerIn:parent;spacing:6
                Icon {anchors.horizontalCenter:parent.horizontalCenter;width:24;height:24;name:parent.parent.modelData.icon;ink:parent.parent.modelData.action===root.page?root.accent:parent.parent.modelData.action==="trash"?root.danger:root.muted}
                Label {anchors.horizontalCenter:parent.horizontalCenter;text:parent.parent.modelData.title;font.pixelSize:root.fontSize(11);color:parent.parent.modelData.action===root.page?root.accent:root.muted}
              }
              MouseArea {anchors.fill:parent;onClicked:{var a=parent.modelData.action;if(a==="copy"||a==="move")root.target(a);else if(a==="trash")root.trashSelected();else if(a==="restore")root.restoreSelected();else if(a==="restoreTarget")root.target("restore");else if(a==="selectedMore"){if(root.selectedCount===1){var chosen=Object.keys(root.selection)[0];root.contextItem=root.items.filter(function(item){return item.path===chosen})[0];root.modal="context"}else root.modal="options";}else root.tab(a==="trashTab"?"trash":a)}}
            }
          }
        }
        Button {visible:root.pickerMode;x:24;y:12;width:parent.width-48;label:"Cancel";onTapped:{bridge.cancel();root.finishPicker({ok:false,cancelled:true})}}
        Button {visible:root.targeting&&!bridge.busy;x:24;y:20;width:parent.width-48;label:root.planned.action==="copy"?"Copy here":root.planned.action==="restore"?"Restore here":"Move here";primary:true;icon:root.planned.action==="copy"?"copy":"move";onTapped:root.commitTarget(false)}
        Item {visible:bridge.busy;anchors.fill:parent;anchors.margins:20
          Label {text:bridge.cancelling?"Stopping safely…":Model.progressLabel(bridge.progress);font.pixelSize:root.fontSize(14);anchors.verticalCenter:parent.verticalCenter;anchors.left:parent.left;anchors.right:cancelOperation.left;anchors.rightMargin:12}
          Button {id:cancelOperation;anchors.right:parent.right;anchors.verticalCenter:parent.verticalCenter;width:96;label:"Cancel";enabled:!bridge.cancelling;onTapped:bridge.cancel()}
        }
      }
      Rectangle {visible:root.message!==""&&root.modal==="";anchors{left:parent.left;right:parent.right;bottom:bottomBar.top}
height:notice.implicitHeight+24;color:root.surface
        Label {id:notice;anchors{left:parent.left;right:parent.right;leftMargin:24;rightMargin:24;verticalCenter:parent.verticalCenter}
text:root.message;font.pixelSize:root.fontSize(13);wrapMode:Text.Wrap}
      }
      Rectangle {
        id:modalLayer;visible:root.modal!=="";anchors.fill:parent;color:"#99000000"
        MouseArea {anchors.fill:parent;onClicked:if(!bridge.busy)root.modal=""}
        Rectangle {anchors{left:parent.left;right:parent.right;bottom:parent.bottom}
height:Math.min(modalContent.height+48,Math.max(160,parent.height-24));color:root.deep;radius:Math.min(root.cornerRadius,height/2)
          MouseArea {anchors.fill:parent}
          Flickable {
            id:modalScroll;objectName:"filesModalScroll";anchors.fill:parent
            contentWidth:width;contentHeight:modalContent.height+48;clip:true
            boundsBehavior:Flickable.StopAtBounds
            Rectangle {
              parent:modalScroll
              visible:modalScroll.contentHeight>modalScroll.height
              width:3;radius:Math.min(root.cornerRadius,width/2);color:root.muted
              height:Math.max(16,modalScroll.height*modalScroll.height/modalScroll.contentHeight)
              x:modalScroll.width-width-4
              y:Math.max(0,Math.min(1,modalScroll.contentY/(modalScroll.contentHeight-modalScroll.height)))*(modalScroll.height-height)
            }
          Column {id:modalContent;x:24;y:24;width:parent.width-48;spacing:12
            Label {visible:root.modal!=="context";width:parent.width;text:root.modal==="context"?(root.contextItem?root.contextItem.name:""):root.modal==="rename"?"Rename":root.modal==="mkdir"?"New folder":root.modal==="trashConfirm"?"Move to Trash?":root.modal==="collision"?"Keep both files?":root.modal==="restoreTarget"?"Choose a new home.":"Folder options";font.pixelSize:root.fontSize(24);font.weight:Font.DemiBold;wrapMode:Text.Wrap}
            Item {width:parent.width;height:68;visible:root.modal==="context"
              Icon {anchors.left:parent.left;anchors.verticalCenter:parent.verticalCenter;width:32;height:32;name:root.contextItem?Model.icon(root.contextItem):"file";ink:root.fg}
              Column {x:48;anchors.verticalCenter:parent.verticalCenter;width:parent.width-48;spacing:5
                Label {width:parent.width;text:root.contextItem?root.contextItem.name:"";font.pixelSize:root.fontSize(20);font.weight:Font.DemiBold}
                Label {width:parent.width;text:root.contextItem?(root.contextItem.isDirectory?"Folder":Model.bytes(root.contextItem.size)):"";color:root.muted;font.pixelSize:root.fontSize(12)}
              }
            }
            Column {width:parent.width;visible:root.modal==="context";spacing:0
              Repeater {model:root.page==="trash"?[{title:"Restore",icon:"restore",action:"restore"},{title:"Restore to…",icon:"move",action:"restoreTarget"}]:[{title:"Open",icon:"arrow",action:"open"},{title:"Copy",icon:"copy",action:"copy"},{title:"Move",icon:"move",action:"move"},{title:"Rename",icon:"edit",action:"rename"},{title:"Move to Trash",icon:"trash",action:"trash"}]
                Button {required property var modelData;width:parent.width;label:modelData.title;icon:modelData.icon;quiet:true;alignLeft:true;destructive:modelData.action==="trash";onTapped:{var a=modelData.action;if(a==="open"){root.modal="";root.selection=({});root.openItem(root.contextItem)}else if(a==="copy"||a==="move")root.target(a);else if(a==="rename"){root.editText=root.contextItem.name;editor.text=root.editText;root.modal="rename";editor.forceActiveFocus()}else if(a==="trash")root.trashSelected();else if(a==="restore")root.restoreSelected();else root.target("restore")}}
              }
            }
            Column {width:parent.width;visible:root.modal==="options";spacing:4
              Repeater {model:(root.page==="home"?[]:root.targeting?[]:[{title:"Select all",action:"selectAll"}]).concat(root.page==="home"?[{title:"New folder",action:"mkdir"}]:root.page==="browse"||root.targeting?[{title:root.hidden?"Hide hidden files":"Show hidden files",action:"hidden"},{title:"Sort by name",action:"name"},{title:"Sort by modified date",action:"modified"},{title:"New folder",action:"mkdir"}]:[]).concat([{title:"Refresh",action:"refresh"}])
                Button {required property var modelData;width:parent.width;label:modelData.title;quiet:true;alignLeft:true;onTapped:{var a=modelData.action;if(a==="mkdir"){editor.text="";root.modal="mkdir";editor.forceActiveFocus();return}root.modal="";if(a==="selectAll"){var chosen={};root.items.forEach(function(item){chosen=Model.toggle(chosen,item)});root.selection=chosen;return}if(a==="hidden")root.hidden=!root.hidden;else if(a==="name"||a==="modified"){root.sorting=a;root.descending=a==="modified"}root.refresh()}}
              }
            }
            Rectangle {visible:root.modal==="rename"||root.modal==="mkdir";width:parent.width;height:56;radius:Math.min(root.cornerRadius,height/2);color:root.surface;border.width:1;border.color:root.accent
              TextInput {id:editor;objectName:"filesName";anchors.fill:parent;anchors.margins:16;color:root.fg;font.family:root.family;font.pixelSize:root.fontSize(16);selectByMouse:true;clip:true;inputMethodHints:Qt.ImhNoAutoUppercase;Accessible.name:root.modal==="rename"?"File name":"Folder name"}
            }
            Label {visible:root.modal==="trashConfirm"||root.modal==="collision"||root.modal==="restoreTarget";width:parent.width;text:root.modal==="trashConfirm"?"You can restore these files from Trash.":root.modal==="collision"?"A file with this name already exists. Keep both creates a new name; nothing is replaced.":"The original folder is no longer available. Choose where to restore these files.";font.pixelSize:root.fontSize(15);color:root.muted;wrapMode:Text.Wrap}
            Row {visible:root.modal!=="context"&&root.modal!=="options";width:parent.width;spacing:12
              Button {width:(parent.width-12)/2;label:"Cancel";onTapped:{root.modal="";root.dismissKeyboard()}}
              Button {width:(parent.width-12)/2;label:root.modal==="collision"?"Keep both":root.modal==="trashConfirm"?"Move to Trash":root.modal==="restoreTarget"?"Choose folder":"Save";primary:true;destructive:root.modal==="trashConfirm";enabled:!bridge.busy;onTapped:{var kind=root.modal;root.modal="";root.dismissKeyboard();if(kind==="collision")root.commitTarget(true);else if(kind==="trashConfirm")bridge.act("trash",{sources:root.planned.sources});else if(kind==="restoreTarget")root.target("restore");else if(kind==="rename")bridge.act("rename",{source:{path:root.contextItem.path,token:root.contextItem.token},name:editor.text});else bridge.act("mkdir",{path:root.path,name:editor.text})}}
            }
          }
          }
        }
      }
    }
  }
}
