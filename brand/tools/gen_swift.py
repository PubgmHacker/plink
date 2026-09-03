import json, re, math
import os, sys; HERE=os.path.dirname(os.path.abspath(__file__)); SRC=os.path.join(HERE,'..','source')
J=lambda p: json.load(open(os.path.join(SRC,p)))
mark=J('mark_paths.json'); glyphs=J('glyphs_fit.json'); grad=J('grad_fit.json')

TOK=re.compile(r'([MLCAZmlcaz])|(-?\d*\.?\d+(?:e-?\d+)?)')
def parse(d):
    toks=[t[0] or float(t[1]) for t in TOK.findall(d)]
    out=[]; i=0; cur=None; start=None; cmd=None
    while i<len(toks):
        if isinstance(toks[i],str): cmd=toks[i]; i+=1
        if cmd=='Z': out.append(('Z',)); cur=start; continue
        if cmd=='M': cur=(toks[i],toks[i+1]); start=cur; out.append(('M',cur)); i+=2; cmd='L'; continue
        if cmd=='L': cur=(toks[i],toks[i+1]); out.append(('L',cur)); i+=2; continue
        if cmd=='C':
            c1=(toks[i],toks[i+1]); c2=(toks[i+2],toks[i+3]); e=(toks[i+4],toks[i+5]); out.append(('C',c1,c2,e)); cur=e; i+=6; continue
        if cmd=='A':
            rx,ry,phi,fa,fs=toks[i:i+5]; e=(toks[i+5],toks[i+6]); i+=7
            out.extend(arc2cubics(cur,rx,ry,phi,int(fa),int(fs),e)); cur=e; continue
        raise ValueError(cmd)
    return out

def arc2cubics(p0,rx,ry,phi,fa,fs,p1):
    (x1,y1),(x2,y2)=p0,p1
    if rx==0 or ry==0 or (x1==x2 and y1==y2): return [('L',p1)]
    ph=math.radians(phi); c,s=math.cos(ph),math.sin(ph)
    dx,dy=(x1-x2)/2,(y1-y2)/2
    x1p= c*dx+s*dy; y1p=-s*dx+c*dy
    rx,ry=abs(rx),abs(ry)
    lam=x1p**2/rx**2+y1p**2/ry**2
    if lam>1: rx*=math.sqrt(lam); ry*=math.sqrt(lam)
    num=rx*rx*ry*ry-rx*rx*y1p*y1p-ry*ry*x1p*x1p
    den=rx*rx*y1p*y1p+ry*ry*x1p*x1p
    coef=(1 if fa!=fs else -1)*math.sqrt(max(0,num/den)) if den else 0
    cxp= coef*rx*y1p/ry; cyp=-coef*ry*x1p/rx
    cx=c*cxp-s*cyp+(x1+x2)/2; cy=s*cxp+c*cyp+(y1+y2)/2
    def ang(ux,uy,vx,vy):
        a=math.atan2(ux*vy-uy*vx, ux*vx+uy*vy); return a
    t1=ang(1,0,(x1p-cxp)/rx,(y1p-cyp)/ry)
    dt=ang((x1p-cxp)/rx,(y1p-cyp)/ry,(-x1p-cxp)/rx,(-y1p-cyp)/ry)
    if fs==0 and dt>0: dt-=2*math.pi
    if fs==1 and dt<0: dt+=2*math.pi
    n=max(1,math.ceil(abs(dt)/(math.pi/2)-1e-9)); seg=dt/n; out=[]
    def pt(t):
        ex,ey=rx*math.cos(t),ry*math.sin(t); return (c*ex-s*ey+cx, s*ex+c*ey+cy)
    def der(t):
        ex,ey=-rx*math.sin(t),ry*math.cos(t); return (c*ex-s*ey, s*ex+c*ey)
    for k in range(n):
        a=t1+k*seg; b=a+seg; kk=4/3*math.tan((b-a)/4)
        pa,pb=pt(a),pt(b); da,db=der(a),der(b)
        c1=(pa[0]+kk*da[0],pa[1]+kk*da[1]); c2=(pb[0]-kk*db[0],pb[1]-kk*db[1])
        out.append(('C',c1,c2,pb if k<n-1 else p1))
    return out

