import socket, subprocess, sys, time, threading, os
S = os.path.dirname(os.path.abspath(__file__))
srv = subprocess.Popen(["julia", "+1.13", f"--project={S}/http2env", "--threads=2,1", f"{S}/h2server.jl"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
print(srv.stdout.readline().strip())
def stat(gc=False):
    srv.stdin.write(("gc" if gc else "s") + "\n"); srv.stdin.flush(); return srv.stdout.readline().strip()
def conn(): return socket.create_connection(("127.0.0.1", 8811))
def answer(s, seconds=10):
    s.settimeout(seconds); data = b""
    try:
        while True:
            d = s.recv(65536)
            if not d: break
            data += d
            if b"\r\n\r\n" in data and (b"Content-Length: 0" in data or len(data.split(b"\r\n\r\n",1)[1]) > 0): break
    except socket.timeout: data += b" [TIMED OUT WAITING]"
    except OSError as e: data += f" [{type(e).__name__}]".encode()
    return data.decode(errors="replace").replace("\r\n", " | ")[:170]
def timed(f):
    t = time.time(); r = f(); return f"{time.time()-t:.1f} s: {r}"
print("start:", stat(gc=True))
# 1. ordinary request
s = conn(); s.sendall(b"POST /api HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\nhello"); print("1 small request      ", answer(s)); s.close()
# 2. over the 64 KB limit, declared, whole body sent
body = b"x" * 12_000_000
def over():
    s = conn(); s.sendall(b"POST /api HTTP/1.1\r\nHost: x\r\nContent-Length: %d\r\n\r\n" % len(body))
    try: s.sendall(body)
    except OSError as e: return "send failed part way: " + type(e).__name__ + " | " + answer(s, 3)
    r = answer(s); s.close(); return r
print("2 declared 12 MB      ", timed(over))
# 3. declares 2 GB, sends almost nothing
def huge():
    s = conn(); s.sendall(b"POST /api HTTP/1.1\r\nHost: x\r\nContent-Length: 2000000000\r\n\r\n{\"a\": \""); r = answer(s, 12); s.close(); return r
print("3 declares 2 GB       ", timed(huge))
# 4. chunked, no declared size, goes over
def chunked():
    s = conn(); s.sendall(b"POST /api HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n")
    chunk = b"4000\r\n" + b"x" * 16384 + b"\r\n"
    try:
        for _ in range(8): s.sendall(chunk)
        s.sendall(b"0\r\n\r\n")
    except OSError as e: return "send failed part way: " + type(e).__name__ + " | " + answer(s, 3)
    r = answer(s); s.close(); return r
print("4 chunked 128 KB      ", timed(chunked))
# 5. sixty oversized requests at once: what is left behind
before = stat(gc=True)
out = []
ts = [threading.Thread(target=lambda: out.append(over()[:16])) for _ in range(60)]
[t.start() for t in ts]; [t.join() for t in ts]
print("5 sixty of 12 MB      ", {a: out.count(a) for a in set(out)}); print("    before:", before); print("    just after:", stat()); time.sleep(2); print("    after clean-up:", stat(gc=True))
# 6. silent connections: opened, nothing sent
silent = [conn() for _ in range(2000)]
time.sleep(1); print("6 2000 silent conns   ", stat(gc=True))
def health():
    s = conn(); s.sendall(b"GET /healthz HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n"); r = answer(s); s.close(); return r
print("    health meanwhile  ", timed(health))
time.sleep(8); print("    8 s later (limit 5 s):", stat(gc=True))
def still_open(s):
    s.settimeout(0.2)
    try: return s.recv(100) != b""
    except socket.timeout: return True
    except OSError: return False
print("    silent still open on the client side:", sum(still_open(s) for s in silent[:200]), "of 200 sampled")
[s.close() for s in silent]
# 7. half a body, then silence
def half():
    s = conn(); s.sendall(b"POST /api HTTP/1.1\r\nHost: x\r\nContent-Length: 1000\r\n\r\n" + b"x" * 500); r = answer(s, 15); s.close(); return r
print("7 half a body, silent ", timed(half))
# 8. headers a byte at a time
def loris():
    s = conn(); t = time.time()
    try:
        for ch in b"GET /healthz HTTP/1.1\r\nHost: x\r\nX-A: " + b"a" * 200:
            s.sendall(bytes([ch])); time.sleep(0.1)
    except OSError as e: return f"closed on us after {time.time()-t:.1f} s ({type(e).__name__})"
    r = answer(s, 3); s.close(); return r
print("8 slow headers        ", timed(loris))
# 9. a reader that stops: asks for a 40 MB answer and reads none of it
s = conn(); s.sendall(b"GET /big HTTP/1.1\r\nHost: x\r\n\r\n"); time.sleep(1); print("9 stalled reader      ", stat())
time.sleep(9); print("    9 s later (limit 5 s):", stat(gc=True)); s.close()
# 10. health check while a handler is busy
t = threading.Thread(target=lambda: (lambda c: (c.sendall(b"GET /slow HTTP/1.1\r\nHost: x\r\n\r\n"), answer(c), c.close()))(conn())); t.start(); time.sleep(0.3)
print("10 health during a slow handler", timed(health)); t.join()
print("end:", stat(gc=True))
srv.stdin.write("\n"); srv.stdin.flush(); srv.wait(timeout=20)
