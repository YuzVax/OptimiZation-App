"""Recolor original purple logo, preserving alpha/shape. Requires Pillow.
Usage: python3 RecolorLogo.py /path/to/original/logo.png --output-dir /path/to/v6
"""
from pathlib import Path
import argparse,colorsys,hashlib
from PIL import Image
a=argparse.ArgumentParser();a.add_argument('original',type=Path);a.add_argument('--output-dir',type=Path,required=True);args=a.parse_args()
im=Image.open(args.original).convert('RGBA');alpha=im.getchannel('A').tobytes();out=[];count=0
hue=colorsys.rgb_to_hsv(1,148/255,28/255)[0]
for rr,g,b,a in im.getdata():
 h,s,v=colorsys.rgb_to_hsv(rr/255,g/255,b/255)
 if a>0 and s>.08 and 235<=h*360<=335:
  rr,g,b=(round(c*255) for c in colorsys.hsv_to_rgb(hue,s,v));count+=1
 out.append((rr,g,b,a))
im.putdata(out);assert im.getchannel('A').tobytes()==alpha
args.output_dir.mkdir(parents=True,exist_ok=True);im.save(args.output_dir/'logo.png',optimize=True)
im.save(args.output_dir/'logo.ico',format='ICO',sizes=[(n,n) for n in (16,20,24,32,40,48,64,96,128,256)])
print('Pixels recolored:',count,'alpha SHA256:',hashlib.sha256(alpha).hexdigest())
