# -*- coding: utf-8 -*-
"""Общий модуль: знак, словесный знак, тэглайн и футер PLINK как SVG-фрагменты в координатах эталона (1056x1008)."""
import json, math, subprocess, os
import numpy as np
from PIL import Image
import os
D=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','source')
P=json.load(open(f'{D}/mark_paths.json')); GA=json.load(open(f'{D}/grad_fit.json')); GF=json.load(open(f'{D}/glyphs_fit.json'))
_m=np.asarray(Image.open(f'{D}/mask.png').convert('RGB')); _u=(_m[:,:,0]>128)|(_m[:,:,1]>128)
_ys,_xs=np.where(_u); MARK_BBOX=(float(_xs.min()),float(_ys.min()),float(_xs.max()+1),float(_ys.max()+1))
WORD_BBOX=(215.0,594.6,880.0,721.4)
BG='#010008'
def _grad(id_,stops):
    (x0,y0),_=stops[0]; (x7,y7),_=stops[-1]; dx,dy=(x7-x0)/14,(y7-y0)/14
    s=''.join('<stop offset="%.4f" stop-color="%s"/>'%((k+0.5)/8,c) for k,(_,c) in enumerate(stops))
    return '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f">%s</linearGradient>'%(id_,x0-dx,y0-dy,x7+dx,y7+dy,s)
def mark_defs(p=''):
    return (_grad(p+'gA',GA['A'])+_grad(p+'gB',GA['B'])
      +'<linearGradient id="%sgR" gradientUnits="userSpaceOnUse" x1="613" y1="138" x2="510" y2="422"><stop offset="0" stop-color="#eadfff" stop-opacity="0.6"/><stop offset="1" stop-color="#eadfff" stop-opacity="0.2"/></linearGradient>'%p
      +'<clipPath id="%scA"><path d="%s"/></clipPath>'%(p,P['A']))
def mark_body(p=''):
    return ('<path d="%s" fill="url(#%sgA)"/><path d="%s" fill="none" stroke="url(#%sgR)" stroke-width="3" clip-path="url(#%scA)"/><path d="%s" fill="url(#%sgB)"/>'%(P['A'],p,P['A'],p,p,P['B'],p))
def mark_mono(color='#ffffff',opB=1.0):
    return '<path d="%s" fill="%s"/><path d="%s" fill="%s" fill-opacity="%.2f"/>'%(P['A'],color,P['B'],color,opB)
def mark_gray():
    """Для tinted-иконки iOS: светлота как у цветного знака."""
    return '<path d="%s" fill="#d9d9de"/><path d="%s" fill="none" stroke="#ffffff" stroke-opacity="0.5" stroke-width="3" clip-path="url(#tcA)"/><path d="%s" fill="#6b6b74"/>'%(P['A'],P['A'],P['B'])
def place(x,y,h,bbox=None):
    """transform, ставящий bbox (по умолчанию знак) верхним-левым углом в (x,y) с высотой h; возвращает (transform, ширина)."""
    bx0,by0,bx1,by1=bbox or MARK_BBOX; s=h/(by1-by0)
    return 'translate(%.4f %.4f) scale(%.6f) translate(%.4f %.4f)'%(x,y,s,-bx0,-by0), (bx1-bx0)*s
def mark_at(x,y,h,p=''):
    t,w=place(x,y,h); return '<g transform="%s">%s</g>'%(t,mark_body(p)), w
def mark_centered(size,ratio=0.60,dy=0.0,p=''):
    bx0,by0,bx1,by1=MARK_BBOX; h=size*ratio; w=h*(bx1-bx0)/(by1-by0)
    return mark_at((size-w)/2,(size-h)/2+dy*size,h,p)[0]
def mono_centered(size,ratio,color='#fff',opB=1.0,dy=0.0):
    bx0,by0,bx1,by1=MARK_BBOX; h=size*ratio; w=h*(bx1-bx0)/(by1-by0)
    t,_=place((size-w)/2,(size-h)/2+dy*size,h); return '<g transform="%s">%s</g>'%(t,mark_mono(color,opB))
def wordmark_defs(p=''):
    return '<linearGradient id="%sgW" gradientUnits="userSpaceOnUse" x1="0" y1="594.6" x2="0" y2="721.4"><stop offset="0" stop-color="#f4f4f5"/><stop offset="1" stop-color="#c2bfdb"/></linearGradient>'%p
def wordmark_body(p='',fill=None):
    return '<g fill="%s">'%(fill or 'url(#%sgW)'%p)+''.join('<path d="%s"/>'%GF[g]['d'] for g in 'PLINK')+'</g>'
def bg_defs(p='',size=1024):
    return ('<radialGradient id="%sbgG" cx="0.5" cy="0.36" r="0.72"><stop offset="0" stop-color="#2b1160"/><stop offset="0.55" stop-color="#120735"/><stop offset="1" stop-color="#06031a"/></radialGradient>'%p)
def icon_svg(size,rounded=None,margin=0.0,ratio=0.60,dy=-0.005,transparent=False):
    """Квадратная иконка: фон (скруглённый прямоугольник при rounded=доля радиуса) + знак по центру."""
    inner=size*(1-2*margin); off=size*margin
    defs=mark_defs('i')+bg_defs('i')
    body=''
    if not transparent:
        rx=(rounded or 0)*inner
        body+='<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="url(#ibgG)"/>'%(off,off,inner,inner,rx)
    g=mark_centered(inner,ratio,dy,'i'); body+='<g transform="translate(%.2f %.2f)">%s</g>'%(off,off,g)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs>%s</defs>%s</svg>'%(size,size,size,size,defs,body)
def render(svg,path,w=None,h=None):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    tmp=path+'.svg'; open(tmp,'w').write(svg)
    cmd=['rsvg-convert','-o',path]+(['-w',str(w)] if w else [])+(['-h',str(h)] if h else [])+[tmp]
    subprocess.run(cmd,check=True); os.remove(tmp)
def save_svg(svg,path):
    os.makedirs(os.path.dirname(path),exist_ok=True); open(path,'w').write(svg)
def flatten(path):
    """Убрать альфу (для iOS/apple-touch/og): подложить фон бренда."""
    im=Image.open(path).convert('RGBA'); bg=Image.new('RGBA',im.size,(1,0,8,255)); bg.alpha_composite(im); bg.convert('RGB').save(path)
