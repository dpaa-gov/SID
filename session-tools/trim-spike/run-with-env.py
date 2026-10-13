"""Starts a program with DB_* read from SID's .env as dev/julia.sh reads it: line by line, never through a shell."""
import os, sys
env = dict(os.environ)
for line in open("/home/fynchy/Development/SID/.env"):
    line = line.rstrip("\n")
    if line.startswith("#") or "=" not in line: continue
    k, v = line.split("=", 1); env[k] = v
if env.get("DB_HOST") == "ards-db": env["DB_HOST"] = "127.0.0.1"
os.execve(sys.argv[1], sys.argv[1:], env)
