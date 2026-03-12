#!/usr/bin/env bash
# planby_context.sh — 질문 키워드 기반 Planby 로컬 파일 경로 반환
# Usage: bash planby_context.sh "질문"
# Output: 줄당 파일 경로 (Gemini -f 플래그용)

QUERY="${1:-}"
BASE="$HOME/Desktop/플랜바이 자료"
FILES=()

q=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

# 재무제표
if echo "$q" | grep -qE '재무|손익|자산|부채|자본|매출|이익|손실|b/s|p&l|현금흐름'; then
  f="$BASE/플랜바이 재무:세무 정보/2023-2025 재무제표.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 법인세
if echo "$q" | grep -qE '법인세|세금|세액|세무|신고|이월결손|공제'; then
  f="$BASE/플랜바이 재무:세무 정보/세무 정보/2024_법인세 신고서.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 가결산·계정별원장
if echo "$q" | grep -qE '가결산|계정별원장|원장|거래|분개'; then
  f="$BASE/플랜바이 재무:세무 정보/2025 가결산_계정별원장.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 자본변동표
if echo "$q" | grep -qE '자본변동|자본금|주식|증자|감자'; then
  f="$BASE/플랜바이 재무:세무 정보/2024 자본변동표.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# TIPS·투자
if echo "$q" | grep -qE 'tips|팁스|투자|협약|정부보조금|r&d'; then
  f="$BASE/플랜바이 재무:세무 정보/투자 정보/2024팁스 협약서.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 정관·주총
if echo "$q" | grep -qE '정관|주총|이사회|주주|임원|대표'; then
  f="$BASE/플랜바이 재무:세무 정보/정관 정보/정관.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 회사소개·서비스
if echo "$q" | grep -qE '회사소개|소개서|사업|서비스|plad|plana|솔루션|제품'; then
  f="$BASE/플랜바이 기본 정보/플랜바이테크놀로지스_회사소개서.pdf"
  [ -f "$f" ] && FILES+=("$f")
  f="$BASE/플랜바이 기본 정보/PLAD 서비스소개서.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 사업계획서
if echo "$q" | grep -qE '사업계획|dips|초격차|딥테크|창업'; then
  f="$BASE/플랜바이 기본 정보/2026년 초격차 스타트업 프로젝트(DIPS) 창업기업 사업계획서.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 영업·고객
if echo "$q" | grep -qE '영업|매출목표|고객|대기업|건설사|파이프라인'; then
  f="$BASE/플랜바이 영업/2026-영업목록_최종.xlsx - 대기업&건설사.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 포스코
if echo "$q" | grep -qE '포스코|posco|공모전|이앤씨'; then
  f="$BASE/플랜바이 고객사/포스코 이앤씨 자료/250909 Posco 공유용자료.pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

# 분석
if echo "$q" | grep -qE '경영분석|swot|4영역|전략분석'; then
  f="$BASE/플랜바이 분석 자료/경영 4영역으로 분석 디테일 (1).pdf"
  [ -f "$f" ] && FILES+=("$f")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  exit 0
fi

printf '%s\n' "${FILES[@]}" | sort -u
