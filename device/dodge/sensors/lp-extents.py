import struct,sys
f=open(sys.argv[1],'rb')
f.seek(4096); g=f.read(52)
magic,ssz=struct.unpack('<II',g[:8]); assert magic==0x616c4467,hex(magic)
mms,slots,lbs=struct.unpack('<III',g[40:52])
off=4096+4096*2
f.seek(off); h=f.read(256)
m,maj,mn,hsz=struct.unpack('<IHHI',h[:12]); assert m==0x414C5030
p=12+32; tsz=struct.unpack('<I',h[p:p+4])[0]; p+=4+32
descs=[struct.unpack('<III',h[p+i*12:p+i*12+12]) for i in range(4)]
f.seek(off+hsz); t=f.read(tsz)
po,pn,pe=descs[0]; eo,en,ee=descs[1]
ext=[struct.unpack('<QIQI',t[eo+i*ee:eo+i*ee+24]) for i in range(en)]
for i in range(pn):
    e=t[po+i*pe:po+(i+1)*pe]
    name=e[:36].rstrip(b'\0').decode(); a,fi,ne,gi=struct.unpack('<IIII',e[36:52])
    xs=[(ext[j][0],ext[j][1],ext[j][2]) for j in range(fi,fi+ne)]
    print(name, ' '.join(f'{n}:{ty}:{d}' for n,ty,d in xs))
