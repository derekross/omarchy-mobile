// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
import TestHyprland
TestCase {
 id:test;name:"ForegroundHomeIdle";when:windowShown;width:420;height:935
 Component{id:component;HomePoll{}}
 property var home
 function foreground(on){Hyprland.focusedWorkspace={toplevels:{values:on?[{}]:[]}}}
 function init(){foreground(false);home=createTemporaryObject(component,test);verify(home!==null)}
 function test_home_reads(){home.owlBacklight="fixture";wait(110);verify(home.reads>=1)}
 function test_foreground_zero_reads(){foreground(true);home.owlBacklight="fixture";wait(110);compare(home.reads,0)}
 function test_unknown_backlight_zero_reads(){wait(100);compare(home.reads,0)}
 function test_return_refresh_immediate(){home.owlBacklight="fixture";foreground(true);home.value="0";home.owlPanelOff=true;var before=home.reads;foreground(false);compare(home.reads,before+1);compare(home.owlPanelOff,false)}
 function test_return_preserves_panel_off(){home.owlBacklight="fixture";foreground(true);home.value="4";foreground(false);compare(home.owlPanelOff,true)}
 function test_stops_after_cover(){home.owlBacklight="fixture";wait(50);foreground(true);var before=home.reads;wait(110);compare(home.reads,before)}
 function test_visibility_binding_hides_home_behind_app(){compare(home.homeShown,true);foreground(true);compare(home.appOnScreen,true);compare(home.homeShown,false);foreground(false);compare(home.homeShown,true)}
 function test_no_workspace_return_refreshes(){home.owlBacklight="fixture";foreground(true);var before=home.reads;Hyprland.focusedWorkspace=null;compare(home.appOnScreen,false);compare(home.reads,before+1)}
 function test_queued_callback_after_cover_does_not_read(){home.owlBacklight="fixture";foreground(true);var before=home.reads;var timer=findChild(home,"backlightPoll");verify(timer!==null);timer.triggered();compare(home.reads,before)}
}
