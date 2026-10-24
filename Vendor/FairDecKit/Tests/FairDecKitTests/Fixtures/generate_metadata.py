# Generates ZIP fixtures using synthetic credential/reference vectors only.
import io,json,struct,zipfile
from pathlib import Path
root=Path(__file__).resolve().parent
f=json.loads((root/'reference.json').read_text())['binaries'][0]
header=bytes.fromhex(f['header'])
binary=header+bytes(4096-len(header))+bytes.fromhex(f['ciphertext'])
class NonSeeking(io.BytesIO):
 def seekable(self): return False
 def seek(self,*args): raise OSError('Non-seekable fixture')
for force64 in [False,True]:
 stream=NonSeeking()
 with zipfile.ZipFile(stream,'w',compression=zipfile.ZIP_DEFLATED) as z:
  for name,data in [('Payload/Fixture.app/Fixture',binary),('Payload/Fixture.app/SC_Info/Fixture.sinf',bytes.fromhex(f['sinf'])),('Payload/Fixture.app/SC_Info/Fixture.supf',bytes.fromhex(f['supf'])),('Payload/Fixture.app/resource.txt',b'untouched'*300)]:
   info=zipfile.ZipInfo(name,(2001,2,3,4,5,6));info.compress_type=zipfile.ZIP_DEFLATED
   info.extra=struct.pack('<HH',0xcafe,5)+b'local'+struct.pack('<HH',0xbeef,4)+b'\x00\xffPK'
   info.comment=b'entry comment\x00\xff'+name.encode()
   info.external_attr=0o100751<<16
   with z.open(info,'w',force_zip64=force64) as file: file.write(data)
  z.comment=b'archive comment\x00\xff with opaque bytes'
 raw=bytearray(stream.getvalue())
 with zipfile.ZipFile(io.BytesIO(raw)) as z:
  for entry in z.infolist():
   # Keep different local/central extras and invalid original DOS timestamps.
   struct.pack_into('<HH',raw,entry.header_offset+10,0,0)
  pos=z.start_dir
  for entry in z.infolist():
   name,extra,comment=struct.unpack_from('<HHH',raw,pos+28)
   start=pos+46+name
   raw[start+4:start+9]=b'centr'
   struct.pack_into('<HH',raw,pos+12,0,0)
   pos+=46+name+extra+comment
 if force64:
  with zipfile.ZipFile(io.BytesIO(raw)) as z:
   pos=z.start_dir
   headers=[]
   for entry in z.infolist():
    name,extra,comment=struct.unpack_from('<HHH',raw,pos+28)
    part=bytearray(raw[pos:pos+46+name+extra+comment])
    for offset in [20,24,42]: struct.pack_into('<I',part,offset,0xffffffff)
    field=struct.pack('<HHQQQ',1,24,entry.file_size,entry.compress_size,entry.header_offset+13)
    part[46+name+extra:46+name+extra]=field
    struct.pack_into('<H',part,30,extra+len(field))
    headers.append(part)
    pos+=46+name+extra+comment
   directory=b''.join(headers)
   end=bytearray(raw[pos:])
   struct.pack_into('<I',end,12,len(directory))
   struct.pack_into('<I',end,16,z.start_dir+13)
   raw=bytearray(b'sample-prefix'+raw[:z.start_dir]+directory+end)
  with zipfile.ZipFile(io.BytesIO(raw)) as z:
   end_offset=len(raw)-22-len(z.comment)
   record=struct.pack('<IQHHIIQQQQ',0x06064b50,44,789,45,0,0,len(z.infolist()),len(z.infolist()),len(directory),z.start_dir)
   locator=struct.pack('<IIQI',0x07064b50,0,end_offset,1)
   struct.pack_into('<HHII',raw,end_offset+8,65535,65535,0xffffffff,0xffffffff)
   raw[end_offset:end_offset]=record+locator
 (root/f'metadata-{64 if force64 else 32}.zip').write_bytes(raw)
