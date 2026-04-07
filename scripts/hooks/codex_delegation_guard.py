#!/usr/bin/env python3
"""
codex_delegation_guard.py — PreToolUse hook for Edit|Write

CLAUDE.md 규칙: 50줄+ 코드 작성/수정은 Codex에 위임해야 함.
이 hook은 코드 파일에 50줄+ 컨텐츠 작성/수정을 시도하면 차단한다.

차단 우회: 환경변수 CODEX_GUARD_BYPASS=1
"""

import json
import os
import sys

# 코드 파일 확장자 (이 확장자만 검사)
CODE_EXTENSIONS = {
    '.py', '.js', '.ts', '.tsx', '.jsx', '.mjs', '.cjs',
    '.go', '.rs', '.java', '.kt', '.scala',
    '.c', '.cpp', '.cc', '.h', '.hpp',
    '.rb', '.php', '.swift', '.cs',
    '.vue', '.svelte',
}
# 주의: .sh, .bash는 의도적 제외 (운영 스크립트 직접 편집이 잦음)
# 주의: .md, .json, .yaml, .toml, .txt 는 자동 통과 (코드 아님)

THRESHOLD = 50

def main():
    # 긴급 우회
    if os.environ.get('CODEX_GUARD_BYPASS') == '1':
        sys.exit(0)

    raw = os.environ.get('TOOL_INPUT', '{}')
    try:
        inp = json.loads(raw)
    except Exception:
        sys.exit(0)

    file_path = inp.get('file_path', '')
    if not file_path:
        sys.exit(0)

    ext = os.path.splitext(file_path)[1].lower()
    if ext not in CODE_EXTENSIONS:
        sys.exit(0)

    # Write 도구: content 키 / Edit 도구: new_string 키
    content = inp.get('content') or inp.get('new_string') or ''
    if not content:
        sys.exit(0)

    line_count = content.count('\n') + 1

    if line_count >= THRESHOLD:
        msg = (
            f"\n[CODEX_DELEGATION_GUARD] BLOCKED: {file_path} ({line_count} lines)\n\n"
            f"CLAUDE.md 규칙: 50줄+ 코드 작성/수정은 Codex에 위임해야 합니다.\n"
            f"대신 다음을 사용하세요:\n\n"
            f'  Skill("codex:rescue", args="--background --write \\"{file_path} 작업 설명\\"")\n\n'
            f"긴급 우회: CODEX_GUARD_BYPASS=1 환경변수 설정 후 재시도\n"
        )
        print(msg, file=sys.stderr)
        sys.exit(2)  # exit code 2 = Claude에게 stderr 전달 + 차단

    sys.exit(0)


if __name__ == '__main__':
    main()
