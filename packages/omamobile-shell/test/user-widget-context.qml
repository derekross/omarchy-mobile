// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
TestCase {
 id:test;name:"ReadonlyWidgetContext";when:windowShown;visible:true;width:420;height:400
 QtObject{id:readonlySettings;readonly property int settings:1}
 function init(){failOnWarning(/.?/);fakeHome.errors=[]}
 property var view:null
 property string widgetUrl:""
 QtObject{id:fakeHome;property color foreground:"white";property color dimForeground:"gray";property var errors:[];function userCard(id){return {state:"ok",message:"",url:test.widgetUrl,record:{dir:"fixture",hash:"owned",manifest:{capabilities:[],name:"Owned fixture",icon:"W"}}}} function guardBegin(){}function guardEnd(){}function noteRuntimeError(id,error){errors=errors.concat([error])}function openSettings(){}}
 Component{id:cell;UserWidgetCell{width:300;height:250;home:fakeHome;entry:({id:"owned",type:"user:owned",w:2,h:2,config:{value:1}})}}
 function make(name){widgetUrl=Qt.resolvedUrl(name+".qml").toString();view=createTemporaryObject(cell,test);verify(view!==null);tryVerify(function(){return findChild(view,"loadedWidget")!==null});return findChild(view,"loadedWidget")}
 function test_readonly_shown_tracks_host_without_error(){var w=make("readonly");compare(w.shown,true);view.shown=false;tryCompare(w,"shown",false);view.shown=true;tryCompare(w,"shown",true);compare(fakeHome.errors.length,0)}
 function test_writable_shown_remains_bound(){var w=make("writable");compare(w.shown,true);view.shown=false;tryCompare(w,"shown",false);view.shown=true;tryCompare(w,"shown",true)}
 function test_other_context_bindings_still_update(){var w=make("readonly");view.editing=true;tryCompare(w,"editing",true);view.entry={id:"owned",type:"user:owned",w:3,h:4,config:{value:9}};tryCompare(w,"cellsWide",3);tryCompare(w,"cellsHigh",4);compare(w.settings.value,9)}
 function test_missing_optional_property_ignored(){make("writable");compare(view.bindContext({},"shown",true),false)}
 function test_nonreadonly_error_propagates(){make("writable");var object={};Object.defineProperty(object,"shown",{set:function(value){throw new TypeError("Unexpected setter failure")}});var threw=false;try{view.bindContext(object,"shown",true)}catch(e){threw=e.message==="Unexpected setter failure"};verify(threw)}
 function test_other_readonly_property_not_caught(){make("writable");var threw=false;try{view.bindContext(readonlySettings,"settings",2)}catch(e){threw=e instanceof TypeError && e.message==='Cannot assign to read-only property "settings"'};verify(threw)}
}
