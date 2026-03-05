"""
law_rag.py — 법령·회계기준 로컬 RAG (ChromaDB + Gemini 합성)

사용법:
  # 1. 기존 knowledge 파일로 즉시 인덱싱 (API key 불필요)
  python3 law_rag.py --seed

  # 2. 법령 질의 (Gemini가 검색 결과로 답변 합성)
  python3 law_rag.py --ask "소득세법상 원천징수 세율은?"
  python3 law_rag.py --ask "R&D 세액공제 요건" --law 조특법

  # 3. 인덱싱 현황
  python3 law_rag.py --list

  # 4. 법제처 API로 법령 전문 인덱싱 (LAW_API_OC 필요)
  python3 law_rag.py --index --query "소득세법,법인세법"

  # 5. 개정 확인
  python3 law_rag.py --update

환경변수:
  LAW_API_OC   — 법제처 API 인증키 (--index, --update 전용)
"""

import os
import sys
import re
import json
import time
import subprocess
import argparse
from pathlib import Path

import chromadb

# ── 설정 ──────────────────────────────────────────────────────
LAW_API_OC   = os.environ.get("LAW_API_OC", "")
LAW_BASE_URL = "https://www.law.go.kr/DRF"
DB_PATH      = os.path.expanduser("~/knowledge-vault/law_chroma_db")
COLLECTION   = "korean_laws"

REPO_DIR = Path(__file__).resolve().parent.parent
KNOWLEDGE_DIR = REPO_DIR / "agents" / "knowledge"


# ── ChromaDB ────────────────────────────────────────────────
def get_db():
    os.makedirs(DB_PATH, exist_ok=True)
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(
        name=COLLECTION,
        metadata={"hnsw:space": "cosine"},
    )
    return collection


# ── 시드: knowledge 파일 인덱싱 ─────────────────────────────
def seed_from_knowledge():
    """agents/knowledge/*.md → ChromaDB (LAW_API_OC 불필요)"""
    collection = get_db()

    md_files = sorted(KNOWLEDGE_DIR.glob("*.md"))
    if not md_files:
        print(f"[ERROR] Knowledge 파일 없음: {KNOWLEDGE_DIR}")
        sys.exit(1)

    indexed = 0
    skipped = 0

    for md_path in md_files:
        source = md_path.stem  # e.g. "tax_core"
        content = md_path.read_text(encoding="utf-8")

        # ## 헤더 기준 섹션 분할
        sections = re.split(r"\n(?=##+ )", content)

        for i, section in enumerate(sections):
            stripped = section.strip()
            if len(stripped) < 40:
                continue

            chunk_id = f"knowledge_{source}_{i}"

            existing = collection.get(ids=[chunk_id])
            if existing["ids"]:
                skipped += 1
                continue

            title_m = re.match(r"#+\s+(.+)", stripped)
            title = title_m.group(1).strip() if title_m else source

            collection.add(
                documents=[stripped[:2000]],
                metadatas=[{
                    "source":      source,
                    "source_file": md_path.name,
                    "title":       title,
                    "type":        "knowledge",
                }],
                ids=[chunk_id],
            )

        indexed += 1
        print(f"  ✅ {md_path.name}")

    total = collection.count()
    print(f"\n시드 완료: {indexed}개 파일 처리 ({skipped}개 청크 이미 존재)")
    print(f"DB 총 청크: {total}개  |  위치: {DB_PATH}")


# ── 법제처 API 인덱싱 ────────────────────────────────────────
def _api_search_laws(query: str) -> list:
    try:
        import requests
    except ImportError:
        print("[ERROR] requests 패키지 필요: pip install requests")
        return []

    if not LAW_API_OC:
        print("[ERROR] LAW_API_OC 환경변수 필요 (export LAW_API_OC=이메일ID)")
        return []

    params = {
        "OC": LAW_API_OC, "target": "law", "type": "JSON",
        "query": query, "page": 1, "display": 20, "sort": "lasc",
    }
    try:
        import requests as req
        r = req.get(f"{LAW_BASE_URL}/lawSearch.do", params=params, timeout=10)
        r.raise_for_status()
        laws = r.json().get("LawSearch", {}).get("law", [])
        return laws if isinstance(laws, list) else [laws]
    except Exception as e:
        print(f"[ERROR] 법령 검색 실패: {e}")
        return []


