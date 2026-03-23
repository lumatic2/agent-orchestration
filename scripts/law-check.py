#!/usr/bin/env python3
"""
law-check.py — 법제처 Open API 기반 법령 개정 자동 감지 및 vault 업데이트

Usage:
  python law-check.py              # 전체 법령 점검 + 업데이트
  python law-check.py --discover   # ls_id 미등록만 탐색 (API 승인 후 최초 실행)
  python law-check.py --dry-run    # 변경 감지만, 다운로드/변환 없음
  python law-check.py 법인세법      # 특정 법령만 점검

Prerequisites:
  pip install pyyaml
  .env에 LAW_API_OC=<법제처 개방 API OC값> 추가
"""
import os
import re
import sys
import json
import time
import shutil
import platform
import subprocess
import urllib.request
import urllib.parse
from pathlib import Path

try:
    import yaml
except ImportError:
    subprocess.run([sys.executable, "-m", "pip", "install", "pyyaml"], check=True)
    import yaml

# ── 경로 설정 (Windows / M1 자동 감지) ───────────────────────────────────────
_BASE         = Path("/Users/luma3/projects/agent-orchestration") if True else Path("C:/Users/1/Desktop")
REGISTRY_PATH = _BASE / "law_registry.yaml"
ENV_PATH      = _BASE / "content-automation/.env"
PDF_INPUT_DIR = _BASE / "pdf-input"
PDF_TO_VAULT  = _BASE / "pdf-to-vault.py"
API_BASE      = "https://www.law.go.kr/DRF"

# 법령 유형 → API target
TYPE_TO_TARGET = {
    "법률":    "law",
    "대통령령": "pres",
    "부령":    "rule",
    "시행규칙": "rule",
}


# ── 유틸 ──────────────────────────────────────────────────────────────────────
def load_env_key(key_name: str) -> str:
    val = os.getenv(key_name)
    if val:
        return val.strip()
    if not ENV_PATH.exists():
        raise RuntimeError(f".env 파일 없음: {ENV_PATH}")
    for line in ENV_PATH.read_text(encoding="utf-8").splitlines():
        raw = line.strip()
        if not raw or raw.startswith("#") or "=" not in raw:
            continue
        k, v = raw.split("=", 1)
        if k.strip() == key_name:
            return v.strip().strip('"').strip("'")
    raise RuntimeError(f"{key_name}을 찾지 못했습니다. .env에 LAW_API_OC=값 추가.")


def load_registry() -> dict:
    return yaml.safe_load(REGISTRY_PATH.read_text(encoding="utf-8"))


def save_registry(data: dict) -> None:
    """registry 저장 (백업 → 헤더 주석 재생성 → 덮어쓰기)"""
    shutil.copy2(REGISTRY_PATH, REGISTRY_PATH.with_suffix(".yaml.bak"))
    header = (
        "# law_registry.yaml\n"
        "# 법제처 Open API 자동 업데이트 추적 목록\n"
        "# ls_id: 법제처 Open API 승인 후 law-check.py 최초 실행 시 자동 채워짐\n"
        "# current_no: 법령 번호 (제XXXXX호에서 숫자), current_date: YYYYMMDD\n\n"
    )
    REGISTRY_PATH.write_text(
        header + yaml.dump(data, allow_unicode=True, default_flow_style=False, sort_keys=False),
        encoding="utf-8",
    )


