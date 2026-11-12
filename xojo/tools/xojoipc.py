#!/usr/bin/env python3
# xojoipc.py 'IDE script' : send a script to the running Xojo IDE (protocol 2), print the reply
import socket, sys, json
s = socket.socket(socket.AF_UNIX); s.settimeout(float(sys.argv[2]) if len(sys.argv) > 2 else 30)
s.connect("/tmp/XojoIDE")
s.sendall(json.dumps({"protocol": 2}).encode() + b"\0")
s.sendall(json.dumps({"tag": "t1", "script": sys.argv[1]}).encode() + b"\0")
buf = b""
try:
    while True:
        d = s.recv(65536)
        if not d: break
        buf += d
        if b'"tag"' in buf and buf.endswith(b"\0"): break
except socket.timeout:
    pass
print(buf.replace(b"\0", b"\n").decode(errors="replace"))
