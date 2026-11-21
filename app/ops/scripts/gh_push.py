import os,base64,json,subprocess,sys,urllib.request
API="https://api.github.com"; OWNER="CTO-DRS"; REPO="wasl-chat"
def call(m,p,d=None):
    req=urllib.request.Request(API+p,method=m,data=json.dumps(d).encode() if d is not None else None,headers={"User-Agent":"wasl","Accept":"application/vnd.github+json"})
    try:
        with urllib.request.urlopen(req) as r: return r.status,json.loads(r.read() or b'{}')
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read() or b'{}')
s,r=call("GET",f"/repos/{OWNER}/{REPO}")
if s==404:
    s,r=call("POST","/user/repos",{"name":REPO,"private":True,"auto_init":True,"description":"Wasl Chat - Flutter + Supabase"}); print("create",s)
s,ref=call("GET",f"/repos/{OWNER}/{REPO}/git/ref/heads/main"); print("ref",s)
parent=ref["object"]["sha"]
root=sys.argv[1]; tree=[]
for dp,dn,fn in os.walk(root):
    for f in fn:
        full=os.path.join(dp,f); rel=os.path.relpath(full,root)
        b=base64.b64encode(open(full,'rb').read()).decode()
        s,bl=call("POST",f"/repos/{OWNER}/{REPO}/git/blobs",{"content":b,"encoding":"base64"})
        assert s==201,(rel,s,bl)
        mode="100755" if os.access(full,os.X_OK) and f in("gradlew",) else "100644"
        tree.append({"path":rel,"mode":mode,"type":"blob","sha":bl["sha"]})
s,t=call("POST",f"/repos/{OWNER}/{REPO}/git/trees",{"tree":tree}); assert s==201,t
s,c=call("POST",f"/repos/{OWNER}/{REPO}/git/commits",{"message":sys.argv[2],"tree":t["sha"],"parents":[parent]}); assert s==201,c
s,u=call("PATCH",f"/repos/{OWNER}/{REPO}/git/refs/heads/main",{"sha":c["sha"],"force":True}); print("push",s,c["sha"])
