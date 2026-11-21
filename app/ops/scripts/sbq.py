import json,sys,urllib.request
q=sys.stdin.read()
req=urllib.request.Request("https://api.supabase.com/v1/projects/hplzbillnbdjtufazrlp/database/query",data=json.dumps({"query":q}).encode(),headers={"Content-Type":"application/json","User-Agent":"hark"},method="POST")
try:
  print(urllib.request.urlopen(req,timeout=90).read().decode()[:6000])
except urllib.error.HTTPError as e: print(e.code,e.read().decode()[:3000])
