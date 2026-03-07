"""
law_search.py — 한국 법령 검색 (국가법령정보센터 기반)

API 키 불필요. Gemini로 law.go.kr 검색 위임.

사용법:
  python3 law_search.py "소득세법 원천징수 세율"
  python3 law_search.py "법인세 손금산입 요건" --law "법인세법"
  python3 law_search.py --list          # 주요 법령 목록
"""

import sys
import os
import subprocess
import argparse

ORCHESTRATE = os.path.expanduser("~/projects/agent-orchestration/scripts/orchestrate.sh")

# 주요 법령 약어 → 정식 명칭
MAJOR_LAWS = {
    "소득세":   "소득세법",
    "법인세":   "법인세법",
    "부가세":   "부가가치세법",
    "상증세":   "상속세및증여세법",
    "종부세":   "종합부동산세법",
    "국기법":   "국세기본법",
    "조특법":   "조세특례제한법",
    "상법":     "상법",
    "자본시장": "자본시장과금융투자업에관한법률",
    "외감법":   "주식회사등의외부감사에관한법률",
    "근로기준": "근로기준법",
    "중소기업": "중소기업기본법",
    "kifrs":    "한국채택국제회계기준(K-IFRS)",
    "k-ifrs":  "한국채택국제회계기준(K-IFRS)",
    "중소기업회계": "중소기업회계기준",
}

# 법령 직접 URL
LAW_URLS = {
    "소득세법":     "https://www.law.go.kr/법령/소득세법",
    "법인세법":     "https://www.law.go.kr/법령/법인세법",
    "부가가치세법": "https://www.law.go.kr/법령/부가가치세법",
    "상속세및증여세법": "https://www.law.go.kr/법령/상속세및증여세법",
    "국세기본법":   "https://www.law.go.kr/법령/국세기본법",
    "조세특례제한법": "https://www.law.go.kr/법령/조세특례제한법",
    "상법":         "https://www.law.go.kr/법령/상법",
}


def search_via_gemini(query: str, law_filter: str = ""):
    """Gemini를 통해 국가법령정보센터에서 검색"""
    if law_filter:
        law_url = LAW_URLS.get(law_filter, f"https://www.law.go.kr/법령/{law_filter}")
        prompt = f"""site:law.go.kr 에서 다음을 검색해줘:
법령: {law_filter}
질문: {query}

다음 URL을 참고해: {law_url}

답변 형식:
1. 관련 조문 (조 번호 포함)
2. 핵심 내용 요약
3. 개정 이력이 있다면 최근 개정 내용
4. 참고 URL"""
    else:
        prompt = f"""한국 국가법령정보센터(law.go.kr)에서 다음 법령 관련 내용을 찾아줘:
질문: {query}

검색 URL: https://www.law.go.kr/lsSc.do?query={query}

답변 형식:
1. 관련 법령명
2. 관련 조문 요약
3. 실무 적용 방법
4. 참고 URL (law.go.kr)"""

    task_name = f"law-{query[:20].replace(' ', '-')}"

    print(f"🔍 법령 검색 중: '{query}'" + (f" in [{law_filter}]" if law_filter else ""))
    print(f"   Gemini → law.go.kr 검색 위임\n")

    cmd = ["bash", ORCHESTRATE, "gemini", prompt, task_name]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)

    if result.returncode == 0:
        # 로그 파일에서 결과 읽기
        import glob
        logs = sorted(glob.glob(
            os.path.expanduser(f"~/projects/agent-orchestration/logs/gemini_{task_name}*.txt")
        ))
        if logs:
            with open(logs[-1]) as f:
                content = f.read()
            # YOLO 헤더 제거
            lines = [l for l in content.split("\n")
                     if not l.startswith("YOLO") and not l.startswith("Loaded") and not l.startswith("Error getting")]
            print("\n".join(lines).strip())
        else:
            print(result.stdout)
    else:
        print(f"[오류] {result.stderr[:200]}")

    print(f"\n🌐 직접 확인: https://www.law.go.kr/lsSc.do?query={query}")


def list_major_laws():
    print("\n📚 주요 법령 목록\n")
    print(f"{'약어':<10} {'정식 법령명'}")
    print("─" * 40)
    for abbr, full in MAJOR_LAWS.items():
        url = LAW_URLS.get(full, "")
        print(f"{abbr:<10} {full}")
        if url:
            print(f"{'':10} {url}")
    print(f"\n예시: python3 law_search.py '원천징수 세율' --law 소득세법")


def main():
    parser = argparse.ArgumentParser(
        description="한국 법령 검색 (국가법령정보센터, API 키 불필요)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
예시:
  python3 law_search.py "원천징수 세율"
  python3 law_search.py "원천징수" --law 소득세법
  python3 law_search.py "배당소득 과세" --law 법인세법
  python3 law_search.py --list
        """
    )
    parser.add_argument("query", nargs="?", help="검색할 법령 키워드/질문")
    parser.add_argument("--law", "-l", default="", help="특정 법령 지정 (약어 또는 정식명)")
    parser.add_argument("--list", action="store_true", help="주요 법령 목록 보기")
    args = parser.parse_args()

    if args.list:
        list_major_laws()
        return

    if not args.query:
        parser.print_help()
        return

    # 약어 → 정식 법령명
    law = MAJOR_LAWS.get(args.law.lower(), args.law)
    search_via_gemini(args.query, law_filter=law)


if __name__ == "__main__":
    main()
