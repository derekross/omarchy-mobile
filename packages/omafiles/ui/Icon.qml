// SPDX-License-Identifier: MIT
import QtQuick
import "file:///usr/share/omarchy/shell/Commons" as Commons
Canvas {
  id: icon
  property string name: "file"
  property color ink: Commons.Color.foreground
  implicitWidth: 24; implicitHeight: 24
  onNameChanged: requestPaint()
  onInkChanged: requestPaint()
  onPaint: {
    var c=getContext("2d");c.reset();c.scale(width/24,height/24);c.strokeStyle=ink;c.lineWidth=1.7;c.lineCap="round";c.lineJoin="round";c.beginPath()
    if(name==="folder"){c.moveTo(3,7);c.lineTo(9,7);c.lineTo(11,4);c.lineTo(21,4);c.lineTo(21,20);c.lineTo(3,20);c.closePath()}
    else if(name==="back"){c.moveTo(15,5);c.lineTo(8,12);c.lineTo(15,19)}
    else if(name==="chevron"){c.moveTo(9,5);c.lineTo(16,12);c.lineTo(9,19)}
    else if(name==="close"){c.moveTo(6,6);c.lineTo(18,18);c.moveTo(18,6);c.lineTo(6,18)}
    else if(name==="check"){c.moveTo(5,12);c.lineTo(9,16);c.lineTo(19,6)}
    else if(name==="plus"){c.moveTo(12,4);c.lineTo(12,20);c.moveTo(4,12);c.lineTo(20,12)}
    else if(name==="search"){c.arc(10.5,10.5,6.5,0,Math.PI*2);c.moveTo(16,16);c.lineTo(21,21)}
    else if(name==="clock"){c.arc(12,12,9,0,Math.PI*2);c.moveTo(12,7);c.lineTo(12,12);c.lineTo(15,14)}
    else if(name==="trash"){c.moveTo(3,6);c.lineTo(21,6);c.moveTo(9,6);c.lineTo(9,3);c.lineTo(15,3);c.lineTo(15,6);c.moveTo(5,6);c.lineTo(6,21);c.lineTo(18,21);c.lineTo(19,6);c.moveTo(10,10);c.lineTo(10,17);c.moveTo(14,10);c.lineTo(14,17)}
    else if(name==="copy"){c.rect(8,8,13,13);c.moveTo(3,16);c.lineTo(3,3);c.lineTo(16,3)}
    else if(name==="move"){c.moveTo(3,7);c.lineTo(10,7);c.lineTo(12,10);c.lineTo(21,10);c.lineTo(21,21);c.lineTo(3,21);c.closePath();c.moveTo(12,3);c.lineTo(21,3);c.moveTo(17,0);c.lineTo(21,3);c.lineTo(17,6)}
    else if(name==="download"){c.moveTo(12,3);c.lineTo(12,15);c.moveTo(7,10);c.lineTo(12,15);c.lineTo(17,10);c.moveTo(4,17);c.lineTo(4,21);c.lineTo(20,21);c.lineTo(20,17)}
    else if(name==="image"){c.rect(3,3,18,18);c.moveTo(9.5,8);c.arc(8,8,1.5,0,Math.PI*2);c.moveTo(3,17);c.lineTo(8,12);c.lineTo(12,16);c.lineTo(15,13);c.lineTo(21,19)}
    else if(name==="edit"){c.moveTo(16,3);c.lineTo(21,8);c.lineTo(8,21);c.lineTo(3,21);c.lineTo(3,16);c.closePath();c.moveTo(14,5);c.lineTo(19,10)}
    else if(name==="more"){[5,12,19].forEach(function(x){c.moveTo(x+1,12);c.arc(x,12,1,0,Math.PI*2)})}
    else if(name==="arrow"){c.moveTo(4,12);c.lineTo(20,12);c.moveTo(14,6);c.lineTo(20,12);c.lineTo(14,18)}
    else if(name==="restore"){c.arc(12,12,8,-2.8,2.5);c.moveTo(3,3);c.lineTo(3,9);c.lineTo(9,9)}
    else if(name==="sort"){c.moveTo(4,5);c.lineTo(20,5);c.moveTo(4,12);c.lineTo(15,12);c.moveTo(4,19);c.lineTo(10,19)}
    else if(name==="phone"){c.rect(6,2,12,20);c.moveTo(10,18);c.lineTo(14,18)}
    else {c.moveTo(6,3);c.lineTo(14,3);c.lineTo(18,7);c.lineTo(18,21);c.lineTo(6,21);c.closePath();c.moveTo(14,3);c.lineTo(14,8);c.lineTo(18,8)}
    c.stroke()
  }
}
