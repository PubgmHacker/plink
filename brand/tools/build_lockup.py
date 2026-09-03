import os, sys
HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,'..','source'); os.chdir(SRC); sys.path.insert(0,HERE)
BUILD=os.path.join(HERE,'..','_build'); os.makedirs(BUILD,exist_ok=True)
# -*- coding: utf-8 -*-
"""Сборка векторного локапа PLINK в координатах эталона 1056x1008."""
import json, math, subprocess
from textfit import load
P=json.load(open('mark_paths.json')); GF=json.load(open('glyphs_fit.json'))
def glyph_items(J,text,size,tracking,Xs):
    G={g['ch']:g for g in J['glyphs']}; sc=size/J['size']; out=[]
    for w,X in zip(text.split(' '),Xs):
        x=X
        for i,ch in enumerate(w):
            out.append((G[ch]['d'],x,sc)); x+=G[ch]['adv']*sc+tracking
    return out
def paths(items,y,fill):
    return ''.join('<path d="%s" transform="translate(%.3f %.3f) scale(%.5f)" fill="%s"/>'%(d,x,y,sc,fill) for d,x,sc in items if d)
tag=glyph_items(load('tag_med.json'),'WATCH TOGETHER. ANYWHERE.',45.14,3.84,[193.6,388.6,683.4])
foot=glyph_items(load('foot_semi.json'),'PLAYER MESSENGER REELS',32.33,0.29,[248.9,530.1,880.6])
IC='#8d55c8'; SW=5.8
def tri(p1,p2,p3,r): return '<path d="M%.2f %.2fL%.2f %.2fL%.2f %.2fZ" fill="%s" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'%(p1+p2+p3+(IC,IC,r))
icons=[]
icons.append('<circle cx="199.5" cy="915" r="24.75" fill="none" stroke="%s" stroke-width="%.1f"/>'%(IC,SW))
icons.append(tri((191.5,904),(191.5,926),(210.5,915),3))
a1,a2=math.radians(160),math.radians(105); cx,cy,rx,ry=482,912.5,23.75,21.25
p1=(cx+rx*math.cos(a1),cy+ry*math.sin(a1)); p2=(cx+rx*math.cos(a2),cy+ry*math.sin(a2))
icons.append('<path d="M458 937 L%.2f %.2f A%.2f %.2f 0 1 1 %.2f %.2f Z" fill="none" stroke="%s" stroke-width="%.1f" stroke-linejoin="round"/>'%(p1+(rx,ry)+p2+(IC,SW)))
icons.append('<rect x="810.25" y="891.25" width="43.5" height="46.5" rx="8" fill="none" stroke="%s" stroke-width="%.1f"/>'%(IC,SW))
icons.append('<path d="M810.25 905H853.75M824.7 891.25V905M839.3 891.25V905" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="butt"/>'%(IC,SW))
icons.append(tri((826.5,916.2),(826.5,926.3),(838.3,921.25),2.2))
dots='<circle cx="410" cy="914.5" r="4" fill="#2c1f5a"/><circle cx="762.5" cy="914.5" r="4" fill="#2c1f5a"/>'
GA=json.load(open('grad_fit.json'))
def grad(id_,stops):
    (x0,y0),_=stops[0]; (x7,y7),_=stops[-1]; dx,dy=(x7-x0)/14,(y7-y0)/14
    s=''.join('<stop offset="%.4f" stop-color="%s"/>'%((k+0.5)/8,c) for k,(_,c) in enumerate(stops))
    return '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f">%s</linearGradient>'%(id_,x0-dx,y0-dy,x7+dx,y7+dy,s)
defs=grad('gA',GA['A'])+grad('gB',GA['B'])
defs+='<linearGradient id="gW" gradientUnits="userSpaceOnUse" x1="0" y1="594.6" x2="0" y2="721.4"><stop offset="0" stop-color="#f4f4f5"/><stop offset="1" stop-color="#c2bfdb"/></linearGradient>'
defs+='<linearGradient id="gT" gradientUnits="userSpaceOnUse" x1="197" y1="0" x2="967" y2="0"><stop offset="0" stop-color="#8642d6"/><stop offset="0.5" stop-color="#6a49d1"/><stop offset="1" stop-color="#4189d2"/></linearGradient>'
defs+='<linearGradient id="gR" gradientUnits="userSpaceOnUse" x1="613" y1="138" x2="510" y2="422"><stop offset="0" stop-color="#eadfff" stop-opacity="0.6"/><stop offset="1" stop-color="#eadfff" stop-opacity="0.2"/></linearGradient>'
defs+='<clipPath id="cA"><path d="%s"/></clipPath>'%P['A']
body='<rect width="1056" height="1008" fill="#010008"/>'
body+='<path d="%s" fill="url(#gA)"/><path d="%s" fill="none" stroke="url(#gR)" stroke-width="3" clip-path="url(#cA)"/>'%(P['A'],P['A'])
body+='<path d="%s" fill="url(#gB)"/>'%P['B']
body+='<g fill="url(#gW)">'+''.join('<path d="%s"/>'%GF[g]['d'] for g in 'PLINK')+'</g>'
defs+='<clipPath id="cT">'+''.join('<path d="%s" transform="translate(%.3f %.3f) scale(%.5f)"/>'%(d,x,813.3,sc) for d,x,sc in tag if d)+'</clipPath>'
body+='<rect x="190" y="770" width="785" height="55" fill="url(#gT)" clip-path="url(#cT)"/>'
body+=paths(foot,926.3,'#bdbdbe')+''.join(icons)+dots
svg='<svg xmlns="http://www.w3.org/2000/svg" width="1056" height="1008" viewBox="0 0 1056 1008"><defs>%s</defs>%s</svg>'%(defs,body)
open('lockup_ref.svg','w').write(svg); subprocess.run(['rsvg-convert','-o',os.path.join(BUILD,'lockup_ref.png'),'lockup_ref.svg'],check=True)
from PIL import Image, ImageChops
ref=Image.open('reference.png').convert('RGB'); ren=Image.open(os.path.join(BUILD,'lockup_ref.png')).convert('RGB')
c=Image.new('RGB',(1056*2+8,1008),(40,40,40)); c.paste(ref,(0,0)); c.paste(ren,(1064,0)); c.save(os.path.join(BUILD,'cmp_lockup.png'))
c.resize((1060,504),Image.LANCZOS).save(os.path.join(BUILD,'cmp_lockup_small.png'))
Image.new('RGB',(1056,300)).paste(ref.crop((150,760,1000,960)),(0,0))
row=Image.new('RGB',(850,404),(40,40,40)); row.paste(ref.crop((150,760,1000,960)),(0,0)); row.paste(ren.crop((150,760,1000,960)),(0,204)); row.save(os.path.join(BUILD,'cmp_bottom.png'))
print('ok')
