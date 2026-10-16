#!/usr/bin/env python3
"""Build digest page data from a raw export + item specs.
usage: build.py <raw_dir> <specs.json> <out.json>
specs: [{id, raw?(raw dir of the day the source messages were exported; defaults to <raw_dir>), section(action|mention|core|opp|social), title, detail, deadline(YYYY-MM-DD|null), links:[{label,url}], tag?, jid, pat:[substrings of source messages], ctx?:[{ts,who,text}] (email items: pre-built context, no pat needed)}]
"""
import json,glob,os,re,sys,base64
raw,specf,outf=sys.argv[1:4]
_cache={}
def load(rd):
    if rd not in _cache:
        d={}
        for f in glob.glob(rd+'/*@g.us.json'):
            for m in (json.load(open(f)) or []):
                d.setdefault(m['chat_jid'],[]).append(m)
        for k in d: d[k].sort(key=lambda m:m['timestamp'])
        _cache[rd]=d
    return _cache[rd]
def clean(t):
    t=(t or '').strip()
    return '' if re.fullmatch(r'[A-Za-z0-9+/=]{20,}',t) or re.fullmatch(r'[0-9A-F]{16,}',t) else t
out=[];budget=[9_000_000]
for s in json.load(open(specf)):
    rd=s.get('raw') or raw
    L=load(rd).get(s['jid'],[])
    idx=[i for i,m in enumerate(L) if any(p.lower() in (m.get('text') or '').lower() for p in s.get('pat',[]))]
    if not idx and not s.get('ctx'): print('NOMATCH',s['id'],file=sys.stderr)
    ctx=[]
    if idx:
        for i in range(max(0,min(idx)-5),min(len(L),max(idx)+6)):
            m=L[i]; t=m.get('message_type')
            if t in ('system','reaction','group_event'): continue
            txt=clean(m.get('text'))
            img=None
            if t=='image':
                jp=f"{rd}/media/{m['event_id'].replace(':','_')}.jpg"
                if os.path.exists(jp) and os.path.getsize(jp)<budget[0]:
                    budget[0]-=os.path.getsize(jp); img='data:image/jpeg;base64,'+base64.b64encode(open(jp,'rb').read()).decode()
            if not txt and not img and t=='text': continue
            ctx.append({'ts':m['timestamp'],'who':'You' if m.get('from_me') else (m.get('sender_name') or 'Unknown'),'me':bool(m.get('from_me')),'text':txt,'type':t,'media':m.get('media_title') if t=='document' else None,'img':img,'src':i in idx})
    if not idx and s.get('ctx'):
        # email (or other non-WhatsApp) items carry their own pre-built context: [{ts,who,text}]
        ctx=[{'ts':c.get('ts',''),'who':c.get('who',''),'me':False,'text':c.get('text',''),'type':'text','media':None,'img':None,'src':True} for c in s['ctx']]
    r={k:v for k,v in s.items() if k not in('pat','ctx')}
    r['group']=(L[0]['chat_name'] if L else s.get('group','')); r['context']=ctx
    out.append(r)
json.dump(out,open(outf,'w'),ensure_ascii=False)
print(len(out),'items')
