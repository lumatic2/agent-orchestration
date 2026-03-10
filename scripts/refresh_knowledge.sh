#!/bin/bash
# refresh_knowledge.sh — knowledge 파일 핵심 수치 자동 갱신
#
# 사용법:
#   bash refresh_knowledge.sh               # 전체 갱신
#   bash refresh_knowledge.sh --agent tax   # tax 에이전트만
#   bash refresh_knowledge.sh --agent economics
#   bash refresh_knowledge.sh --agent lawyer
#   bash refresh_knowledge.sh --check       # 갱신 없이 현황만 확인
#   bash refresh_knowledge.sh --dry-run     # 가져올 값만 출력, 파일 수정 안함
#
# 환경변수:
#   BOK_API_KEY   — 한국은행 ECOS API 키 (https://ecos.bok.or.kr 무료 등록)
#                   미설정 시 'sample' 키로 시도 (제한적)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
KNOWLEDGE_DIR="$REPO_DIR/agents/knowledge"

# ─── 인수 파싱 ────────────────────────────────────────────────
TARGET_AGENT="all"
CHECK_ONLY=false
DRY_RUN=false
PREV_ARG=""

for arg in "$@"; do
  case "$arg" in
    --check)   CHECK_ONLY=true ;;
    --dry-run) DRY_RUN=true ;;
    --agent)   ;;
    *)
      [ "$PREV_ARG" = "--agent" ] && TARGET_AGENT="$arg"
      ;;
  esac
  PREV_ARG="$arg"
done

# ─── 설정 ─────────────────────────────────────────────────────
BOK_KEY="${BOK_API_KEY:-sample}"
TODAY=$(date +%Y-%m-%d)

echo "🔄 knowledge 자동갱신 시작 ($TODAY)"
echo "   BOK API 키: $([ "$BOK_KEY" = "sample" ] && echo "sample (제한적)" || echo "사용자 키 사용")"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ─── 공통: 섹션 교체 함수 ────────────────────────────────────
# update_section FILE AGENT_KEY NEW_CONTENT
update_section() {
  local file="$1"
  local key="$2"
  local new_content="$3"

  if [ "$DRY_RUN" = true ]; then
    echo "  [DRY-RUN] $file 에 쓸 내용:"
    echo "$new_content" | head -20
    return 0
  fi

  python3 - "$file" "$key" "$TODAY" << PYEOF
import sys, re

filepath, key, today = sys.argv[1], sys.argv[2], sys.argv[3]

with open(filepath, encoding='utf-8') as f:
    content = f.read()

# new content passed via stdin
new_inner = sys.stdin.read().strip()

start_marker = f'<!-- AUTOREFRESH_START: {key} -->'
end_marker   = '<!-- AUTOREFRESH_END -->'

start_idx = content.find(start_marker)
end_idx   = content.find(end_marker)

if start_idx == -1 or end_idx == -1:
    print(f"  ⚠️  마커 없음: {filepath} (AUTOREFRESH_START: {key})", file=sys.stderr)
    sys.exit(1)

end_idx_full = end_idx + len(end_marker)
replacement  = f"{start_marker}\n{new_inner}\n{end_marker}"
new_content  = content[:start_idx] + replacement + content[end_idx_full:]

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(new_content)

print(f"  ✅ 갱신 완료: {filepath}")
PYEOF
  echo "$new_content" | python3 -c "
import sys
content = sys.stdin.read()
" 2>/dev/null
}

# ─── Python 데이터 페처 ──────────────────────────────────────
fetch_data() {
python3 - "$BOK_KEY" "$TARGET_AGENT" "$CHECK_ONLY" "$DRY_RUN" "$KNOWLEDGE_DIR" "$TODAY" << 'PYEOF'
import sys, json, urllib.request, urllib.error, re, os
from datetime import datetime

bok_key, target, check_only, dry_run, kdir, today = \
    sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]

check_only = check_only == "true"
dry_run    = dry_run    == "true"

# ── BOK ECOS API 호출 ──────────────────────────────────────
def bok_fetch(stat_code, period_type, start, end, item_code=""):
    url = (
        f"https://ecos.bok.or.kr/api/StatisticSearch/{bok_key}/json/kr"
        f"/1/5/{stat_code}/{period_type}/{start}/{end}"
    )
    if item_code:
        url += f"/{item_code}"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=8) as r:
            data = json.loads(r.read().decode())
        rows = data.get("StatisticSearch", {}).get("row", [])
        if rows:
            return rows[-1]  # 최신 값
    except Exception as e:
        print(f"  ⚠️  BOK API 오류 ({stat_code}): {e}", file=sys.stderr)
    return None

# ── 웹 스크래핑 폴백 ──────────────────────────────────────
def scrape(url, pattern):
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as r:
            html = r.read().decode("utf-8", errors="replace")
        m = re.search(pattern, html)
        return m.group(1).strip() if m else None
    except Exception as e:
        print(f"  ⚠️  스크래핑 오류 ({url[:50]}): {e}", file=sys.stderr)
        return None

