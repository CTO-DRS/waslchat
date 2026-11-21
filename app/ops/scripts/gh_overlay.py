# usage: gh_overlay.py OWNER/REPO "msg" localdir:prefix [localdir:prefix ...]  (adds/overwrites files, keeps the rest)
import os,base64,json,sys,urllib.request
API="https://api.github.com"; REPO=sys.argv[1]
def call(m,p,d=None):
    req=urllib.request.Request(API+p,method=m,data=json.dumps(d).encode() if d is not None else None,headers={"User-Agent":"wasl","Accept":"application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r: return r.status,json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read() or b'{}')
s,ref=call("GET",f"/repos/{REPO}/git/ref/heads/main"); parent=ref["object"]["sha"]
s,pc=call("GET",f"/repos/{REPO}/git/commits/{parent}"); base=pc["tree"]["sha"]
tree=[]
for spec in sys.argv[3:]:
    root,prefix=spec.split(":",1)
    for dp,dn,fn in os.walk(root):
        for f in fn:
            full=os.path.join(dp,f); rel=os.path.join(prefix,os.path.relpath(full,root)).lstrip("/")
            s,bl=call("POST",f"/repos/{REPO}/git/blobs",{"content":base64.b64encode(open(full,'rb').read()).decode(),"encoding":"base64"})
            assert s==201,(rel,s,bl); tree.append({"path":rel,"mode":"100644","type":"blob","sha":bl["sha"]})
s,t=call("POST",f"/repos/{REPO}/git/trees",{"base_tree":base,"tree":tree}); assert s==201,t
s,c=call("POST",f"/repos/{REPO}/git/commits",{"message":sys.argv[2],"tree":t["sha"],"parents":[parent]}); assert s==201,c
s,u=call("PATCH",f"/repos/{REPO}/git/refs/heads/main",{"sha":c["sha"]}); print("push",s,c["sha"],len(tree),"files")
