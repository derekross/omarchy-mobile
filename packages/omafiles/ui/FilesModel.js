// SPDX-License-Identifier: MIT
function bytes(value) {
  var size=Number(value)||0;
  if(size<1024)return Math.max(0,Math.round(size))+" B";
  var units=["KB","MB","GB","TB"],n=size/1024,index=0;
  while(n>=1024&&index<units.length-1){n/=1024;index++;}
  return (n<10?n.toFixed(1):Math.round(n))+" "+units[index];
}
function title(path,home){
  if(path===home)return "All files";
  return String(path||"").replace(/\/+$/,"").split("/").pop()||"Files";
}
function icon(item){return item.isDirectory||item.targetIsDirectory?"folder":String(item.mime||"").indexOf("image/")===0?"image":"file";}
function toggle(selection,item){
  var next=Object.assign({},selection||{});
  if(Object.prototype.hasOwnProperty.call(next,item.path))delete next[item.path];
  else {next[item.path]={path:item.path,token:item.token};if(item.trashId)next[item.path].trashId=item.trashId;}
  return next;
}
function sources(selection){return Object.keys(selection||{}).map(function(path){return {path:path,token:selection[path].token};});}
function prune(selection,items){
  var live={};items.forEach(function(item){live[item.path]=item;});
  var next={};Object.keys(selection||{}).forEach(function(path){
    // Tokens are opaque string arrays. Never convert inode/mtime to numbers.
    if(live[path]&&JSON.stringify(live[path].token)===JSON.stringify(selection[path].token))next[path]=selection[path];
  });return next;
}
function progressLabel(update){
  if(update.bytesTotal>0)return bytes(update.bytesDone||0)+" of "+bytes(update.bytesTotal);
  if(update.itemsTotal>0)return (update.itemsDone||0)+" of "+update.itemsTotal+" files";
  return "Preparing files…";
}
if(typeof module!=="undefined")module.exports={bytes:bytes,title:title,icon:icon,toggle:toggle,sources:sources,prune:prune,progressLabel:progressLabel};
