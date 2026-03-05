"""
law_rag.py — 법제처 API + ChromaDB 기반 한국 법령 RAG 에이전트

사용법:
  # 1. 법령 인덱싱 (처음 한 번)
  python3 law_rag.py --index --query "소득세법,법인세법,부가가치세법,상법,K-IFRS"

  # 2. 법령 질의
  python3 law_rag.py --ask "소득세법상 원천징수 세율은?"

  # 3. 개정 업데이트 (주기적으로 실행)
  python3 law_rag.py --update

환경변수:
  LAW_API_OC   — 법제처 API 인증키 (open.law.go.kr 이메일 ID)
"""

import os
import sys
import json
import time
import argparse
import requests
import chromadb
from chromadb.utils import embedding_functions

# ── 설정 ──────────────────────────────────────────────
LAW_API_OC   = os.environ.get("LAW_API_OC", "")          # 법제처 API 인증키
LAW_BASE_URL = "https://www.law.go.kr/DRF"
DB_PATH      = os.path.expanduser("~/knowledge-vault/law_chroma_db")
COLLECTION   = "korean_laws"

# 한국어 임베딩 모델 (로컬, 무료)
EMBED_MODEL = "jhgan/ko-sroberta-multitask"

# 기본 법령 목록 (확장 가능)
DEFAULT_LAWS = [
    "소득세법", "법인세법", "부가가치세법", "국세기본법",
    "조세특례제한법", "상속세및증여세법", "종합부동산세법",
    "상법", "자본시장법", "외부감사법",
    "중소기업기본법", "근로기준법",
]


# ── ChromaDB 클라이언트 ────────────────────────────────
def get_db():
    os.makedirs(DB_PATH, exist_ok=True)
    ef = embedding_functions.SentenceTransformerEmbeddingFunction(
        model_name=EMBED_MODEL
    )
    client = chromadb.PersistentClient(path=DB_PATH)
    collection = client.get_or_create_collection(
        name=COLLECTION,
        embedding_function=ef,
        metadata={"hnsw:space": "cosine"},
    )
    return collection


# ── 법제처 API 호출 ────────────────────────────────────
def search_laws(query: str, page: int = 1) -> list:
    """법령 목록 검색"""
    if not LAW_API_OC:
        print("[ERROR] LAW_API_OC 환경변수를 설정하세요.")
        print("  export LAW_API_OC='이메일아이디'  (open.law.go.kr 가입 후 발급)")
        return []

    url = f"{LAW_BASE_URL}/lawSearch.do"
    params = {
        "OC": LAW_API_OC,
        "target": "law",
        "type": "JSON",
        "query": query,
        "page": page,
        "display": 20,
        "sort": "lasc",
    }
    try:
        r = requests.get(url, params=params, timeout=10)
        r.raise_for_status()
        data = r.json()
        laws = data.get("LawSearch", {}).get("law", [])
        return laws if isinstance(laws, list) else [laws]
    except Exception as e:
        print(f"[ERROR] 법령 검색 실패: {e}")
        return []


def get_law_content(law_id: str) -> str:
    """법령 본문 조회"""
    url = f"{LAW_BASE_URL}/lawService.do"
    params = {
        "OC": LAW_API_OC,
        "target": "law",
        "type": "JSON",
        "ID": law_id,
    }
    try:
        r = requests.get(url, params=params, timeout=15)
        r.raise_for_status()
        data = r.json()
        # 조문 내용 추출
        articles = data.get("법령", {}).get("조문", {}).get("조문단위", [])
        if isinstance(articles, dict):
            articles = [articles]
        texts = []
        for a in articles:
            title = a.get("조문제목", "")
            content = a.get("조문내용", "")
            if content:
                texts.append(f"{title}\n{content}")
        return "\n\n".join(texts)
    except Exception as e:
        print(f"[ERROR] 본문 조회 실패 (ID={law_id}): {e}")
        return ""


# ── 인덱싱 ─────────────────────────────────────────────
def index_laws(queries: list):
    """법령 검색 → 본문 조회 → ChromaDB 저장"""
    collection = get_db()
    indexed = 0

    for query in queries:
        print(f"\n[검색] '{query}'...")
        laws = search_laws(query)

        for law in laws:
            law_id   = law.get("법령일련번호", "")
            law_name = law.get("법령명한글", "")
            pub_date = law.get("공포일자", "")

            if not law_id:
                continue

            # 이미 인덱싱된 경우 스킵
            existing = collection.get(ids=[law_id])
            if existing["ids"]:
                print(f"  ⏭ 이미 인덱싱됨: {law_name}")
                continue

            print(f"  📄 인덱싱: {law_name} ({pub_date})")
            content = get_law_content(law_id)

            if not content:
                # 본문 없으면 메타데이터만 저장
                content = f"{law_name} — {law.get('소관부처명', '')}"

            # 긴 법령은 청크로 분할
            chunks = chunk_text(content, chunk_size=1000, overlap=100)
            for i, chunk in enumerate(chunks):
                chunk_id = f"{law_id}_chunk_{i}"
                collection.add(
                    documents=[chunk],
                    metadatas=[{
                        "law_id": law_id,
                        "law_name": law_name,
                        "pub_date": pub_date,
                        "chunk": i,
                    }],
                    ids=[chunk_id],
                )

            indexed += 1
            time.sleep(0.3)  # API 부하 방지

    print(f"\n✅ 인덱싱 완료: {indexed}개 법령")
    print(f"   DB 위치: {DB_PATH}")


