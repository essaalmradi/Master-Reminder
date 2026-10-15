"""Prepare reviewed, attributed offline data. Input snapshots are in ../sources."""
from pathlib import Path
import json,hashlib,shutil,re
s=Path('../sources');r=Path('Sources/ReminderCore/Resources');r.mkdir(parents=True,exist_ok=True)
q=s.joinpath('quran-tanzil').read_text();shutil.copyfile(s/'quran-tanzil',r/'quran-tanzil.txt')
names={x['id']:x['name'] for x in json.loads((s/'quran-jsdelivr').read_text())}
(r/'surahs.json').write_text(json.dumps([{'number':i,'name':names[i]} for i in range(1,115)],ensure_ascii=False))
items=[]
h=json.loads((s/'hisn-github').read_text());idx=json.loads((s/'hisn-api').read_text(encoding='utf-8-sig'))['العربية']
for c in h:
 match=next((x for x in idx if x['TITLE']==c['category']),None)
 link='https://www.hisnmuslim.com/i/ar/'+str(match['ID']) if match else 'https://www.hisnmuslim.com/'
 kind='tasbih' if c['id'] in [129,130,131] else ('dua' if 'دعاء' in c['category'] or 'الدعاء' in c['category'] else 'dhikr')
 for a in c['array']:
  items.append(dict(id=f"hisn-{c['id']}-{a['id']}",category=kind,title=c['category'],text=a['text'],reference=f"حصن المسلم · {c['category']} · النص {a['id']}",sourceURL=link,repetitions=a['count'],chapter=c['id'],audioURL='https://raw.githubusercontent.com/rn0x/Adhkar-json/main'+a['audio'],bundledAudio='dhikr-sample' if a['filename']=='91' else None))
for a in json.loads((s/'nawawi').read_text())['hadiths']:
 n=a['hadithnumber']
 items.append(dict(id=f'nawawi-{n}',category='hadith',title=f'الحديث {n} · الأربعون النووية',text=a['text'],reference=f'الأربعون النووية · الحديث {n} · التخريج كما ورد في النص',sourceURL=f'https://sunnah.com/nawawi40:{n}',repetitions=1,chapter=n))
assert len(items)==309
(r/'library.json').write_text(json.dumps(items,ensure_ascii=False,separators=(',',':')))
credits='''مصادر المكتبة وحقوق الاستخدام\n\nالقرآن الكريم: مشروع تنزيل، النص البسيط الإصدار 1.1.\nhttps://tanzil.net/\nتم حفظ ملف المصدر كاملًا دون تغيير نصوص الآيات، مع إشعار الحقوق الأصلي في نهايته.\nأسماء السور: Quran JSON / Risan Bagja، CC-BY-4.0، https://github.com/risan/quran-json (npm 3.1.2).\n\nحصن المسلم: سعيد بن علي بن وهف القحطاني. 267 نصًا ضمن 132 بابًا.\nالنصوص والتسجيل التجريبي من https://github.com/rn0x/Adhkar-json المأخوذ من https://www.hisnmuslim.com/\nالناشر يجيز استخدام الملفات مجانًا؛ ملف README الأصلي مرفق. لا يُنسب أداء التسجيل إلى قارئ غير مذكور في المصدر.\n\nالأربعون النووية: 42 حديثًا مع التخريج داخل النص، من Hadith API (ara-nawawi).\nhttps://github.com/fawazahmed0/hadith-api — Unlicense. ليس كل ما في المجموعة بدرجة واحدة؛ يُرجع إلى التخريج في النص والمصدر.\n\nالخط العربي والأيقونة: ملفات هوية ماستر ليبيا التي قدمها مالك المشروع.\nInter وHepta Slab: SIL Open Font License 1.1، نصوص التراخيص مرفقة.\n'''
(r/'ContentCredits.txt').write_text(credits)
for a,b in [('hisn-readme','Hisn-Source-README.txt'),('nawawi-license','Hadith-LICENSE.txt'),('inter-license','Inter-OFL.txt'),('hepta-license','HeptaSlab-OFL.txt')]:shutil.copyfile(s/a,r/b)
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
for name in ['Inter','HeptaSlab']:
 f=TTFont(s/(name+'.ttf'));axes={'wght':400}
 if name=='Inter':axes['opsz']=14
 instantiateVariableFont(f,axes,inplace=True);f.save(r/(name+'.ttf'))
 print(name,[(n.nameID,n.toUnicode()) for n in f['name'].names if n.nameID==6][:1])
manifest={'counts':{'quranVerses':6236,'surahs':114,'hisnTexts':267,'hisnChapters':132,'nawawi':42},'retrieved':'2026-10-15','sourceSHA256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [s/'quran-tanzil',s/'hisn-github',s/'nawawi']}}
(r/'ContentManifest.json').write_text(json.dumps(manifest,indent=2))
print(manifest)
