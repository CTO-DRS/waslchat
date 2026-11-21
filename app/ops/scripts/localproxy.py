#!/usr/bin/env python3
# Local no-auth proxy on 127.0.0.1:18888 chaining to upstream HTTPS_PROXY (with auth)
import asyncio, base64, os, urllib.parse as u
p = u.urlparse(os.environ.get('HTTPS_PROXY') or os.environ.get('https_proxy'))
UH, UP = p.hostname, p.port
AUTH = base64.b64encode(f"{u.unquote(p.username or '')}:{u.unquote(p.password or '')}".encode()).decode()

async def pipe(r, w):
    try:
        while True:
            d = await r.read(65536)
            if not d: break
            w.write(d); await w.drain()
    except Exception: pass
    finally:
        try: w.close()
        except Exception: pass

async def handle(cr, cw):
    try:
        head = await cr.readuntil(b"\r\n\r\n")
    except Exception:
        cw.close(); return
    lines = head.split(b"\r\n")
    lines = [l for l in lines if not l.lower().startswith(b"proxy-authorization")]
    lines.insert(1, f"Proxy-Authorization: Basic {AUTH}".encode())
    ur, uw = await asyncio.open_connection(UH, UP)
    uw.write(b"\r\n".join(lines)); await uw.drain()
    if os.environ.get('LPDEBUG'):  # DEBUG
        first = await ur.readuntil(b"\r\n\r\n"); print(lines[0], first.split(b'\r\n')[0], flush=True); cw.write(first); await cw.drain()
    await asyncio.gather(pipe(cr, uw), pipe(ur, cw))

async def main():
    s = await asyncio.start_server(handle, '127.0.0.1', 18888)
    async with s: await s.serve_forever()
asyncio.run(main())