def _api_get_law_content(law_id: str) -> str:
    try:
        import requests as req
    except ImportError:
        return ""

    params = {"OC": LAW_API_OC, "target": "law", "type": "JSON", "ID": law_id}
    try:
        r = req.get(f"{LAW_BASE_URL}/lawService.do", params=params, timeout=15)
        r.raise_for_status()
        articles = r.json().get("법령", {}).get("조문", {}).get("조문단위", [])
        if isinstance(articles, dict):
            articles = [articles]
        texts = []
        for a in articles:
            title   = a.get("조문제목", "")
            content = a.get("조문내용", "")
            if content:
                texts.append(f"{title}\n{content}")
        return "\n\n".join(texts)
    except Exception as e:
        print(f"[ERROR] 본문 조회 실패 ({law_id}): {e}")
        return ""


def chunk_text(text: str, size: int = 1000, overlap: int = 100) -> list:
    chunks = []
    start = 0
    while start < len(text):
        chunks.append(text[start:min(start + size, len(text))])
        start += size - overlap
    return chunks


def index_laws(queries: list):
    """법제처 API → ChromaDB (LAW_API_OC 필요)"""
    collection = get_db()
    indexed = 0

    for query in queries:
        print(f"\n[검색] '{query}'...")
        laws = _api_search_laws(query)

        for law in laws:
            law_id   = law.get("법령일련번호", "")
            law_name = law.get("법령명한글", "")
            pub_date = law.get("공포일자", "")
            if not law_id:
                continue

            existing = collection.get(ids=[f"{law_id}_chunk_0"])
            if existing["ids"]:
                print(f"  ⏭ 이미 인덱싱됨: {law_name}")
                continue

            print(f"  📄 인덱싱: {law_name} ({pub_date})")
            content = _api_get_law_content(law_id) or f"{law_name} — {law.get('소관부처명', '')}"

            for i, chunk in enumerate(chunk_text(content)):
                collection.add(
                    documents=[chunk],
                    metadatas=[{
                        "source":    law_id,
                        "law_name":  law_name,
                        "pub_date":  pub_date,
                        "title":     law_name,
                        "type":      "law_api",
                        "chunk":     i,
                    }],
                    ids=[f"{law_id}_chunk_{i}"],
                )
            indexed += 1
            time.sleep(0.3)

    print(f"\n✅ 인덱싱 완료: {indexed}개 법령  |  DB: {DB_PATH}")


# ── 질의 + Gemini 합성 ───────────────────────────────────────
def ask(question: str, law_filter: str = "", n_results: int = 6):
    collection = get_db()

    if collection.count() == 0:
        print("⚠️  인덱싱된 데이터 없음. 먼저 실행하세요:")
        print("   python3 law_rag.py --seed")
        sys.exit(1)

    # 검색
    query_kwargs = dict(query_texts=[question], n_results=n_results)
    if law_filter:
        query_kwargs["where_document"] = {"$contains": law_filter}

    try:
        results = collection.query(**query_kwargs)
    except Exception:
        # where_document 미지원 버전 대비 fallback
        results = collection.query(query_texts=[question], n_results=n_results * 2)

    docs      = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]

    # law_filter 후처리 필터
    if law_filter and docs:
        pairs = [
            (d, m) for d, m in zip(docs, metadatas)
            if law_filter in m.get("title", "") or
               law_filter in m.get("source", "") or
               law_filter in m.get("law_name", "") or
               law_filter in d
        ]
        if pairs:
            docs, metadatas = zip(*pairs)
        # 필터 후 결과 없으면 원본 유지

    if not docs:
        print("관련 법령/기준을 찾지 못했습니다.")
        return

    # 컨텍스트 조립
    context_parts = []
    print(f"\n📚 '{question}' 관련 참고 자료:\n")
    print("─" * 50)
    for i, (doc, meta) in enumerate(zip(docs, metadatas)):
        title = meta.get("title") or meta.get("law_name") or meta.get("source", "")
        src   = meta.get("source_file") or meta.get("type", "")
        print(f"[{i+1}] {title}  ({src})")
        print(f"{doc[:200]}...")
        print()
        context_parts.append(f"[{title}]\n{doc}")

    context = "\n\n".join(context_parts)
    print("─" * 50)

    # Gemini 합성
    print("\n🤖 Gemini 답변 합성 중...\n")
    prompt = f"""다음 법령·회계기준 내용을 참고하여 질문에 전문적으로 답변해줘.

## 참고 자료
{context}

## 질문
{question}

답변 형식:
1. 핵심 답변 (조문·기준 근거 명시)
2. 관련 조문·기준 번호
3. 실무 적용 시 주의사항 (있는 경우)"""

    result = subprocess.run(
        ["gemini", "--yolo", "-p", prompt],
        capture_output=True, text=True, timeout=90,
    )

    if result.returncode == 0:
        output = result.stdout.strip()
        # YOLO 헤더 제거
        lines = [l for l in output.split("\n")
                 if not l.startswith("YOLO") and
                    not l.startswith("Loaded") and
                    not l.startswith("Error getting")]
        print("\n".join(lines).strip())
    else:
        print(f"[Gemini 오류] {result.stderr[:300]}")


