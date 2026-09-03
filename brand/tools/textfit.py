# -*- coding: utf-8 -*-
"""Раскладка строки из глифов CoreText: размер по высоте капители, трекинг по ширине слов."""
import json, re, numpy as np
def load(path): return json.load(open(path))
def layout(J, size, words_ext, y_base, gap_word=None):
    """words_ext: [(x_start,x_end)] по словам эталона; трекинг подбирается один на всю строку.
    Возвращает список (glyph d, x, scale) и трекинг."""
    sc=size/J['size']; G=J['glyphs']
    words=[]; cur=[]
    for g in G:
        if g['ch']==' ': words.append(cur); cur=[]
        else: cur.append(g)
    words.append(cur)
    # трекинг t: ширина слова = sum(adv)*sc - (adv_last - ink_x1_last)*sc - ink_x0_first*sc + t*(n-1)
    ts=[]
    for w,(xa,xb) in zip(words,words_ext):
        ink=(sum(g['adv'] for g in w)-(w[-1]['adv']-w[-1]['x1'])-w[0]['x0'])*sc
        ts.append(((xb-xa)-ink)/(len(w)-1))
    t=float(np.mean(ts))
    out=[]
    for w,(xa,xb) in zip(words,words_ext):
        x=xa-w[0]['x0']*sc
        for g in w:
            out.append((g['d'],x,sc)); x+=g['adv']*sc+t
    return out,t,ts
def svg_group(items,y_base,fill='white',extra=''):
    parts=[]
    for d,x,sc in items:
        if not d: continue
        parts.append('<path d="%s" transform="translate(%.3f %.3f) scale(%.5f)" fill="%s"/>'%(d,x,y_base,sc,fill))
    return '<g %s>%s</g>'%(extra,''.join(parts))