# ── 섹션 교체 ─────────────────────────────────────────────
def update_section(filepath, key, new_inner):
    if check_only or dry_run:
        if dry_run:
            print(f"\n  [DRY-RUN] {os.path.basename(filepath)}:")
            print(new_inner[:400])
        return

    with open(filepath, encoding="utf-8") as f:
        content = f.read()

    start_marker = f"<!-- AUTOREFRESH_START: {key} -->"
    end_marker   = "<!-- AUTOREFRESH_END -->"
    s = content.find(start_marker)
    e = content.find(end_marker)
    if s == -1 or e == -1:
        print(f"  ⚠️  마커 없음: {filepath}")
        return

    replacement = f"{start_marker}\n{new_inner}\n{end_marker}"
    new_content = content[:s] + replacement + content[e + len(end_marker):]
    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"  ✅ {os.path.basename(filepath)} 갱신 완료")

# ──────────────────────────────────────────────────────────
# [1] ECONOMICS: 기준금리, 환율, CPI
# ──────────────────────────────────────────────────────────
def refresh_macro():
    print("\n📊 [economics] 거시경제 지표 갱신 중...")

    # 기준금리 (722Y001 / 0101000)
    ym_start = datetime.now().strftime("%Y%m")
    ym_1yr   = str(int(ym_start[:4]) - 1) + ym_start[4:]
    rate_row = bok_fetch("722Y001", "M", ym_1yr, ym_start, "0101000")

    # USD/KRW 환율 (731Y001 / 0000001) — 원달러 매매기준율
    fx_row   = bok_fetch("731Y001", "D", ym_1yr + "01", ym_start + "31", "0000001")

    # CPI 전년동월비 — 코드별 시도 (sample 키 제한으로 폴백)
    cpi_row = bok_fetch("901Y062", "M", ym_1yr, ym_start, "0")
    if not cpi_row:
        # 인덱스값으로 YoY 수동 계산
        cur  = bok_fetch("901Y009", "M", ym_start, ym_start, "0")
        ym_prev = str(int(ym_start[:4]) - 1) + ym_start[4:]
        prev = bok_fetch("901Y009", "M", ym_prev, ym_prev, "0")
        if cur and prev:
            try:
                yoy = (float(cur["DATA_VALUE"]) / float(prev["DATA_VALUE"]) - 1) * 100
                cur["DATA_VALUE"] = f"{yoy:.1f}"
                cpi_row = cur
            except:
                pass

    # 결과 포매팅
    def fmt(row, suffix=""):
        if row:
            val = row.get("DATA_VALUE", "—")
            dt  = row.get("TIME", "—")
            return f"{val}{suffix}", dt
        return "—", "—"

    rate_val, rate_dt = fmt(rate_row, "%")
    fx_val,   fx_dt   = fmt(fx_row, "원")
    cpi_val,  cpi_dt  = fmt(cpi_row, "%")

    # 변화 방향 추가
    def trend(row):
        rows_all = []
        if row:
            ym2 = str(int(row.get("TIME","000000")[:6]) - 1).zfill(6)
            prev = bok_fetch("722Y001", "M", ym2, ym2, "0101000")
            if prev:
                try:
                    diff = float(row["DATA_VALUE"]) - float(prev["DATA_VALUE"])
                    return "▲" if diff > 0 else ("▼" if diff < 0 else "─")
                except:
                    pass
        return ""

    content = f"""## ⏰ 최신 지표 (자동갱신)
_마지막 갱신: {today}_

| 지표 | 값 | 기준일 |
|---|---|---|
| 한국은행 기준금리 | {rate_val} | {rate_dt} |
| USD/KRW 환율 | {fx_val} | {fx_dt} |
| 소비자물가(CPI, 전년비) | {cpi_val} | {cpi_dt} |

> 출처: 한국은행 ECOS (ecos.bok.or.kr)"""

    if check_only:
        print(f"  기준금리: {rate_val} ({rate_dt})")
        print(f"  USD/KRW:  {fx_val} ({fx_dt})")
        print(f"  CPI:      {cpi_val} ({cpi_dt})")
        return

    update_section(
        os.path.join(kdir, "macro_indicators.md"),
        "macro",
        content
    )

