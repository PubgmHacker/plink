# -*- coding: utf-8 -*-
import sys, os, json, subprocess, shutil; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
from plkbrand import *
from PIL import Image
OUT=sys.argv[1] if len(sys.argv)>1 else os.path.join(HERE,'..','_build'); shutil.rmtree(OUT,ignore_errors=True)
def svg(w,h,defs,body,vb=None):
    vb=vb or (0,0,w,h)
    return '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" viewBox="%.2f %.2f %.2f %.2f"><defs>%s</defs>%s</svg>'%(w,h,vb[0],vb[1],vb[2],vb[3],defs,body)
# ---------- мастер-файлы бренда ----------
lock=open(os.path.join(HERE,'..','source','lockup_ref.svg')).read(); B=f'{OUT}/brand'
save_svg(lock,f'{B}/plink-lockup.svg'); render(lock,f'{B}/plink-lockup@2x.png',w=2112)
save_svg(lock.replace('<rect width="1056" height="1008" fill="#010008"/>',''),f'{B}/plink-lockup-transparent.svg')
bx0,by0,bx1,by1=MARK_BBOX; pad=10; vbm=(bx0-pad,by0-pad,bx1-bx0+2*pad,by1-by0+2*pad)
mark=svg(int(vbm[2]),int(vbm[3]),mark_defs(),mark_body(),vbm); save_svg(mark,f'{B}/plink-mark.svg'); render(mark,f'{B}/plink-mark-1024.png',h=1024)
save_svg(svg(int(vbm[2]),int(vbm[3]),'',mark_mono('#ffffff',0.55),vbm),f'{B}/plink-mark-mono-white.svg')
save_svg(svg(int(vbm[2]),int(vbm[3]),'',mark_mono('#000000',0.55),vbm),f'{B}/plink-mark-mono-black.svg')
wx0,wy0,wx1,wy1=WORD_BBOX; vbw=(wx0-8,wy0-8,wx1-wx0+16,wy1-wy0+16)
save_svg(svg(int(vbw[2]),int(vbw[3]),wordmark_defs(),wordmark_body(),vbw),f'{B}/plink-wordmark.svg')
# горизонтальный логотип: знак h=460 (как в эталоне), слово справа, капитель 0.42 высоты знака
sc=0.42*(by1-by0)/(wy1-wy0); gap=70; W=(bx1-bx0)+gap+(wx1-wx0)*sc; H=by1-by0
wm='<g transform="translate(%.2f %.2f) scale(%.5f) translate(%.2f %.2f)">%s</g>'%(bx0+(bx1-bx0)+gap,by0+(H-(wy1-wy0)*sc)/2,sc,-wx0,-wy0,wordmark_body())
hor=svg(int(W+2*pad),int(H+2*pad),mark_defs()+wordmark_defs(),mark_body()+wm,(bx0-pad,by0-pad,W+2*pad,H+2*pad))
save_svg(hor,f'{B}/plink-logo-horizontal.svg'); render(hor.replace('<defs>','<defs>').replace('</defs>','</defs><rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="%s"/>'%(bx0-pad,by0-pad,W+2*pad,H+2*pad,BG),1),f'{B}/plink-logo-horizontal-dark@2x.png',h=int(2*(H+2*pad)))
# ---------- iOS / iPadOS ----------
I=f'{OUT}/ios/AppIcon.appiconset'
render(icon_svg(1024),f'{I}/AppIcon-1024.png'); flatten(f'{I}/AppIcon-1024.png')
render(svg(1024,1024,mark_defs('i'),mark_centered(1024,0.60,-0.005,'i')),f'{I}/AppIcon-1024-dark.png')
render(svg(1024,1024,'<clipPath id="tcA"><path d="%s"/></clipPath>'%P['A'],'<g transform="%s">%s</g>'%(place((1024-0.6*1024*(bx1-bx0)/(by1-by0))/2,(1024-614.4)/2-5,614.4)[0],mark_gray())),f'{I}/AppIcon-1024-tinted.png')
json.dump({"images":[{"filename":"AppIcon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"},{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"AppIcon-1024-dark.png","idiom":"universal","platform":"ios","size":"1024x1024"},{"appearances":[{"appearance":"luminosity","value":"tinted"}],"filename":"AppIcon-1024-tinted.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}},open(f'{I}/Contents.json','w'),indent=2)
# ---------- Android ----------
A=f'{OUT}/android'
render(svg(432,432,bg_defs('i'),'<rect width="432" height="432" fill="url(#ibgG)"/>'),f'{A}/mipmap-xxxhdpi/ic_launcher_background.png')
render(svg(432,432,mark_defs('i'),mark_centered(432,0.48,0,'i')),f'{A}/mipmap-xxxhdpi/ic_launcher_foreground.png')
render(svg(432,432,'',mono_centered(432,0.48,'#ffffff',1.0)),f'{A}/mipmap-xxxhdpi/ic_launcher_monochrome.png')
for dpi,s in (('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)):
    render(icon_svg(s,rounded=0.2,margin=0.04,ratio=0.58),f'{A}/mipmap-{dpi}/ic_launcher.png')
    render(icon_svg(s,rounded=0.5,margin=0.04,ratio=0.50),f'{A}/mipmap-{dpi}/ic_launcher_round.png')
os.makedirs(f'{A}/mipmap-anydpi-v26',exist_ok=True)
ad='<?xml version="1.0" encoding="utf-8"?>\n<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@mipmap/ic_launcher_background"/>\n    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n</adaptive-icon>\n'
open(f'{A}/mipmap-anydpi-v26/ic_launcher.xml','w').write(ad); open(f'{A}/mipmap-anydpi-v26/ic_launcher_round.xml','w').write(ad)
render(icon_svg(512),f'{A}/play-store-512.png'); flatten(f'{A}/play-store-512.png')
# ---------- Windows ----------
Wd=f'{OUT}/windows'; sizes=(16,20,24,32,40,48,64,128,256)
for s in sizes: render(icon_svg(s,rounded=0.2,ratio=0.62 if s>=32 else 0.7),f'{Wd}/ico-src/{s}.png')
ims=[Image.open(f'{Wd}/ico-src/{s}.png') for s in sizes]
ims[-1].save(f'{Wd}/plink.ico',format='ICO',sizes=[(s,s) for s in sizes],append_images=ims[:-1]); shutil.rmtree(f'{Wd}/ico-src')
for name,(w,h) in {'Square44x44Logo':(44,44),'Square71x71Logo':(71,71),'Square150x150Logo':(150,150),'Square310x310Logo':(310,310),'Wide310x150Logo':(310,150),'StoreLogo':(50,50),'SplashScreen':(620,300)}.items():
    for scale in (100,200,400):
        W_,H_=w*scale//100,h*scale//100; hgt=H_*0.62; wid=hgt*(bx1-bx0)/(by1-by0)
        g,_=mark_at((W_-wid)/2,(H_-hgt)/2,hgt,'i')
        render(svg(W_,H_,mark_defs('i'),g),f'{Wd}/tiles/{name}.scale-{scale}.png')
# ---------- macOS ----------
M=f'{OUT}/macos/Plink.iconset'
def mac_svg(size):
    s=size/1024; r=824*s; off=(size-r)/2; rx=185.4*s
    defs=mark_defs('i')+bg_defs('i')+'<filter id="sh" x="-20%%" y="-20%%" width="140%%" height="140%%"><feDropShadow dx="0" dy="%.2f" stdDeviation="%.2f" flood-color="#000" flood-opacity="0.4"/></filter>'%(10*s,10*s)
    body='<rect x="%.2f" y="%.2f" width="%.2f" height="%.2f" rx="%.2f" fill="url(#ibgG)" filter="url(#sh)"/>'%(off,off,r,r,rx)
    body+='<g transform="translate(%.2f %.2f)">%s</g>'%(off,off,mark_centered(r,0.60,-0.005,'i'))
    return svg(size,size,defs,body)
for n,scale in ((16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)):
    render(mac_svg(n*scale),f'{M}/icon_{n}x{n}%s.png'%('@2x' if scale==2 else ''))
subprocess.run(['iconutil','-c','icns',M,'-o',f'{OUT}/macos/Plink.icns'],check=True)
# ---------- Linux ----------
L=f'{OUT}/linux/hicolor'
for s in (16,22,24,32,48,64,96,128,256,512): render(icon_svg(s,rounded=0.2,margin=0.04,ratio=0.6),f'{L}/{s}x{s}/apps/plink.png')
save_svg(icon_svg(512,rounded=0.2,margin=0.04,ratio=0.6),f'{L}/scalable/apps/plink.svg')
open(f'{OUT}/linux/plink.desktop','w').write('[Desktop Entry]\nType=Application\nName=Plink\nComment=Watch together. Anywhere.\nExec=plink %U\nIcon=plink\nCategories=AudioVideo;Video;Network;\nStartupWMClass=Plink\n')
# ---------- Web (лендинг) ----------
Wb=f'{OUT}/web'
for s in (16,32,48): render(icon_svg(s,rounded=0.2,ratio=0.62 if s>=32 else 0.7),f'{Wb}/favicon-{s}x{s}.png')
fi=[Image.open(f'{Wb}/favicon-{s}x{s}.png') for s in (16,32,48)]; fi[-1].save(f'{Wb}/favicon.ico',format='ICO',sizes=[(16,16),(32,32),(48,48)],append_images=fi[:-1])
render(icon_svg(180),f'{Wb}/apple-touch-icon.png'); flatten(f'{Wb}/apple-touch-icon.png')
for s in (192,512): render(icon_svg(s,ratio=0.5),f'{Wb}/android-chrome-{s}x{s}.png'); flatten(f'{Wb}/android-chrome-{s}x{s}.png')
save_svg(svg(int(vbm[2]),int(vbm[3]),'',mark_mono('#000000',1.0),vbm),f'{Wb}/safari-pinned-tab.svg')
# og-image 1200x630: локап (знак+слово+тэглайн, x171–974 y81–822) высотой 500
lx0,ly0,lx1,ly1=171,81,975,822; s=500/(ly1-ly0); w=(lx1-lx0)*s
inner=lock.split('<rect width="1056" height="1008" fill="#010008"/>',1)[1].rsplit('</svg>',1)[0]
defs_=lock.split('<defs>',1)[1].split('</defs>',1)[0]
# убрать футер (иконки/подписи ниже y=860) — режем клипом
og='<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630"><defs>%s<clipPath id="ogc"><rect x="150" y="60" width="860" height="775"/></clipPath></defs><rect width="1200" height="630" fill="%s"/><g transform="translate(%.2f %.2f) scale(%.5f) translate(%.2f %.2f)" clip-path="url(#ogc)">%s</g></svg>'%(defs_,BG,(1200-w)/2,65,s,-lx0,-ly0,inner.replace('<rect x="190" y="770"','<rect x="190" y="770"'))
render(og,f'{Wb}/og-image.png'); flatten(f'{Wb}/og-image.png')
json.dump({"name":"Plink","short_name":"Plink","description":"Watch together. Anywhere.","icons":[{"src":"/android-chrome-192x192.png","sizes":"192x192","type":"image/png","purpose":"any maskable"},{"src":"/android-chrome-512x512.png","sizes":"512x512","type":"image/png","purpose":"any maskable"}],"theme_color":"#010008","background_color":"#010008","display":"standalone","start_url":"/"},open(f'{Wb}/site.webmanifest','w'),indent=2)
# ---------- превью-лист ----------
tiles=[(f'{I}/AppIcon-1024.png',256),(f'{I}/AppIcon-1024-dark.png',256),(f'{I}/AppIcon-1024-tinted.png',256),(f'{A}/mipmap-xxxhdpi/ic_launcher_foreground.png',256),(f'{A}/mipmap-xxxhdpi/ic_launcher.png',192),(f'{A}/mipmap-xxxhdpi/ic_launcher_round.png',192),(f'{M}/icon_512x512.png',256),(f'{L}/512x512/apps/plink.png',256),(f'{Wd}/tiles/Square150x150Logo.scale-200.png',256),(f'{Wb}/favicon-32x32.png',32),(f'{Wb}/favicon-16x16.png',16),(f'{Wb}/og-image.png',600)]
sheet=Image.new('RGB',(1300,900),(60,60,70)); x=y=10
for p,sz in tiles:
    im=Image.open(p).convert('RGBA'); im.thumbnail((sz,sz)); 
    if x+im.width>1290: x=10; y+=270
    sheet.paste(im,(x,y),im); x+=im.width+14
sheet.save(os.path.join(OUT,'icons_sheet.png'))
n=sum(len(f) for _,_,f in os.walk(OUT)); print('файлов:',n); subprocess.run('du -sh %s/*'%OUT,shell=True)
