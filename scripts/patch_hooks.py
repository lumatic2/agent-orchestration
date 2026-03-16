#!/usr/bin/env python3
"""Patch ~/.claude/settings.json common hooks to latest version.
Usage: python3 patch_hooks.py [settings_path]
"""
import sys, os

path = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/.claude/settings.json")
if not os.path.exists(path):
    print(f"[SKIP] {path} not found")
    sys.exit(0)

with open(path, encoding="utf-8") as f:
    c = f.read()

patches = [
    # P1-①: pre-pull 범위 — SCHEDULE.md 만 → 전체 tracked 파일
    (
        "subprocess.run(['git','-C',repo,'pull','--rebase'],capture_output=True) if 'SCHEDULE.md' in fp else None",
        "targets=['SCHEDULE.md','RECURRING.md','session.md','daily/']; subprocess.run(['git','-C',repo,'pull','--rebase'],capture_output=True) if any(t in fp for t in targets) else None",
    ),
    # P1-②: push 실패 감지
    (
        "subprocess.run(['git','-C',repo,'push'],capture_output=True) if match else None",
        "r=subprocess.run(['git','-C',repo,'push'],capture_output=True) if match else None; print('[WARN] git push failed:',r.stderr.decode().strip(),flush=True) if match and r and r.returncode!=0 else None",
    ),
]

changed = False
for old, new in patches:
    if old in c:
        c = c.replace(old, new, 1)
        print(f"[OK] patched: {old[:60]}...")
        changed = True

if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write(c)
else:
    print("[OK] already up to date")