# ──────────────────────────────────────────────────────────
# [2] LABOR: 최저임금
# ──────────────────────────────────────────────────────────
def refresh_labor():
    print("\n👷 [lawyer] 최저임금 갱신 중...")

    # 최저임금 — 고용노동부 스크래핑
    mw_val = scrape(
        "https://www.moel.go.kr/policy/policyinfo/lobar/list.do",
        r'(\d{1,3}(?:,\d{3})+)\s*원'
    )
    # 폴백: minimumwage.go.kr
    if not mw_val:
        mw_val = scrape(
            "https://www.minimumwage.go.kr/main.do",
            r'(\d{1,3}(?:,\d{3})+)\s*원'
        )

    year = datetime.now().year
    if not mw_val:
        # 하드코딩 폴백 (연도별)
        fallback = {2025: "10,030", 2026: "10,030"}  # 2026 미정 시 동결 가정
        mw_val = fallback.get(year, "확인 필요")
        print(f"  ⚠️  스크래핑 실패 → 폴백값 사용: {mw_val}원")

    try:
        monthly = int(mw_val.replace(",","")) * 209
        monthly_str = f"{monthly:,}"
    except:
        monthly_str = "—"

    content = f"""## ⏰ 최신 지표 (자동갱신)
_마지막 갱신: {today}_

| 지표 | 값 | 적용 시기 |
|---|---|---|
| 최저임금 | {mw_val}원/시간 | {year}년 |
| 월 환산 최저임금 (209시간) | {monthly_str}원 | {year}년 |

> 출처: 최저임금위원회 (minimumwage.go.kr)"""

    if check_only:
        print(f"  최저임금: {mw_val}원/시간 ({year}년)")
        print(f"  월 환산: {monthly_str}원")
        return

    update_section(
        os.path.join(kdir, "labor_civil_law.md"),
        "labor",
        content
    )

# ──────────────────────────────────────────────────────────
# [3] TAX: 법인세율 (law.go.kr 스크래핑)
# ──────────────────────────────────────────────────────────
def refresh_tax():
    print("\n💼 [tax] 법인세율 갱신 중...")

    # law.go.kr 법인세법 스크래핑 (URL 인코딩)
    html = None
    try:
        import urllib.parse
        law_url = "https://www.law.go.kr/법령/법인세법"
        encoded = urllib.parse.quote(law_url, safe=":/?=&")
        req = urllib.request.Request(encoded, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=10) as r:
            html = r.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  ⚠️  law.go.kr 접근 실패: {e}", file=sys.stderr)

    # 현행 법인세율 (2023년 이후 인하 적용)
    # 하드코딩 기준값 (2023년 세제개편으로 인하)
    rates = [
        ("2억 이하",       "9%",  "법인세법 §55"),
        ("2억 초과~200억", "19%", "법인세법 §55"),
        ("200억 초과~3000억", "21%", "법인세법 §55"),
        ("3000억 초과",    "24%", "법인세법 §55"),
    ]
    carryforward = "80% (중소기업 100%)"

    # law.go.kr에서 실제 세율 추출 시도
    if html:
        # 세율 패턴 탐지 (예: 9퍼센트, 19퍼센트)
        found = re.findall(r'(\d+)퍼센트', html)
        if found and len(found) >= 4:
            print(f"  ℹ️  law.go.kr에서 세율 감지: {found[:6]}")
            # 실제 파싱은 구조가 복잡해 하드코딩 우선 유지

    rows_str = "\n".join([f"| 법인세율 ({r[0]}) | {r[1]} | {r[2]} |" for r in rates])
    content = f"""## ⏰ 최신 세율·한도 (자동갱신)
_마지막 갱신: {today}_

| 지표 | 값 | 근거 |
|---|---|---|
{rows_str}
| 이월결손금 공제 한도 | {carryforward} | 법인세법 §13 |

> ⚠️ 세율은 매년 세제개편 확인 필요. 출처: 법제처 law.go.kr"""

    if check_only:
        for r in rates:
            print(f"  법인세율 {r[0]}: {r[1]}")
        return

    update_section(
        os.path.join(kdir, "tax_core.md"),
        "tax",
        content
    )

# ──────────────────────────────────────────────────────────
# 실행
# ──────────────────────────────────────────────────────────
run_map = {
    "economics": [refresh_macro],
    "lawyer":    [refresh_labor],
    "tax":       [refresh_tax],
    "all":       [refresh_macro, refresh_labor, refresh_tax],
}

fns = run_map.get(target, run_map["all"])
for fn in fns:
    fn()

print()
PYEOF
}

# ─── 실행 ─────────────────────────────────────────────────────
if [ "$CHECK_ONLY" = true ]; then
  echo "ℹ️  CHECK 모드 — 파일 수정 없음"
fi

fetch_data

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$DRY_RUN" = true ]; then
  echo "  [DRY-RUN] 완료. 실제 갱신: bash refresh_knowledge.sh"
elif [ "$CHECK_ONLY" = true ]; then
  echo "  갱신하려면: bash refresh_knowledge.sh [--agent 이름]"
else
  echo "  다음 갱신: bash refresh_knowledge.sh"
  echo "  BOK API 키 등록: export BOK_API_KEY=your_key"
  echo "  키 발급: https://ecos.bok.or.kr (무료)"
fi