# ── 목록 ────────────────────────────────────────────────────
def list_indexed():
    collection = get_db()
    all_items = collection.get()
    total = len(all_items.get("ids", []))

    if total == 0:
        print("인덱싱된 데이터 없음. 실행: python3 law_rag.py --seed")
        return

    sources = {}
    for meta in all_items.get("metadatas", []):
        if not meta:
            continue
        src  = meta.get("source_file") or meta.get("law_name") or meta.get("source", "?")
        kind = meta.get("type", "?")
        sources.setdefault(kind, set()).add(src)

    print(f"\n📚 인덱싱 현황 (총 {total}개 청크)\n")
    for kind, srcs in sorted(sources.items()):
        label = "knowledge 파일" if kind == "knowledge" else "법제처 API 법령"
        print(f"  [{label}] {len(srcs)}건")
        for s in sorted(srcs):
            print(f"    • {s}")


# ── 개정 확인 ────────────────────────────────────────────────
def update_laws():
    if not LAW_API_OC:
        print("[ERROR] LAW_API_OC 환경변수 필요")
        sys.exit(1)

    collection = get_db()
    all_items = collection.get()

    law_ids = set()
    for meta in all_items.get("metadatas", []):
        if meta and meta.get("type") == "law_api":
            law_ids.add(meta.get("source", ""))
    law_ids.discard("")

    print(f"법제처 API 법령 {len(law_ids)}개 개정 확인 중...")
    updated = 0
    for law_id in law_ids:
        try:
            import requests as req
            r = req.get(f"{LAW_BASE_URL}/lawService.do",
                        params={"OC": LAW_API_OC, "target": "law", "type": "JSON", "ID": law_id},
                        timeout=10)
            data = r.json()
            new_date = data.get("법령", {}).get("기본정보", {}).get("공포일자", "")
            ex = collection.get(ids=[f"{law_id}_chunk_0"])
            if ex["metadatas"] and ex["metadatas"][0]:
                old_date = ex["metadatas"][0].get("pub_date", "")
                if new_date and new_date != old_date:
                    print(f"  🔄 개정: {law_id} ({old_date} → {new_date})")
                    updated += 1
            time.sleep(0.3)
        except Exception:
            pass

    print(f"\n업데이트 필요: {updated}개")
    if updated:
        print("  '--index' 로 재인덱싱하세요.")


# ── 메인 ────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="한국 법령·회계기준 RAG")
    parser.add_argument("--seed",   "-s", action="store_true",
                        help="knowledge/*.md 파일 인덱싱 (API key 불필요)")
    parser.add_argument("--index",  "-i", action="store_true",
                        help="법제처 API로 법령 인덱싱 (LAW_API_OC 필요)")
    parser.add_argument("--query",  "-q", type=str,
                        help="--index 시 검색할 법령 목록 (쉼표 구분)")
    parser.add_argument("--ask",    "-a", type=str, help="법령 질의")
    parser.add_argument("--law",    "-l", type=str, default="",
                        help="특정 법령·기준으로 필터 (예: 소득세법, vat, 조특)")
    parser.add_argument("--update", "-u", action="store_true", help="개정 확인")
    parser.add_argument("--list",         action="store_true", help="인덱싱 현황")
    args = parser.parse_args()

    if not any([args.seed, args.index, args.ask, args.update, args.list]):
        parser.print_help()
        return

    if args.list:
        list_indexed()
    elif args.seed:
        seed_from_knowledge()
    elif args.index:
        if not LAW_API_OC:
            print("[ERROR] LAW_API_OC 환경변수 필요")
            print("  export LAW_API_OC='이메일ID'  (open.law.go.kr 가입 후)")
            sys.exit(1)
        default_q = "소득세법,법인세법,부가가치세법,상법,조세특례제한법,국세기본법,상속세및증여세법"
        queries = [q.strip() for q in (args.query or default_q).split(",") if q.strip()]
        index_laws(queries)
    elif args.ask:
        ask(args.ask, law_filter=args.law)
    elif args.update:
        update_laws()


if __name__ == "__main__":
    main()
