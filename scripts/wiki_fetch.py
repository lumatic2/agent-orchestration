#!/usr/bin/env python3
"""Wikipedia 요약을 vault에 저장하는 유틸리티.

사용법:
  python3 wiki_fetch.py "기업가치" --domain investment
  python3 wiki_fetch.py "GPT-4" --domain tech --append-to ~/vault/10-knowledge/tech/note.md
  python3 wiki_fetch.py "양자컴퓨터" --domain tech --lang en
"""
from __future__ import annotations
import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple

VAULT_BASE = Path.home() / "vault"


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": "vault-wiki-bot/1.0"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def _summary_from_title(title: str, lang: str) -> Optional[Tuple[str, str, str]]:
    """제목으로 직접 요약 조회"""
    try:
        url = (
            f"https://{lang}.wikipedia.org/api/rest_v1/page/summary/"
            f"{urllib.parse.quote(title.replace(' ', '_'), safe='')}"
        )
        page = _get(url)
        extract = page.get("extract", "").strip()
        if not extract:
            return None
        page_url = (
            page.get("content_urls", {}).get("desktop", {}).get("page")
            or f"https://{lang}.wikipedia.org/wiki/{urllib.parse.quote(title.replace(' ', '_'))}"
        )
        return page.get("title", title), extract, page_url
    except Exception:
        return None


def search_wikipedia(query: str, lang: str = "ko") -> Optional[Tuple[str, str, str]]:
    """(title, extract, url) 반환, 실패 시 None.
    우선순위: 직접 제목 조회 → opensearch 결과 조회"""
    # 1. 직접 제목 조회 (정확도 최고)
    direct = _summary_from_title(query, lang)
    if direct:
        return direct

    # 2. opensearch fallback
    try:
        search_url = (
            f"https://{lang}.wikipedia.org/w/api.php"
            f"?action=opensearch&search={urllib.parse.quote(query)}&limit=5&format=json"
        )
        data = _get(search_url)
        titles = data[1] if len(data) > 1 else []
        for title in titles:
            result = _summary_from_title(title, lang)
            if result:
                return result
        return None
    except Exception as e:
        print(f"[Wikipedia/{lang}] 검색 실패: {e}", file=sys.stderr)
        return None


def fetch_and_save(topic: str, domain: str, lang: str = "auto", append_to: Optional[str] = None) -> bool:
    today = datetime.now().strftime("%Y-%m-%d")

    if lang == "auto":
        result = search_wikipedia(topic, "ko") or search_wikipedia(topic, "en")
    else:
        result = search_wikipedia(topic, lang)

    if not result:
        print(f"[Wikipedia] '{topic}' 검색 결과 없음", file=sys.stderr)
        return False

    title, extract, url = result
    if len(extract) > 500:
        extract = extract[:497] + "..."

    wiki_section = f"## Wikipedia: {title}\n\n> 출처: {url}\n\n{extract}\n"

    if append_to:
        path = Path(append_to).expanduser()
        if not path.exists():
            print(f"[Wikipedia] 파일 없음: {path}", file=sys.stderr)
            return False
        existing = path.read_text(encoding="utf-8")
        path.write_text(existing.rstrip() + "\n\n---\n\n" + wiki_section, encoding="utf-8")
        print(f"[Wikipedia] '{title}' → 기존 노트에 추가: {path}")
        return True

    vault_dir = VAULT_BASE / "10-knowledge" / domain
    vault_dir.mkdir(parents=True, exist_ok=True)
    slug = topic.replace(" ", "-").replace("/", "-").lower()
    out_path = vault_dir / f"{slug}_wiki_{today}.md"
    note = (
        f"---\ntype: knowledge\ndomain: {domain}\nsource: wikipedia\n"
        f"date: {today}\nstatus: inbox\ntopic: {topic}\n---\n\n{wiki_section}"
    )
    out_path.write_text(note, encoding="utf-8")
    print(f"[Wikipedia] 저장 완료: {out_path}")
    return True


def main():
    parser = argparse.ArgumentParser(description="Wikipedia 요약을 vault에 저장")
    parser.add_argument("topic", help="검색할 주제")
    parser.add_argument("--domain", default="research", help="vault 도메인 (기본: research)")
    parser.add_argument("--lang", default="auto", choices=["auto", "ko", "en"])
    parser.add_argument("--append-to", metavar="FILE", help="기존 vault 노트에 추가")
    args = parser.parse_args()
    sys.exit(0 if fetch_and_save(args.topic, args.domain, args.lang, args.append_to) else 1)


if __name__ == "__main__":
    main()
