#!/usr/bin/env python3
"""Check .claude.json MCP configuration against expected baseline.
Reports missing or misconfigured MCP servers.
Usage: python3 check_mcp.py
"""
import json, os, sys, platform

def find_claude_json():
    home = os.path.expanduser("~")
    # Windows: C:/Users/1/.claude.json, Mac: ~/.claude.json
    path = os.path.join(home, ".claude.json")
    return path if os.path.exists(path) else None

EXPECTED_GLOBAL_MCPS = {
    "obsidian-vault": {
        "required_keys": ["command"],
        "note": "M1 SSH 경유 — mcpvault 설정 필요"
    },
    "stitch-mcp": {
        "required_keys": ["command"],
        "note": "npx stitch-mcp@latest (Windows: cmd /c 래퍼 필요)"
    },
    "gemini-nanobanana-mcp": {
        "required_keys": ["command", "env"],
        "note": "GEMINI_API_KEY 환경변수 필요"
    },
}

EXPECTED_PROJECT_MCPS = {
    "google-workspace": {
        "note": "홈 디렉토리 프로젝트에 등록, 필요 시 gws.py on/off"
    }
}

def check():
    path = find_claude_json()
    if not path:
        print("[ERROR] .claude.json 없음")
        sys.exit(1)

    with open(path, encoding="utf-8") as f:
        d = json.load(f)

    global_mcps = d.get("mcpServers", {})
    projects = d.get("projects", {})

    print(f"=== MCP 설정 검사 ({platform.node()}) ===\n")

    # Global MCPs
    print("[ Global MCPs ]")
    for name, info in EXPECTED_GLOBAL_MCPS.items():
        if name in global_mcps:
            cfg = global_mcps[name]
            missing = [k for k in info["required_keys"] if k not in cfg]
            if missing:
                print(f"  [WARN] {name}: 키 누락 {missing}")
            else:
                print(f"  [OK]   {name}")
        else:
            print(f"  [MISS] {name} — {info['note']}")

    # Project MCPs
    print("\n[ Project MCPs ]")
    home = os.path.expanduser("~").replace("\\", "/")
    found_gws = False
    for proj_key, proj_data in projects.items():
        proj_mcps = proj_data.get("mcpServers", {})
        if "google-workspace" in proj_mcps:
            print(f"  [OK]   google-workspace (project: {proj_key})")
            found_gws = True
    if not found_gws:
        print(f"  [MISS] google-workspace — {EXPECTED_PROJECT_MCPS['google-workspace']['note']}")

    # Windows-specific: cmd /c wrapper check
    if platform.system() == "Windows" or "MINGW" in platform.node().upper() or os.sep == "\\":
        print("\n[ Windows cmd /c 래퍼 검사 ]")
        for name in ["stitch-mcp", "gemini-nanobanana-mcp"]:
            if name in global_mcps:
                cmd = global_mcps[name].get("command", "")
                if cmd == "cmd":
                    print(f"  [OK]   {name}: cmd /c 래퍼 있음")
                elif cmd == "npx":
                    print(f"  [WARN] {name}: cmd /c 래퍼 없음 (npx 직접 호출 — Windows에서 오류 가능)")

    print()

if __name__ == "__main__":
    check()