# ── API 호출 ──────────────────────────────────────────────────────────────────
def api_get(oc: str, endpoint: str, params: dict) -> dict:
    params = {**params, "OC": oc, "type": "JSON"}
    url = f"{API_BASE}/{endpoint}?" + urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    req = urllib.request.Request(url, headers={"User-Agent": "law-check/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def search_law(oc: str, name: str, law_type: str) -> list[dict]:
    # lawSearch.do는 target=law 로 모든 유형(법률·시행령·시행규칙) 검색 가능
    _ = TYPE_TO_TARGET.get(law_type, "law")  # kept for reference
    try:
        data = api_get(oc, "lawSearch.do", {"target": "law", "query": name, "display": "20"})
    except Exception as e:
        print(f"    [API ERROR] 검색 실패: {e}")
        return []
    raw = data.get("LawSearch", {}).get("law", [])
    if isinstance(raw, dict):
        return [raw]
    return raw or []


def get_law_info(oc: str, ls_id: str) -> dict:
    try:
        data = api_get(oc, "lawService.do", {"target": "law", "ID": ls_id})
    except Exception as e:
        print(f"    [API ERROR] 상세조회 실패: {e}")
        return {}
    law = data.get("law", {})
    # 일부 응답은 {"law": {"기본정보": {...}, "조문": [...]}} 구조
    return law.get("기본정보", law)


# ── ls_id 자동 탐색 ───────────────────────────────────────────────────────────
def discover_ls_id(oc: str, entry: dict):
    """법령명으로 ls_id 탐색 — 정확 일치 우선, 없으면 첫 번째 결과"""
    results = search_law(oc, entry["name"], entry.get("type", "법률"))
    if not results:
        return None

    for r in results:
        if r.get("법령명한글", "").strip() == entry["name"]:
            ls_id = str(r.get("법령ID", "")).strip()
            print(f"    → ls_id={ls_id}")
            return ls_id

    # 유사 일치 (첫 번째 결과)
    r = results[0]
    ls_id = str(r.get("법령ID", "")).strip()
    matched_name = r.get("법령명한글", "?")
    print(f"    → ls_id={ls_id} (유사 일치: {matched_name})")
    return ls_id


# ── 버전 비교 ─────────────────────────────────────────────────────────────────
def parse_law_no(raw: str) -> str:
    """'제21065호' → '21065'"""
    m = re.search(r"\d+", str(raw))
    return m.group(0) if m else str(raw)


def check_update(oc: str, entry: dict):
    """최신 버전 확인 → 신버전이면 dict 반환, 최신이면 None"""
    info = get_law_info(oc, entry["ls_id"])
    if not info:
        return None

    # API 필드: 법령호수 or 공포번호 (응답 버전에 따라 다름)
    api_no   = parse_law_no(info.get("법령호수", info.get("공포번호", "")))
    api_date = re.sub(r"\D", "", str(info.get("공포일자", "")))

    if api_no == str(entry.get("current_no", "")) and api_date == str(entry.get("current_date", "")):
        return None

    return {
        "name":     entry["name"],
        "ls_id":    entry["ls_id"],
        "domain":   entry["domain"],
        "type":     entry.get("type", "법률"),
        "old_no":   str(entry.get("current_no", "")),
        "new_no":   api_no,
        "old_date": str(entry.get("current_date", "")),
        "new_date": api_date,
    }


# ── 다운로드 + vault 업데이트 ──────────────────────────────────────────────────
def download_law_pdf(oc: str, ls_id: str, dest: Path) -> None:
    url = f"{API_BASE}/lawService.do?OC={oc}&target=law&type=PDF&ID={ls_id}"
    req = urllib.request.Request(url, headers={"User-Agent": "law-check/1.0"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        dest.write_bytes(resp.read())


def process_update(oc: str, upd: dict) -> bool:
    # 파일명에 법령 유형 괄호 포함 → pdf-to-vault.py의 is_law_document() 트리거
    pdf_name = f"{upd['name']}({upd['type']})(제{upd['new_no']}호)({upd['new_date']}).pdf"
    dest = PDF_INPUT_DIR / pdf_name

    PDF_INPUT_DIR.mkdir(parents=True, exist_ok=True)

    print(f"    [DOWNLOAD] {pdf_name}")
    try:
        download_law_pdf(oc, upd["ls_id"], dest)
    except Exception as e:
        print(f"    [ERROR] PDF 다운로드 실패: {e}")
        return False

    print(f"    [VAULT] pdf-to-vault.py 실행...")
    try:
        proc = subprocess.run(
            [sys.executable, "-u", str(PDF_TO_VAULT), str(dest)],
            capture_output=True, text=True, encoding="utf-8", timeout=300,
        )
        for line in (proc.stdout + proc.stderr).strip().splitlines():
            print(f"      {line}")
        if proc.returncode != 0:
            return False
    except Exception as e:
        print(f"    [ERROR] pdf-to-vault 실행 실패: {e}")
        return False

    return True


# ── 메인 ──────────────────────────────────────────────────────────────────────
def main() -> int:
    args          = sys.argv[1:]
    dry_run       = "--dry-run" in args
    discover_only = "--discover" in args
    name_filter   = next((a for a in args if not a.startswith("-")), None)

    try:
        oc = load_env_key("LAW_API_OC")
    except RuntimeError as e:
        print(f"[ERROR] {e}")
        return 1

    registry = load_registry()
    laws     = registry.get("laws", [])

    if name_filter:
        laws = [e for e in laws if name_filter in e["name"]]
        if not laws:
            print(f"[WARN] '{name_filter}' 매칭 법령 없음")
            return 0

    # ── 1단계: ls_id 자동 탐색 ────────────────────────────────────────────
    undiscovered = [e for e in laws if not e.get("ls_id")]
    if undiscovered:
        print(f"[DISCOVER] ls_id 미등록 {len(undiscovered)}개 탐색 중...")
        changed = False
        for entry in undiscovered:
            print(f"  {entry['name']}", end="", flush=True)
            ls_id = discover_ls_id(oc, entry)
            if ls_id:
                entry["ls_id"] = ls_id
                changed = True
            else:
                print("  → 탐색 실패")
            time.sleep(0.3)  # API 부하 방지
        if changed and not dry_run:
            save_registry(registry)
            print("[DISCOVER] registry 업데이트 완료\n")

    if discover_only:
        return 0

    # ── 2단계: 버전 비교 ──────────────────────────────────────────────────
    registered = [e for e in laws if e.get("ls_id")]
    if not registered:
        print("[INFO] ls_id 등록 법령 없음. --discover 먼저 실행하세요.")
        return 0

    print(f"[CHECK] {len(registered)}개 법령 버전 점검...")
    updates = []
    for entry in registered:
        print(f"  {entry['name']}", end="", flush=True)
        upd = check_update(oc, entry)
        if upd:
            print(f" → 개정! 제{upd['old_no']}호 → 제{upd['new_no']}호")
            updates.append(upd)
        else:
            print(" ✓")
        time.sleep(0.2)

    if not updates:
        print("\n[DONE] 모든 법령 최신 상태")
        return 0

    print(f"\n[UPDATE] {len(updates)}개 개정 감지:")
    for u in updates:
        print(f"  - {u['name']}: 제{u['old_no']}호({u['old_date']}) → 제{u['new_no']}호({u['new_date']})")

    if dry_run:
        print("[DRY-RUN] 종료 (실제 처리 없음)")
        return 0

    # ── 3단계: 다운로드 + vault 갱신 ──────────────────────────────────────
    ok = 0
    for upd in updates:
        print(f"\n  처리: {upd['name']}")
        if process_update(oc, upd):
            for entry in registry["laws"]:
                if entry["name"] == upd["name"]:
                    entry["current_no"]   = upd["new_no"]
                    entry["current_date"] = upd["new_date"]
                    break
            ok += 1
        else:
            print(f"  [SKIP] 다음 실행에서 재시도")

    if ok:
        save_registry(registry)

    print(f"\n[DONE] {ok}/{len(updates)} 업데이트 완료")
    return 0 if ok == len(updates) else 1


if __name__ == "__main__":
    raise SystemExit(main())
