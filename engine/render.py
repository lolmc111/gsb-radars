#!/usr/bin/env python3
"""Inject digest data into the page template.
usage: render.py <template.html> <items.json> <meta.json> <out.html> [out.day.json]
The optional 5th output is the same data with images stripped, for the page db (days/<date>).
meta: {title, window, groupsRead, messageCount, footer}"""
import json,sys
t,itf,mf,o=sys.argv[1:5]
day=sys.argv[5] if len(sys.argv)>5 else None
D=json.load(open(mf)); D['items']=json.load(open(itf))
d=json.dumps(D,ensure_ascii=False).replace('</','<\\/')
open(o,'w').write(open(t).read().replace('__DATA__',d))
if day:
    import copy
    E=copy.deepcopy(D)
    for it in E['items']:
        for c in it.get('context',[]): c['img']=None
    json.dump(E,open(day,'w'),ensure_ascii=False)