def chunk_text(text: str, chunk_size: int = 1000, overlap: int = 100) -> list:
    """텍스트를 청크로 분할"""
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + chunk_size, len(text))
        chunks.append(text[start:end])
        start += chunk_size - overlap
    return chunks


# ── 질의 ───────────────────────────────────────────────
def ask(question: str, n_results: int = 5):
    """RAG 질의 — 관련 법령 조문 검색 후 컨텍스트 반환"""
    collection = get_db()

    results = collection.query(
        query_texts=[question],
        n_results=n_results,
    )

    docs      = results.get("documents", [[]])[0]
    metadatas = results.get("metadatas", [[]])[0]

    if not docs:
        print("관련 법령을 찾지 못했습니다.")
        return

    print(f"\n📚 '{question}'에 관련된 법령 조문:\n")
    print("─" * 60)

    for i, (doc, meta) in enumerate(zip(docs, metadatas)):
        print(f"[{i+1}] {meta.get('law_name', '알 수 없음')} (공포일: {meta.get('pub_date','')})")
        print(f"{doc[:300]}...")
        print()

    # Claude API로 답변 생성 (선택)
    context = "\n\n".join([
        f"[{meta.get('law_name')}]\n{doc}"
        for doc, meta in zip(docs, metadatas)
    ])
    print("─" * 60)
    print("\n💡 위 조문을 Claude에 붙여넣어 전문적인 답변을 받으세요.")
    print(f"\n컨텍스트 길이: {len(context)}자")

    return context


# ── 업데이트 ────────────────────────────────────────────
def update_laws():
    """인덱싱된 법령의 최신 개정 확인"""
    collection = get_db()
    all_items = collection.get()

    law_ids = set()
    for meta in all_items.get("metadatas", []):
        if meta:
            law_ids.add(meta.get("law_id", ""))

    print(f"현재 인덱싱된 법령 ID: {len(law_ids)}개")
    print("법제처 API로 개정 여부 확인 중...")

    updated = 0
    for law_id in law_ids:
        if not law_id:
            continue
        # 현재 버전과 API 버전 비교
        url = f"{LAW_BASE_URL}/lawService.do"
        params = {"OC": LAW_API_OC, "target": "law", "type": "JSON", "ID": law_id}
        try:
            r = requests.get(url, params=params, timeout=10)
            data = r.json()
            new_date = data.get("법령", {}).get("기본정보", {}).get("공포일자", "")

            # DB의 기존 날짜와 비교
            existing = collection.get(ids=[f"{law_id}_chunk_0"])
            if existing["metadatas"] and existing["metadatas"][0]:
                old_date = existing["metadatas"][0].get("pub_date", "")
                if new_date and new_date != old_date:
                    print(f"  🔄 개정 감지: {law_id} ({old_date} → {new_date})")
                    updated += 1

            time.sleep(0.3)
        except:
            pass

    print(f"\n업데이트 필요: {updated}개 법령")
    if updated > 0:
        print("  '--index' 옵션으로 재인덱싱하세요.")


# ── 메인 ───────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(description="한국 법령 RAG 에이전트")
    parser.add_argument("--index",  "-i", action="store_true",  help="법령 인덱싱")
    parser.add_argument("--query",  "-q", type=str, default=",".join(DEFAULT_LAWS),
                        help="인덱싱할 법령 검색어 (쉼표 구분)")
    parser.add_argument("--ask",    "-a", type=str, help="법령 질의")
    parser.add_argument("--update", "-u", action="store_true",  help="개정 확인")
    parser.add_argument("--list",   "-l", action="store_true",  help="인덱싱된 법령 목록")
    args = parser.parse_args()

    if not any([args.index, args.ask, args.update, args.list]):
        parser.print_help()
        return

    if args.list:
        collection = get_db()
        all_items = collection.get()
        names = set()
        for meta in all_items.get("metadatas", []):
            if meta:
                names.add(meta.get("law_name", ""))
        print(f"인덱싱된 법령 ({len(names)}개):")
        for n in sorted(names):
            print(f"  • {n}")

    elif args.index:
        queries = [q.strip() for q in args.query.split(",") if q.strip()]
        index_laws(queries)

    elif args.ask:
        ask(args.ask)

    elif args.update:
        update_laws()


if __name__ == "__main__":
    main()
