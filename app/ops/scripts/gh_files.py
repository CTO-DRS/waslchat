# usage: gh_files.py OWNER/REPO BRANCH "msg" ROOT file1 [file2 ...]  (overwrites listed files on branch, keeps the rest)
import base64,json,sys,urllib.request
API="https://api.github.com"; REPO,BR,MSG,ROOT=sys.argv[1:5]; FILES=sys.argv[5:]
def call(m,p,d=None):
    req=urllib.request.Request(API+p,method=m,data=json.dumps(d).encode() if d is not None else None,headers={"User-Agent":"wasl","Accept":"application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r: return r.status,json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read() or b'{}')
s,ref=call("GET",f"/repos/{REPO}/git/ref/heads/{BR}"); assert s==200,ref; parent=ref["object"]["sha"]
s,pc=call("GET",f"/repos/{REPO}/git/commits/{parent}"); base=pc["tree"]["sha"]
tree=[]
for f in FILES:
    assert not f.startswith("secrets")
    s,bl=call("POST",f"/repos/{REPO}/git/blobs",{"content":base64.b64encode(open(ROOT+"/"+f,'rb').read()).decode(),"encoding":"base64"})
    assert s==201,(f,s,bl); tree.append({"path":f,"mode":"100644","type":"blob","sha":bl["sha"]})
s,t=call("POST",f"/repos/{REPO}/git/trees",{"base_tree":base,"tree":tree}); assert s==201,t
s,c=call("POST",f"/repos/{REPO}/git/commits",{"message":MSG,"tree":t["sha"],"parents":[parent]}); assert s==201,c
s,u=call("PATCH",f"/repos/{REPO}/git/refs/heads/{BR}",{"sha":c["sha"]}); print("push",REPO,BR,s,c["sha"][:8],len(tree),"files")