def bbox(cmds):
    xs=[];ys=[];cur=None
    for c in cmds:
        if c[0]=='M' or c[0]=='L': cur=c[1]; xs.append(cur[0]); ys.append(cur[1])
        elif c[0]=='C':
            p0=cur
            for t in [i/24 for i in range(1,25)]:
                mt=1-t
                x=mt**3*p0[0]+3*mt*mt*t*c[1][0]+3*mt*t*t*c[2][0]+t**3*c[3][0]
                y=mt**3*p0[1]+3*mt*mt*t*c[1][1]+3*mt*t*t*c[2][1]+t**3*c[3][1]
                xs.append(x); ys.append(y)
            cur=c[3]
    return min(xs),min(ys),max(xs),max(ys)

def swift_path(name, cmds, doc):
    L=[f'    /// {doc}', f'    static let {name}: Path = {{', '        var p = Path()']
    f=lambda v: f'{v:.2f}'
    for c in cmds:
        if c[0]=='M': L.append(f'        p.move(to: CGPoint(x: {f(c[1][0])}, y: {f(c[1][1])}))')
        elif c[0]=='L': L.append(f'        p.addLine(to: CGPoint(x: {f(c[1][0])}, y: {f(c[1][1])}))')
        elif c[0]=='C': L.append(f'        p.addCurve(to: CGPoint(x: {f(c[3][0])}, y: {f(c[3][1])}), control1: CGPoint(x: {f(c[1][0])}, y: {f(c[1][1])}), control2: CGPoint(x: {f(c[2][0])}, y: {f(c[2][1])}))')
        elif c[0]=='Z': L.append('        p.closeSubpath()')
    L+= ['        return p','    }()','']
    return '\n'.join(L)

A=parse(mark['A']); B=parse(mark['B'])
W=[]
for ch in 'PLINK': W+=parse(glyphs[ch]['d'])
ma=bbox(A); mb=bbox(B); mbox=(min(ma[0],mb[0]),min(ma[1],mb[1]),max(ma[2],mb[2]),max(ma[3],mb[3]))
wbox=bbox(W)
print('mark bbox',mbox,'word bbox',wbox)
print('cmds A',len(A),'B',len(B),'W',len(W))

def unit(pt,box): return ((pt[0]-box[0])/(box[2]-box[0]), (pt[1]-box[1])/(box[3]-box[1]))
def gline(pts):
    (x0,y0),(x1,y1)=pts[0][0],pts[-1][0]
    dx,dy=(x1-x0)/14,(y1-y0)/14
    return (x0-dx,y0-dy),(x1+dx,y1+dy)
def hexcol(h):
    h=h.lstrip('#'); return f'Color(red: {int(h[0:2],16)}/255, green: {int(h[2:4],16)}/255, blue: {int(h[4:6],16)}/255)'
def stops(pts):
    n=len(pts); return ',\n'.join(f'        Gradient.Stop(color: {hexcol(c)}, location: {(k+0.5)/n:.4f})' for k,(_,c) in enumerate(pts))
sA,eA=gline(grad['A']); sB,eB=gline(grad['B'])
uA0,uA1=unit(sA,mbox),unit(eA,mbox); uB0,uB1=unit(sB,mbox),unit(eB,mbox)
uR0,uR1=unit((613,138),mbox),unit((510,422),mbox)
print('A',uA0,uA1,'B',uB0,uB1,'rim',uR0,uR1)

