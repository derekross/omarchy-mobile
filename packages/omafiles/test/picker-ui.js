// SPDX-License-Identifier: MIT
const fs=require('fs'),vm=require('vm'),assert=require('assert')
const source=fs.readFileSync(require('path').join(__dirname,'../ui/shell.qml'),'utf8')
function extract(name){const start=source.indexOf('function '+name+'(');assert(start>=0);const begin=source.indexOf('{',start);let depth=1,end=begin+1;while(depth&&end<source.length){if(source[end]==='{')depth++;if(source[end]==='}')depth--;end++}return source.slice(start,end).replace(/nonce:string/g,'nonce').replace(/\):string\s*\{/,'){')}
let actions=[],navigation=[]
const c=vm.createContext({pickerNonce:'owned-nonce',pickerMode:true,pickerResult:{pending:true},window:{visible:true},pickerOutput:{setText:value=>actions.push({result:JSON.parse(value)})},bridge:{busy:false,act:(action,payload)=>actions.push({action,payload})},navigate:path=>navigation.push(path),selectedCount:0,selection:{},targeting:false,page:'browse'})
c.root=c
vm.runInContext(['finishPicker','openItem','result','cancel'].map(extract).join('\n'),c)
c.openItem({path:'/fixture/folder',isDirectory:true});assert.deepEqual(navigation,['/fixture/folder']);assert.equal(actions.length,0)
c.openItem({path:'/fixture/Straße %.png',isDirectory:false,token:['1','2','3','4','5']});assert.equal(actions.length,1);assert.equal(actions[0].action,'pick-image');assert.equal(actions[0].payload.source.path,'/fixture/Straße %.png')
assert.equal(JSON.parse(c.result('foreign')).error,'invalid_request');assert.equal(c.cancel('foreign'),'refused');assert.equal(c.pickerResult.pending,true)
assert.equal(c.cancel('owned-nonce'),'ok');assert.equal(actions[actions.length-1].result.nonce,'owned-nonce');assert.equal(actions[actions.length-1].result.result.cancelled,true);assert.equal(JSON.parse(c.result('owned-nonce')).cancelled,true)
c.finishPicker({ok:true,path:'/late/result.png'});assert.equal(c.pickerResult.cancelled,true,'late validation cannot overwrite Cancel')
assert(source.includes('visible:!root.pickerMode&&!root.targeting&&!bridge.busy'),'destructive toolbar hidden in picker')
assert(source.includes('imagesOnly:pickerMode'));assert(source.includes('if(bridge.busy||targeting||pickerMode)return;selection='),'picker does not enable selection operations')
console.log('PASS actual picker UI functions: folder browse, captured image request, nonce isolation, Cancel and late-result guard, read-only picker controls')
