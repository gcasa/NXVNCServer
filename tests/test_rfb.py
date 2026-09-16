#!/usr/bin/env python3
"""Independent wire decoder + tests of the real server (macOS Foundation).
Run: python3 tests/test_rfb.py. Builds only in a temporary directory.
"""
import ctypes as C
import io
import os
from pathlib import Path
import random
import socket
import struct
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent

class Format(C.Structure):
    _fields_ = [(k,C.c_int) for k in ('bytes','compactBytes','compactOffset','direct')] + [
        (k,C.c_ulong*256) for k in ('red','green','blue')] + [('bigEndian',C.c_int)]

class GrayCache(C.Structure):
    _fields_=[(k,C.c_int) for k in ('width','height','rowBytes','valid','invert')] + [
        (k,C.c_void_p) for k in ('previous','dirty','versions')]

def cache_tests(lib):
    w,h,stride=67,35,20
    c=GrayCache(); assert lib.NXVNCInitGrayCache(C.byref(c),w,h)
    source=(C.c_ubyte*(stride*h))()
    rgb=(C.c_ubyte*(w*h*4))()
    compare,expand=C.c_double(),C.c_double()
    def refresh(invert=0):
        return lib.NXVNCRefreshGrayCache(C.byref(c),source,stride,invert,rgb,
                                        C.byref(compare),C.byref(expand))
    versions=(C.c_ulong*6).from_address(c.versions)
    try:
        assert refresh()==6 and list(versions)==[1]*6
        assert refresh()==0 and not any(rgb)
        # Change only row padding and the unused low bits of the last byte.
        for y in range(h):
            source[y*stride+16]|=3
            source[y*stride+17]=255
        assert refresh()==0
        source[34*stride+16]|=0x30 # pixel 65: gray 255
        assert refresh()==1 and list(versions)==[1,1,1,1,1,2]
        expected=bytearray(w*h*4); pos=(34*w+65)*4
        expected[pos+1:pos+4]=bytes([255]*3)
        assert bytes(rgb)==expected
        assert refresh()==0
        assert refresh(1)==6 # color-space polarity change invalidates all tiles
        for i in range(w*h):
            assert bytes(rgb[i*4:i*4+4])==bytes((0,*(0 if i==34*w+65 else 255 for _ in range(3))))
        c.valid=0
        assert refresh(1)==6 # return from a generic capture format
    finally: lib.NXVNCFreeGrayCache(C.byref(c))
    # Tightly packed rows take the whole-band comparison fast path.
    w,h,stride=64,65,16
    c=GrayCache(); assert lib.NXVNCInitGrayCache(C.byref(c),w,h)
    source=(C.c_ubyte*(stride*h))()
    rgb=(C.c_ubyte*(w*h*4))()
    versions=(C.c_ulong*6).from_address(c.versions)
    expected=bytearray(w*h*4)
    try:
        assert refresh()==6 and list(versions)==[1]*6
        assert refresh()==0
        for x,y,tile in [(35,40,3),(0,0,0),(63,64,5)]:
            before=list(versions)
            source[y*stride+x//4] |= 3 << (6-2*(x%4))
            assert refresh()==1
            before[tile]+=1
            assert list(versions)==before
            pos=(y*w+x)*4
            expected[pos+1:pos+4]=bytes([255]*3)
            assert bytes(rgb)==expected
            assert refresh()==0
            assert not any((C.c_ubyte*6).from_address(c.dirty))
        assert refresh(1)==6
        assert refresh(1)==0
    finally: lib.NXVNCFreeGrayCache(C.byref(c))
    print('PASS: packed cache, unchanged bands, changed tiles, padding, inversion, invalidation')

FORMATS = [(32,24,1,255,255,255,16,8,0), (32,24,0,255,255,255,16,8,0),
           (16,16,0,31,63,31,11,5,0), (16,16,1,31,63,31,11,5,0),
           (8,8,0,7,7,3,5,2,0), (32,24,1,255,255,255,24,16,8),
           (32,24,0,255,255,255,24,16,8), (32,32,1,255,255,255,16,8,0)]

def wire_pixel(rgb, fmt, compact=False):
    bpp,depth,be,r,g,b,rs,gs,bs=fmt
    value=(rgb[0]*r//255<<rs)|(rgb[1]*g//255<<gs)|(rgb[2]*b//255<<bs)
    data=value.to_bytes(bpp//8,'big' if be else 'little')
    mask=(r<<rs)|(g<<gs)|(b<<bs)
    if compact and bpp==32 and depth<=24:
        if mask < 1<<24: data=data[1:] if be else data[:-1]
        elif mask&255==0: data=data[:-1] if be else data[1:]
    return data

def decode_tile(read,w,h,fmt,encoding):
    size=len(wire_pixel((0,0,0),fmt,encoding==15))
    kind=read(1)[0]
    if encoding==15:
        if kind==0: return [read(size) for _ in range(w*h)]
        assert 1<=kind<=16,kind
        palette=[read(size) for _ in range(kind)]
        if kind==1: return palette*(w*h)
        bits=1 if kind==2 else 2 if kind<=4 else 4
        result=[]
        for y in range(h):
            row=read((w*bits+7)//8)
            for x in range(w):
                result.append(palette[(row[x*bits//8]>>(8-bits-x*bits%8))&((1<<bits)-1)])
        return result
    if kind&1: return [read(size) for _ in range(w*h)]
    assert kind&2 # encoder always specifies background
    result=[read(size)]*(w*h)
    fg=read(size) if kind&4 else None
    if kind&8:
        for _ in range(read(1)[0]):
            color=read(size) if kind&16 else fg
            xy,wh=read(2); x,y=xy>>4,xy&15; rw,rh=(wh>>4)+1,(wh&15)+1
            assert x+rw<=w and y+rh<=h
            for yy in range(y,y+rh): result[yy*w+x:yy*w+x+rw]=[color]*rw
    return result

def core_tests(lib):
    lib.NXVNCSetFormat.argtypes=[C.POINTER(Format)]+[C.c_int]*9
    rng=random.Random(2345)
    for fmt in FORMATS:
        f=Format(); assert lib.NXVNCSetFormat(C.byref(f),*fmt)
        for w,h in [(16,16),(1,1),(3,7),(15,16),(16,1)]:
            for mode in ['solid','two','four','sixteen','random','gray','gray-random','gray-solid','gray-checker','gray-block','gray-stripes']:
                colors=[(rng.randrange(256),rng.randrange(256),rng.randrange(256)) for _ in range(16)]
                rgb=[]
                for i in range(w*h):
                    n={'solid':1,'two':2,'four':4,'sixteen':16}.get(mode)
                    rgb.append(colors[i%n] if n else tuple(rng.randrange(256) for _ in range(3)))
                if mode.startswith('gray'):
                    rgb=[(v,v,v) for v in [85*(rng.randrange(4) if mode=='gray-random' else
                                              2 if mode=='gray-solid' else
                                              (i%w+i//w)%2*3 if mode=='gray-checker' else
                                              (3 if i%w>=w//2 else 0) if mode=='gray-block' else
                                              (i%w//4)%4 if mode=='gray-stripes' else (i//3)%4)
                                            for i in range(w*h)]]
                # Padding in source rows verifies non-contiguous tiles.
                stride=w*4+12
                src=bytearray(stride*h)
                for y in range(h):
                    for x in range(w): src[y*stride+x*4:y*stride+x*4+4]=bytes((0,*rgb[y*w+x]))
                source=(C.c_ubyte*len(src)).from_buffer_copy(src)
                raw=(C.c_ubyte*(w*4))()
                lib.NXVNCEncodeRow(C.byref(f),source,raw,w)
                assert bytes(raw)[:w*f.bytes]==b''.join(wire_pixel(p,fmt) for p in rgb[:w])
                for enc,name in [(15,'NXVNCEncodeTRLE'),(5,'NXVNCEncodeHextile')]:
                    output=(C.c_ubyte*1030)(*([0xa5]*1030))
                    length=getattr(lib,name)(C.byref(f),source,stride,w,h,output)
                    if enc==5 and w==16 and h==16 and mode=='gray-checker':
                        assert output[0]==1 # complex tiles take bounded raw fallback
                    if enc==5 and w==16 and h==16 and mode=='gray-block':
                        assert length==4+2*f.bytes and output[0]==14
                    if enc==5 and w==16 and h==16 and mode=='gray-stripes':
                        assert length==8+4*f.bytes and output[0]==26
                    if enc==5 and mode=='gray-solid':
                        assert output[0]==2 # solid tiles remain compressed
                    assert 0<length<=1025 and bytes(output)[1025:]==b'\xa5'*5
                    stream=io.BytesIO(bytes(output)[:length])
                    decoded=decode_tile(stream.read,w,h,fmt,enc)
                    assert decoded==[wire_pixel(p,fmt,enc==15) for p in rgb],(fmt,w,h,mode,enc)
                    assert stream.tell()==length
    for width in range(1,18):
        for invert in [0,1]:
            for value in range(256):
                source=(C.c_ubyte*((width+3)//4))(*([value]*((width+3)//4)))
                output=(C.c_ubyte*(width*4+4))(*([0xa5]*(width*4+4)))
                lib.NXVNCExpandGray2(source,output,width,invert)
                expected=b''
                for x in range(width):
                    gray=((value>>(6-2*(x%4)))&3)*85
                    if invert: gray=255-gray
                    expected+=bytes((0,gray,gray,gray))
                assert bytes(output)==expected+b'\xa5'*4
    for fmt in [(32,24,1,255,255,255,16,16,0),(8,8,0,255,255,255,16,8,0),
                (32,24,1,0,255,255,16,8,0),(32,24,1,256,255,255,16,8,0)]:
        assert not lib.NXVNCSetFormat(C.byref(Format()),*fmt)
    print('PASS: raw/TRLE/Hextile round trips, 8 formats, edge tiles, palette/raw fallback, gray LUT, invalid formats')

class Client:
    def __init__(self,port):
        self.s=socket.create_connection(('127.0.0.1',port),timeout=5)
        assert self.read(12)==b'RFB 003.003\n'
        self.s.sendall(b'RFB 003.003\n'); assert self.read(4)==b'\0\0\0\1'
        self.s.sendall(b'\1'); init=self.read(24)
        self.width,self.height=struct.unpack('!HH',init[:4]); self.read(struct.unpack('!I',init[20:])[0])
        self.fmt=FORMATS[0]; self.wire_bytes=0
    def read(self,n):
        data=b''
        while len(data)<n:
            b=self.s.recv(n-len(data)); assert b,'unexpected disconnect'; data+=b
        self.wire_bytes=getattr(self,'wire_bytes',0)+n
        return data
    def format(self,fmt):
        self.fmt=fmt; bpp,depth,be,r,g,b,rs,gs,bs=fmt
        self.s.sendall(b'\0\0\0\0'+struct.pack('!BBBBHHHBBBxxx',bpp,depth,be,1,r,g,b,rs,gs,bs))
    def encodings(self,encs):
        self.s.sendall(struct.pack('!BBH',2,0,len(encs))+b''.join(struct.pack('!i',e) for e in encs))
    def update(self,inc=False,rect=(0,0,67,35),change=None):
        self.s.sendall(struct.pack('!BBHHHH',3,inc,*rect))
        return self.response(rect,change)
    def response(self,rect=(0,0,67,35),change=None):
        header=self.read(4); assert header[:2]==b'\0\0'
        count=struct.unpack('!H',header[2:])[0]; encs=[]; covered=set()
        for _ in range(count):
            x,y,w,h,enc=struct.unpack('!HHHHi',self.read(12)); encs.append(enc)
            assert x>=rect[0] and y>=rect[1] and x+w<=rect[0]+rect[2] and y+h<=rect[1]+rect[3]
            if enc==0:
                tile=[self.read(self.fmt[0]//8) for _ in range(w*h)]
                tiles=[(0,0,w,h,tile)]
            else:
                assert enc in (5,15); tiles=[]
                for ty in range(0,h,16):
                    for tx in range(0,w,16):
                        tw,th=min(16,w-tx),min(16,h-ty)
                        tiles.append((tx,ty,tw,th,decode_tile(self.read,tw,th,self.fmt,enc)))
            for tx,ty,tw,th,tile in tiles:
                for yy in range(th):
                    for xx in range(tw):
                        px,py=x+tx+xx,y+ty+yy; covered.add((px,py))
                        g=((px//8+py//8)%4)*85
                        changes=change if isinstance(change,list) else ([change] if change else [])
                        for cx,cy,value in changes:
                            if (px,py)==(cx,cy): g=value
                        assert tile[yy*tw+xx]==wire_pixel((g,g,g),self.fmt,enc==15),(px,py,enc)
        return count,encs,covered
    def close(self): self.s.close()

def protocol_tests(binary,folder,packed=False):
    changed=85 if packed else 17
    listener=socket.socket();listener.bind(('127.0.0.1',0));port=listener.getsockname()[1];listener.close()
    state=folder/'state';log=folder/'server.log'
    with log.open('w') as output:
        proc=subprocess.Popen([str(binary),str(port),str(state)]+(["packed"] if packed else []),stdout=output,stderr=output,
                              env={**os.environ,'NXVNC_PROFILE':'1'})
        try:
            for i in range(50):
                try: c=Client(port);break
                except ConnectionRefusedError: time.sleep(.05)
            else: raise AssertionError('server did not start')
            c.encodings([15,5,0]); assert c.update()[1]==[15]
            assert c.update(True)[0]==0
            state.write_text('65 34 '+str(changed))
            assert c.update(True,(0,0,32,32))[0]==0
            result=c.update(True,change=(65,34,changed));assert result[0]==1 and result[2]=={(65,34)}
            assert c.update(True,change=(65,34,changed))[0]==0
            state.write_text('')
            c.encodings([5,0]); assert c.update()[1]==[5]
            for fmt in FORMATS:
                c.format(fmt)
                for enc in [0,5,15]:
                    c.encodings([enc]);result=c.update();assert result[1]==[enc]
                    assert len(result[2])==67*35
            # Tight bounds inside a tile, across tiles, and adjacent spans.
            c.format(FORMATS[0]); c.encodings([0]); c.update()
            bound_value=170 if packed else changed
            for changes,expected in [([(10,5,bound_value)],{(10,5)}),
                                     ([(10,5,bound_value),(12,7,bound_value)],
                                      {(x,y) for x in range(10,13) for y in range(5,8)}),
                                     ([(31,5,bound_value),(32,5,bound_value)],{(31,5),(32,5)})]:
                state.write_text('\n'.join('%d %d %d'%point for point in changes))
                before=c.wire_bytes
                result=c.update(True,change=changes)
                assert result[0]==1 and result[2]==expected,result
                assert c.wire_bytes-before==16+4*len(expected)
                assert c.update(True,change=changes)[0]==0
                state.write_text(''); c.update()
            c.close()
            c=Client(port) # no encodings or format: raw defaults must reset
            result=c.update(True,(3,2,5,7));assert set(result[1])=={0} and len(result[2])==35
            assert c.update(True,(3,2,5,7))[0]==0
            result=c.update(True);assert len(result[2])>=67*35-35
            assert c.update(True)[0]==0
            assert c.update(False,(67,35,1,1))[0]==0
            c.format(FORMATS[2])
            assert c.update(True)[0]>0 # format change invalidates the snapshot
            # Unknown encodings fall back to raw, and malformed formats close
            # only this connection, leaving the listener available.
            c.encodings([123456,-239]); assert c.update()[1]==[0]
            c.s.sendall(b'\0\0\0\0'+struct.pack('!BBBBHHHBBBxxx',32,24,1,1,255,255,255,16,16,0))
            assert c.s.recv(1)==b''
            c.close()
            c=Client(port); assert c.update()[1]==[0]; c.close()
            c=Client(port)
            c.s.sendall(struct.pack('!BBHH',5,1,12,7))
            c.s.sendall(struct.pack('!BBHH',5,1,14,8))
            c.s.sendall(struct.pack('!BBHI',4,1,0,0xffe3))
            c.s.sendall(struct.pack('!BBHI',4,1,0,ord('c')))
            c.update(True) # Synchronize: preceding input messages were consumed.
            c.close() # Held key, modifier and mouse button must be released.
            c=Client(port); c.update(True); c.close()
        finally:
            proc.terminate();proc.wait(timeout=5)
    assert 'CAPTURE 3 2 5 7' in log.read_text()
    for field in ['refresh=','encode/buffer=','cache=','socket=']:
        assert field in log.read_text()
    events=[list(map(int,line.split()[1:])) for line in log.read_text().splitlines()
            if line.startswith('INPUT ')]
    assert [e[0] for e in events]==[5,1,6,12,10,12,11,2]
    assert events[0][1:3]==[12,7] and events[2][1:3]==[14,8]
    assert events[4][3:6]==[1<<18,0,3]
    print('PASS: real server handshake, negotiation, updates, partial dirty tracking, reconnect reset, empty rectangles, profiling')

def responsiveness_tests(binary,folder):
    def wait_for(predicate,timeout=3):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            if predicate(): return
            time.sleep(.005)
        raise AssertionError('timed out waiting for input service')
    for slow_reader in [False,True]:
        listener=socket.socket(); listener.bind(('127.0.0.1',0))
        port=listener.getsockname()[1]; listener.close()
        log=folder/('backpressure.log' if slow_reader else 'polling.log')
        state=folder/'input-state'; state.write_text('')
        env={**os.environ,'NXVNC_PROFILE':'1','NXVNC_MAX_FPS':'1'}
        env.pop('NXVNC_TEST_LARGE',None)
        if slow_reader: env['NXVNC_TEST_LARGE']='1'
        with log.open('w') as output:
            proc=subprocess.Popen([str(binary),str(port),str(state)],stdout=output,stderr=output,env=env)
            try:
                for _ in range(100):
                    try: c=Client(port); break
                    except ConnectionRefusedError: time.sleep(.02)
                else: raise AssertionError('server did not start')
                if slow_reader:
                    c.s.setsockopt(socket.SOL_SOCKET,socket.SO_RCVBUF,4096)
                    c.s.sendall(struct.pack('!BBHHHH',3,0,0,0,c.width,c.height))
                    assert c.read(4)==b'\0\0\0\1'
                    assert struct.unpack('!HHHHi',c.read(12))==(0,0,c.width,c.height,0)
                    # Stop reading an 8 MiB raw update. Input must still work.
                else:
                    c.update()
                    c.s.sendall(struct.pack('!BBHHHH',3,1,0,0,67,35))
                key=struct.pack('!BBHI',4,1,0,ord('a'))
                c.s.sendall(key[:3]); time.sleep(.05)
                assert 'INPUT ' not in log.read_text() # incomplete message stays buffered
                c.s.sendall(key[3:])
                wait_for(lambda: 'INPUT ' in log.read_text(),.7 if not slow_reader else 3)
                text=log.read_text()
                if slow_reader:
                    assert 'NXVNC: update ' not in text # output is still blocked
                else:
                    assert text.count('CAPTURE ')==1 # handled during polling delay
                    assert c.response()[0]==0
                c.close()
                c=Client(port) # a stalled/disconnected viewer must not wedge the server
                c.update(False,(0,0,67,35)); c.close()
            finally:
                proc.terminate(); proc.wait(timeout=5)
    print('PASS: fragmented input during rate-limit wait and blocked socket writes, stalled-reader disconnect/reconnect')

with tempfile.TemporaryDirectory(prefix='nxvnc-tests-') as temp:
    folder=Path(temp); library=folder/'encoding.dylib';binary=folder/'server'
    subprocess.run(['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror','-dynamiclib',
                    str(ROOT/'NXVNCEncoding.c'),'-o',str(library)],check=True)
    lib=C.CDLL(str(library))
    core_tests(lib)
    stubs=folder/'AppKit'; stubs.mkdir()
    (stubs/'AppKit.h').write_text((ROOT/'tests/capture_appkit_stub.h').read_text())
    (stubs/'NSGraphics.h').write_text('')
    subprocess.run(['clang','-O2','-Wall','-Wextra','-Werror','-Wno-missing-method-return-type',
                    '-Wno-unused-parameter','-I'+str(folder),'-I'+str(ROOT),'-framework','Foundation',
                    str(ROOT/'tests/test_capture.m'),str(ROOT/'NXVNCFramebuffer.m'),
                    str(ROOT/'NXVNCEncoding.c'),'-o',str(folder/'capture')],check=True)
    subprocess.run([str(folder/'capture')],check=True)
    cache_tests(lib)
    subprocess.run(['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror',
                    '-I'+str(ROOT),str(ROOT/'NXVNCInput.c'),
                    str(ROOT/'tests/test_input.c'),'-o',str(folder/'input')],check=True)
    subprocess.run([str(folder/'input')],check=True)
    subprocess.run(['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror',
                    '-DNXVNC_INPUT_NATIVE_TEST','-I'+str(ROOT),
                    str(ROOT/'NXVNCInput.c'),str(ROOT/'NXVNCInputNative.c'),
                    str(ROOT/'tests/test_input_native.c'),'-o',str(folder/'native-input')],check=True)
    subprocess.run([str(folder/'native-input')],check=True)
    subprocess.run(['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror',
                    '-DNXVNC_INPUT_INTEL_TEST','-I'+str(ROOT),
                    str(ROOT/'NXVNCInput.c'),str(ROOT/'tests/test_input.c'),
                    '-o',str(folder/'intel-translation')],check=True)
    subprocess.run([str(folder/'intel-translation')],check=True)
    subprocess.run(['cc','-std=c89','-pedantic','-Wall','-Wextra','-Werror',
                    '-DNXVNC_INPUT_INTEL_TEST','-I'+str(ROOT),
                    str(ROOT/'NXVNCInput.c'),str(ROOT/'NXVNCInputNative.c'),
                    str(ROOT/'tests/test_input_intel.c'),'-o',str(folder/'intel-input')],check=True)
    subprocess.run([str(folder/'intel-input')],check=True)
    for arch in ('m68k','intel'):
        subprocess.run(['clang','-Wall','-Wextra','-Werror','-DNXVNC_INPUT_DPS_TEST',
                        *(['-DNXVNC_INPUT_INTEL_TEST'] if arch=='intel' else []),
                        '-I'+str(ROOT),'-framework','Foundation',
                        str(ROOT/'NXVNCInputDPS.m'),str(ROOT/'tests/test_input_dps.m'),
                        '-o',str(folder/('dps-'+arch))],check=True)
        subprocess.run([str(folder/('dps-'+arch))],check=True)
    subprocess.run(['clang','-O2','-Wall','-Wextra','-Werror','-Wno-missing-method-return-type',
                    '-Wno-unused-parameter','-I'+str(ROOT),'-framework','Foundation',
                    str(ROOT/'tests/framebuffer.m'),str(ROOT/'NXVNCRFBServer.m'),
                    str(ROOT/'NXVNCEncoding.c'),str(ROOT/'NXVNCInput.c'),'-o',str(binary)],check=True)
    protocol_tests(binary,folder)
    protocol_tests(binary,folder,packed=True)
    responsiveness_tests(binary,folder)