src=f'''// Plink/Features/Brand/PlinkBrandGeometry.swift
//
// СГЕНЕРИРОВАНО из эталонного макета PLINK (1056×1008): контуры знака сняты с
// растра и восстановлены как кривые, вордмарк — как скруглённые многоугольники
// (дуги переведены в кубики). Координаты — в системе макета, поэтому знак,
// слово, градиенты и блики сходятся с эталоном 1:1. Правки — только через
// генератор (brand/tools/gen_swift.py), руками числа не трогать.

import SwiftUI

enum PlinkBrandGeometry {{
    /// Рамка знака (фигуры A и B вместе) в координатах макета.
    static let markBox = CGRect(x: {mbox[0]:.2f}, y: {mbox[1]:.2f}, width: {mbox[2]-mbox[0]:.2f}, height: {mbox[3]-mbox[1]:.2f})
    /// Рамка вордмарка PLINK в координатах макета.
    static let wordmarkBox = CGRect(x: {wbox[0]:.2f}, y: {wbox[1]:.2f}, width: {wbox[2]-wbox[0]:.2f}, height: {wbox[3]-wbox[1]:.2f})
    /// Рамка всего лок-апа (знак + слово + слоган + подвал), макет целиком.
    static let lockupBox = CGRect(x: 0, y: 0, width: 1056, height: 1008)

{swift_path('markA', A, 'Фигура A — стрелка «play», верхняя, светло-фиолетовая.')}
{swift_path('markB', B, 'Фигура B — нижняя капля-хвост, тёмно-фиолетовая.')}
{swift_path('wordmark', W, 'Слово PLINK: пять литер, каждая — замкнутый контур (P с противоположно ориентированным контуром-окошком).')}
    /// Вписывает путь, снятый в координатах макета, в прямоугольник с
    /// сохранением пропорций (aspect-fit, по центру).
    static func fit(_ path: Path, box: CGRect, in rect: CGRect) -> Path {{
        guard rect.width > 0, rect.height > 0, box.width > 0, box.height > 0 else {{ return Path() }}
        let s = min(rect.width / box.width, rect.height / box.height)
        let tx = rect.midX - (box.midX * s)
        let ty = rect.midY - (box.midY * s)
        let t = CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: tx, ty: ty)
        return path.applying(t)
    }}
}}

// MARK: - Формы

/// Фигура A знака (стрелка). Заполнять `PlinkBrandPalette.markA`.
struct PlinkMarkShapeA: Shape {{
    func path(in rect: CGRect) -> Path {{
        PlinkBrandGeometry.fit(PlinkBrandGeometry.markA, box: PlinkBrandGeometry.markBox, in: rect)
    }}
}}

/// Фигура B знака (хвост). Заполнять `PlinkBrandPalette.markB`.
struct PlinkMarkShapeB: Shape {{
    func path(in rect: CGRect) -> Path {{
        PlinkBrandGeometry.fit(PlinkBrandGeometry.markB, box: PlinkBrandGeometry.markBox, in: rect)
    }}
}}

/// Силуэт знака целиком (A ∪ B) — для монохромных и tinted-вариантов, масок и теней.
struct PlinkMarkSilhouette: Shape {{
    func path(in rect: CGRect) -> Path {{
        var p = PlinkBrandGeometry.fit(PlinkBrandGeometry.markA, box: PlinkBrandGeometry.markBox, in: rect)
        p.addPath(PlinkBrandGeometry.fit(PlinkBrandGeometry.markB, box: PlinkBrandGeometry.markBox, in: rect))
        return p
    }}
}}

/// Слово PLINK как контур. Заливать с `FillStyle(eoFill: true)` — окошко «P»
/// вырезано вторым контуром.
struct PlinkWordmarkShape: Shape {{
    func path(in rect: CGRect) -> Path {{
        PlinkBrandGeometry.fit(PlinkBrandGeometry.wordmark, box: PlinkBrandGeometry.wordmarkBox, in: rect)
    }}
}}

// MARK: - Палитра

/// Цвета бренда, снятые с эталона. НЕ зависят от темы приложения: знак меняет
/// цвет только вокруг себя (гало, фон), никогда внутри.
enum PlinkBrandPalette {{
    /// Фон макета — почти чёрный с каплей фиолетового.
    static let background = {hexcol('#010008')}
    /// Основной акцент бренда (цвет иконок подвала макета).
    static let accent = {hexcol('#8d55c8')}
    /// Верх стрелки — самый светлый фиолетовый.
    static let violetLight = {hexcol(grad['A'][0][1])}
    /// Низ стрелки — насыщенный индиго.
    static let violetDeep = {hexcol(grad['A'][-1][1])}
    /// Хвост — тёмный фиолет.
    static let plum = {hexcol(grad['B'][0][1])}
    /// Точки-разделители подвала.
    static let dot = {hexcol('#2c1f5a')}
    /// Серый подвала (PLAYER · MESSENGER · REELS).
    static let footerText = {hexcol('#bdbdbe')}

    /// Градиент фигуры A (8 опор, подгонка под растр эталона).
    static let markAStops: [Gradient.Stop] = [
{stops(grad['A'])}
    ]
    static let markAStart = UnitPoint(x: {uA0[0]:.4f}, y: {uA0[1]:.4f})
    static let markAEnd = UnitPoint(x: {uA1[0]:.4f}, y: {uA1[1]:.4f})
    static var markA: LinearGradient {{
        LinearGradient(stops: markAStops, startPoint: markAStart, endPoint: markAEnd)
    }}

    /// Градиент фигуры B.
    static let markBStops: [Gradient.Stop] = [
{stops(grad['B'])}
    ]
    static let markBStart = UnitPoint(x: {uB0[0]:.4f}, y: {uB0[1]:.4f})
    static let markBEnd = UnitPoint(x: {uB1[0]:.4f}, y: {uB1[1]:.4f})
    static var markB: LinearGradient {{
        LinearGradient(stops: markBStops, startPoint: markBStart, endPoint: markBEnd)
    }}

    /// Светлая внутренняя кромка стрелки: гаснет сверху вниз. Рисуется как
    /// обводка, обрезанная самой фигурой (внутренний штрих).
    static let rimStart = UnitPoint(x: {uR0[0]:.4f}, y: {uR0[1]:.4f})
    static let rimEnd = UnitPoint(x: {uR1[0]:.4f}, y: {uR1[1]:.4f})
    static var rim: LinearGradient {{
        LinearGradient(
            colors: [{hexcol('#eadfff')}.opacity(0.6), {hexcol('#eadfff')}.opacity(0.2)],
            startPoint: rimStart, endPoint: rimEnd
        )
    }}
    /// Толщина кромки в долях ширины знака (3 px на 350 px макета; видна половина).
    static let rimWidthRatio: CGFloat = 3.0 / {mbox[2]-mbox[0]:.2f}

    /// Вордмарк: сверху почти белый, книзу — холодный сиреневый.
    static var wordmark: LinearGradient {{
        LinearGradient(colors: [{hexcol('#f4f4f5')}, {hexcol('#c2bfdb')}], startPoint: .top, endPoint: .bottom)
    }}

    /// Слоган WATCH TOGETHER. ANYWHERE.: фиолет → индиго → голубой, слева направо.
    static var tagline: LinearGradient {{
        LinearGradient(
            stops: [
                Gradient.Stop(color: {hexcol('#8642d6')}, location: 0),
                Gradient.Stop(color: {hexcol('#6a49d1')}, location: 0.5),
                Gradient.Stop(color: {hexcol('#4189d2')}, location: 1),
            ],
            startPoint: .leading, endPoint: .trailing
        )
    }}
}}
'''
out=sys.argv[1] if len(sys.argv)>1 else os.path.join(HERE,'..','..','ios','Plink','Features','Brand','PlinkBrandGeometry.swift')
os.makedirs(os.path.dirname(out),exist_ok=True); open(out,'w').write(src); print('->',out)
print('lines', src.count('\n'))
