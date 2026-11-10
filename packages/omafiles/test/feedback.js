// SPDX-License-Identifier: MIT
// Actual QML JS functions; no window, feedback service or motor is invoked.
const fs=require('fs'),vm=require('vm'),assert=require('assert')
const source=fs.readFileSync(require('path').join(__dirname,'../ui/shell.qml'),'utf8')
function extract(name){const start=source.indexOf('function '+name+'(');assert(start>=0);const begin=source.indexOf('{',start);let depth=1,end=begin+1;while(depth&&end<source.length){if(source[end]==='{')depth++;if(source[end]==='}')depth--;end++}return source.slice(start,end)}
let ticks=[]
const c=vm.createContext({bridge:{busy:false},targeting:false,pickerMode:false,selection:{},modal:'',contextItem:null,Model:{toggle:(selection,item)=>Object.assign({},selection,{[item.path]:item})},Quickshell:{execDetached:args=>ticks.push(Array.from(args))}})
vm.runInContext(['feedback','holdItem','context'].map(extract).join('\n'),c)
c.holdItem({path:'/fixture/a'});assert.deepEqual(ticks,[['sh','-c','command -v fbcli >/dev/null 2>&1 && exec fbcli -E button-pressed']]);assert(c.selection['/fixture/a'])
c.bridge.busy=true;c.holdItem({path:'/fixture/b'});c.context({path:'/fixture/a'});assert.equal(ticks.length,1)
c.bridge.busy=false;c.targeting=true;c.holdItem({path:'/fixture/b'});c.context({path:'/fixture/a'});assert.equal(ticks.length,1)
c.targeting=false;c.context({path:'/fixture/a'});assert.equal(ticks.length,2);assert.deepEqual(ticks[1],['sh','-c','command -v fbcli >/dev/null 2>&1 && exec fbcli -E button-pressed'])
c.context({path:'/fixture/a'});assert.equal(ticks.length,2,'already open context does not tick twice')
assert.equal((source.match(/feedback\("long-press"\)/g)||[]).length,1)
assert.equal((source.match(/feedback\("context-open"\)/g)||[]).length,1)
console.log('PASS actual accepted longpress/context once; busy/targeting/repeated context no tick; no pointer/frame feedback hooks')

assert(!source.includes('omamobile-feedback'),'no private helper dependency')
assert(c.Quickshell,'feedback uses the guarded public optional fbcli command')
