// SPDX-License-Identifier: MIT
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),path=require('path');
const root=process.argv[2];assert(root,'usage: node notification-store45.cjs SHELL');
function load(p,extras={}) {const x={module:{exports:{}},...extras};vm.createContext(x);vm.runInContext(fs.readFileSync(p,'utf8').replace(/^\.(?:pragma|import).*$/mg,''),x);return x;}
const logic=load(path.join(root,'plugins/notifications/NotificationLogic.js')).module.exports;
const glance=load(path.join(root,'plugins/lock/LockGlance.js'),{NotificationLogic:logic,Date});
const now=Date.now(),n={key:'nSynthetic1',ts:now/1000,originalId:1,app:'Fixture',summary:'Synthetic summary',body:'Synthetic body',image:'file:///tmp/synthetic.png',urgency:1};
const raw=JSON.stringify([n])+ '\n'+JSON.stringify([{...n,summary:'older copy',ts:n.ts-1},{...n,key:'nSynthetic2',originalId:2,ts:n.ts-2}])+'\n'+JSON.stringify({dnd:false});
const rows=logic.historyRows(raw,[],1,10);assert.equal(rows.length,2);assert.equal(rows[0].key,'nSynthetic1');assert.equal(rows[0].timestamp,now);assert.equal(logic.popupFileName(rows[0]),'nSynthetic1');assert.equal(rows[0].summary,n.summary);
assert.equal(glance.cards(raw,now,false,false).length,2);
const hidden=glance.cards(raw,now,true,false)[0];assert.equal(hidden.summary,'Fixture');assert.equal(hidden.body,'Unlock to read');assert.equal(hidden.image,'');assert.equal(hidden.file,'nSynthetic1');
assert.equal(glance.cards(raw,now,false,true).length,0);assert.equal(glance.doNotDisturb('{"dnd":true}'),true);
assert.equal(logic.historyRows(JSON.stringify([{...n,key:'../bad'}]),[],1,10).length,0);
assert.equal(logic.historyRows(JSON.stringify([{...n,ts:'bad'}]),[],1,10).length,0);
assert.equal(logic.historyRows('{"dnd":true}\n',[],1,10).length,0);
const old={originalId:8,timestamp:now,app:'Fixture',summary:'Legacy synthetic'};const oldrow=logic.historyRows(JSON.stringify(old)+'\n',[],1,10)[0];assert.equal(logic.popupFileName(oldrow),String(now)+'-8.json');
console.log('PASS4.5store->legacyglance: keyed live/history merge, dedupe, timestamp, privacy/DND, malformed rows; oldrecord compatibility');
