# SPDX-License-Identifier: MIT
"""Text SMS TPDU encoding/decoding (3GPP TS 23.038 and TS 23.040).

No flash/class-0, SIM data download, or other special outbound messages.
Received 8-bit messages keep their bytes and destination port: a WAP push
to port 2948 carries an MMS notification, which the Messages app reads.
"""
import datetime
import math
import re
import secrets

GSM = '@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ\x1bÆæßÉ !"#¤%&\'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà'
EXT = {10:'\f',20:'^',40:'{',41:'}',47:'\\',60:'[',61:'~',62:']',64:'|',101:'€'}
ENC = {c: [i] for i,c in enumerate(GSM) if i != 27}
ENC.update({c:[27,i] for i,c in EXT.items()})


def number(value, *, voice=False):
    value = re.sub(r'[\s().-]', '', value)
    if re.fullmatch(r'[2-9]\d{9}', value):
        value = '+1' + value
    elif re.fullmatch(r'1[2-9]\d{9}', value):
        value = '+' + value
    if not re.fullmatch(r'\+?[0-9]{3,15}', value):
        raise ValueError('Enter a phone number with its country code')
    if voice and not re.fullmatch(r'\+[1-9][0-9]{6,14}', value):
        raise ValueError('Short-code and emergency calling are not supported yet')
    return value


def pack7(values, header=b''):
    skip = math.ceil(len(header)*8/7)
    bits = int.from_bytes(header,'little')
    for i, val in enumerate(values): bits |= val << ((i+skip)*7)
    count = skip + len(values)
    return count, bits.to_bytes(math.ceil(count*7/8),'little')


def unpack7(data, count, skip=0):
    if (count*7+7)//8 > len(data): raise ValueError('Truncated GSM text')
    bits = int.from_bytes(data,'little')
    out, escape = [], False
    for i in range(skip,count):
        val = (bits >> (i*7)) & 127
        if escape:
            out.append(EXT.get(val,'�')); escape=False
        elif val == 27: escape=True
        else: out.append(GSM[val])
    return ''.join(out)


def address(value):
    digits=value.lstrip('+'); padded=digits+('F' if len(digits)%2 else '')
    return bytes([len(digits), 0x91 if value.startswith('+') else 0x81])+bytes(int(padded[i+1]+padded[i],16) for i in range(0,len(padded),2))


def submit(destination, text):
    destination=number(destination)
    if not isinstance(text,str) or not text.strip() or len(text)>1600:
        raise ValueError('Enter a message of 1 to 1600 characters')
    gsm=all(c in ENC for c in text)
    units=[ENC[c] if gsm else list(c.encode('utf-16-be')) for c in text]
    single, limit=(160,153) if gsm else (140,134)
    total=sum(map(len,units)); limit=single if total<=single else limit
    parts=[[]]
    for unit in units:
        if len(parts[-1])+len(unit)>limit: parts.append([])
        parts[-1].extend(unit)
    reference=secrets.randbelow(256)
    result=[]
    for i,part in enumerate(parts):
        header=bytes([5,0,3,reference,len(parts),i+1]) if len(parts)>1 else b''
        if gsm: length,body=pack7(part,header)
        else: body=header+bytes(part); length=len(body)
        result.append(bytes([0x41 if header else 1,0])+address(destination)+bytes([0,0 if gsm else 8,length])+body)
    return result


WAP_PUSH = 2948


def deliver(pdu):
    """Decode SMS-DELIVER. A WAP push (MMS) keeps its bytes as data; other
    binary content stays a placeholder."""
    if len(pdu)<3 or pdu[0]&3: raise ValueError('Not an SMS delivery')
    first,n,toa=pdu[:3]; pos=3
    size=math.ceil(n/2)
    if pos+size+10>len(pdu): raise ValueError('Truncated SMS delivery')
    raw=pdu[pos:pos+size]; pos+=size
    if toa & 0x70 == 0x50:
        sender=unpack7(raw,n*4//7)
    else:
        sender=''.join(f'{b&15:x}{b>>4:x}' for b in raw)[:n]
        if not sender.isdigit(): raise ValueError('Invalid sender address')
        if toa&0x70==0x10: sender='+'+sender
    pid,dcs=pdu[pos:pos+2]; pos+=2
    stamp=pdu[pos:pos+7]; pos+=7
    def bcd(x): return (x&15)*10+(x>>4)
    try:
        year,month,day,hour,minute,second=map(bcd,stamp[:6])
        zone=datetime.timedelta(minutes=bcd(stamp[6]&0xf7)*15)
        if stamp[6]&8: zone=-zone
        timestamp=datetime.datetime(2000+year if year<90 else 1900+year,month,day,hour,minute,second,tzinfo=datetime.timezone(zone)).isoformat()
    except ValueError: timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat()
    length=pdu[pos]; data=pdu[pos+1:]; header=0; concat=None; port=None
    if first&0x40:
        if not data: raise ValueError('Missing SMS header')
        header=data[0]+1
        if header>len(data): raise ValueError('Truncated SMS header')
        i=1
        while i<header:
            if i+2>header: raise ValueError('Malformed SMS header')
            tag,size=data[i:i+2]; value=data[i+2:i+2+size]; i+=2+size
            if i>header: raise ValueError('Malformed SMS header')
            if tag==0 and size==3: concat=tuple(value)
            elif tag==8 and size==4: concat=(int.from_bytes(value[:2],'big'),value[2],value[3])
            elif tag==5 and size==4: port=int.from_bytes(value[:2],'big')
            elif tag==4 and size==2: port=value[0]
        if concat and not 1<=concat[2]<=concat[1]<=32: raise ValueError('Invalid SMS part index')
    alphabet=(dcs>>2)&3 if dcs&0xc0==0 else (0 if dcs&0xf0 in (0xc0,0xd0) else 2 if dcs&0xf0==0xe0 else (1 if dcs&4 else 0))
    if dcs&0xc0==0 and dcs&0x20: alphabet=1  # compressed content unsupported
    if alphabet==0:
        text=unpack7(data,length,math.ceil(header*8/7))
    elif alphabet==2:
        if length>len(data) or length<header: raise ValueError('Truncated Unicode SMS')
        text=data[header:length].decode('utf-16-be',errors='replace')
    elif alphabet==1 and (port==WAP_PUSH or (concat and port is None)) and not (dcs&0xc0==0 and dcs&0x20):
        if length>len(data) or length<header: raise ValueError('Truncated WAP push')
        return dict(number=sender,text='',timestamp=timestamp,concat=concat,port=port,data=bytes(data[header:length]))
    else: text='Received a multimedia or binary message that this phone cannot display yet.'
    return dict(number=sender,text=text,timestamp=timestamp,concat=concat,port=port,data=b'')


def received_pdu(data):
    # The matching modem's incoming field includes the SMSC prefix, unlike
    # its outgoing TPDU field. Verified against both real received messages.
    if not data or data[0]>12 or len(data)<=1+data[0]:
        raise ValueError('Invalid received SMS service-centre prefix')
    return deliver(data[1+data[0]:])
