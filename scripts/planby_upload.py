#!/usr/bin/env python3
"""
planby_upload.py — AnythingLLM 워크스페이스 자동 분류 업로드

사용법:
  python3 planby_upload.py <파일경로>               # 자동 분류 (이미지PDF → vision 자동 추출)
  python3 planby_upload.py <파일경로> <워크스페이스>  # 수동 지정
  python3 planby_upload.py --list                  # 워크스페이스별 문서 수 확인
  python3 planby_upload.py --vision-batch <폴더>   # 폴더 내 이미지PDF 일괄 변환 업로드

워크스페이스: 기준 | 재무세무 | 전략영업 | 회의초안

PDF 처리 전략:
  - 텍스트 PDF: pymupdf로 직접 추출 → 마크다운 업로드
  - 이미지 PDF: Vision API(Gemini/Claude)로 OCR → 마크다운 업로드
  - Vision API 사용 시 GEMINI_API_KEY 또는 ANTHROPIC_API_KEY 환경변수 필요
"""

import sys
import os
import json
import base64
import unicodedata
import urllib.request
import tempfile

ANYTHINGLLM_KEY = "planby-cb99f5222e56c3ed40d98c77e35bf001"
BASE_URL = "http://localhost:3001/api/v1"

WS = {
    "기준":    "0fb026cf-455b-40b9-911e-33ba8c63dbaa",
    "재무세무": "51656bcc-e741-4e16-8094-4c813fe259bf",
    "전략영업": "0e6792e6-bc20-4e49-9d24-91af61bbf5fb",
    "회의초안": "497efbac-31d9-4864-8d53-98a49437d51e",
}

WS_DISPLAY = {
    "기준":    "플랜바이 기준 문서",
    "재무세무": "플랜바이 재무, 세무",
    "전략영업": "플랜바이 전략, 영업",
    "회의초안": "플랜바이 회의, 초안",
}

VISION_PROMPT = (
    "이 슬라이드/문서 이미지에서 모든 텍스트를 추출해줘. "
    "제목, 소제목, 본문, 수치, 표, 레이블을 마크다운 형식으로 구조 그대로 정리해줘. "
    "이미지 설명이나 주석 없이 텍스트 내용만 출력해."
)


# ── 유틸 ──────────────────────────────────────────────────────────────────────

def n(s):
    return unicodedata.normalize("NFC", s)


def classify(title: str) -> str:
    t = n(title)
    if any(n(x) in t for x in [
        "재무", "법인세", "자본변동", "계좌", "은행", "카드", "매출 정산", "매입 정산",
        "현금흐름", "계정별원장", "재무제표", "tax_", "세금계산서", "가결산", "라벨",
        "급여", "원천세", "부가세", "회계", "결산", "손익", "대차", "분개",
    ]):
        return "재무세무"
    if any(n(x) in t for x in [
        "정관", "서비스소개서", "서비스_소개서", "회사소개서", "솔루션_소개", "솔루션 소개",
        "tips_agreement", "TIPS", "PLAD", "service_en", "service_kr", "service_intro",
        "solution_cases", "계약서", "약관", "정책", "지침",
    ]):
        return "기준"
    if any(n(x) in t for x in [
        "IR", "Pitch", "pitch", "경영", "PLANA", "포스코", "Posco", "POSCO", "DIPS",
        "딥테크", "사업계획", "신청서", "공모전", "제안서", "고객", "파이프라인",
        "전략", "영업", "OKR",
    ]):
        return "전략영업"
    if any(n(x) in t for x in [
        "인터뷰", "interview", "키워드", "keywords", "회의", "메모", "초안", "draft", "DRAFT",
    ]):
        return "회의초안"
    return "기준"


# ── AnythingLLM API ──────────────────────────────────────────────────────────

def api_get(path):
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        headers={"Authorization": f"Bearer {ANYTHINGLLM_KEY}"}
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def api_post_json(path, body):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        f"{BASE_URL}{path}", data=data,
        headers={"Authorization": f"Bearer {ANYTHINGLLM_KEY}", "Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


def api_upload_file(file_path, upload_filename=None):
    """AnythingLLM에 파일 업로드 (multipart/form-data)"""
    if not upload_filename:
        upload_filename = os.path.basename(file_path)

    boundary = "----PlanbyUploadBoundary"
    with open(file_path, "rb") as f:
        file_data = f.read()

    body = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="file"; filename="{upload_filename}"\r\n'
        f"Content-Type: application/octet-stream\r\n\r\n"
    ).encode() + file_data + f"\r\n--{boundary}--\r\n".encode()

    req = urllib.request.Request(
        f"{BASE_URL}/document/upload", data=body,
        headers={
            "Authorization": f"Bearer {ANYTHINGLLM_KEY}",
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        }
    )
    with urllib.request.urlopen(req) as r:
        return json.loads(r.read())


# ── PDF 처리 ──────────────────────────────────────────────────────────────────

def is_image_pdf(pdf_path: str) -> bool:
    """PDF가 이미지 전용인지 확인 (텍스트 레이어 없음)"""
    import fitz
    doc = fitz.open(pdf_path)
    total_chars = sum(len(doc[i].get_text().strip()) for i in range(min(3, len(doc))))
    doc.close()
    return total_chars < 100


def pdf_to_markdown_text(pdf_path: str) -> str | None:
    """텍스트 PDF: pymupdf로 직접 추출"""
    import fitz
    doc = fitz.open(pdf_path)
    pages = []
    for i, page in enumerate(doc, 1):
        text = page.get_text().strip()
        if text:
            pages.append(f"## Page {i}\n\n{text}")
    doc.close()
    return "\n\n---\n\n".join(pages) if pages else None


def extract_page_image(pdf_path: str, page_num: int) -> bytes:
    """PDF 특정 페이지를 PNG bytes로 변환"""
    import fitz
    doc = fitz.open(pdf_path)
    page = doc[page_num]
    mat = fitz.Matrix(2, 2)  # 2x 해상도
    pix = page.get_pixmap(matrix=mat)
    doc.close()
    return pix.tobytes("png")


def vision_extract_gemini(image_bytes: bytes) -> str:
    """Gemini Vision API로 텍스트 추출"""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY 환경변수가 설정되지 않았습니다")

    payload = {
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/png",
                                 "data": base64.standard_b64encode(image_bytes).decode()}},
                {"text": VISION_PROMPT}
            ]
        }],
        "generationConfig": {"temperature": 0}
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={api_key}",
        data=data,
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        result = json.loads(r.read())
    return result["candidates"][0]["content"]["parts"][0]["text"]


def vision_extract_claude(image_bytes: bytes) -> str:
    """Claude Vision API로 텍스트 추출"""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise RuntimeError("ANTHROPIC_API_KEY 환경변수가 설정되지 않았습니다")

    payload = {
        "model": "claude-haiku-4-5-20251001",
        "max_tokens": 4096,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image", "source": {
                    "type": "base64", "media_type": "image/png",
                    "data": base64.standard_b64encode(image_bytes).decode()
                }},
                {"type": "text", "text": VISION_PROMPT}
            ]
        }]
    }
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=data,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        result = json.loads(r.read())
    return result["content"][0]["text"]


def vision_extract_page(image_bytes: bytes) -> str:
    """사용 가능한 Vision API로 텍스트 추출 (Gemini 우선)"""
    if os.environ.get("GEMINI_API_KEY"):
        return vision_extract_gemini(image_bytes)
    elif os.environ.get("ANTHROPIC_API_KEY"):
        return vision_extract_claude(image_bytes)
    else:
        raise RuntimeError(
            "Vision API 키가 없습니다.\n"
            "  Gemini: export GEMINI_API_KEY=... (~/.zshenv에 추가)\n"
            "    발급: https://aistudio.google.com/app/apikey\n"
            "  Claude: export ANTHROPIC_API_KEY=... (~/.zshenv에 추가)\n"
            "    발급: https://console.anthropic.com/settings/keys"
        )


def pdf_to_markdown_vision(pdf_path: str) -> str:
    """이미지 PDF: Vision API로 페이지별 OCR → 마크다운"""
    import fitz
    doc = fitz.open(pdf_path)
    total_pages = len(doc)
    doc.close()

    pages = []
    for i in range(total_pages):
        print(f"  Vision OCR: {i+1}/{total_pages}페이지...", end="\r")
        image_bytes = extract_page_image(pdf_path, i)
        text = vision_extract_page(image_bytes).strip()
        if text:
            pages.append(f"## Page {i+1}\n\n{text}")

    print()  # 줄바꿈
    return "\n\n---\n\n".join(pages) if pages else ""


def pdf_to_markdown(pdf_path: str, force_vision: bool = False) -> tuple[str | None, str]:
    """
    PDF를 마크다운으로 변환.
    returns: (markdown_text or None, method)
    method: 'text' | 'vision' | 'empty'
    """
    import fitz  # noqa

    if not force_vision and not is_image_pdf(pdf_path):
        md = pdf_to_markdown_text(pdf_path)
        if md:
            return md, "text"

    # 이미지 PDF → Vision
    try:
        md = pdf_to_markdown_vision(pdf_path)
        return (md or None), "vision"
    except RuntimeError as e:
        print(f"  Vision 불가: {e}")
        return None, "empty"


# ── 커맨드 ────────────────────────────────────────────────────────────────────

def cmd_list():
    ws_list = api_get("/workspaces")["workspaces"]
    print("=== AnythingLLM 워크스페이스 현황 ===")
    for ws in ws_list:
        if "플랜바이" in ws["name"]:
            detail = api_get(f"/workspace/{ws['slug']}")
            ws_data = detail.get("workspace", [])
            if isinstance(ws_data, list):
                ws_data = ws_data[0] if ws_data else {}
            count = len(ws_data.get("documents", []))
            print(f"  {ws['name']}: {count}개")


def cmd_upload(file_path, manual_ws=None):
    if not os.path.isfile(file_path):
        print(f"오류: 파일을 찾을 수 없습니다 — {file_path}")
        sys.exit(1)

    filename = os.path.basename(file_path)

    if manual_ws:
        if manual_ws not in WS:
            print(f"오류: 알 수 없는 워크스페이스 '{manual_ws}'")
            print(f"      선택 가능: {' | '.join(WS.keys())}")
            sys.exit(1)
        ws_key = manual_ws
        print(f"수동 지정: {filename} → [{ws_key}]")
    else:
        ws_key = classify(filename)
        print(f"자동 분류: {filename} → [{ws_key}] ({WS_DISPLAY[ws_key]})")

    # PDF 전처리
    upload_path = file_path
    upload_filename = filename
    tmp_path = None

    if file_path.lower().endswith(".pdf"):
        try:
            import fitz  # noqa
        except ImportError:
            print("  경고: pymupdf 없음, 원본 PDF 업로드")
        else:
            md_text, method = pdf_to_markdown(file_path)
            if md_text:
                upload_filename = os.path.splitext(filename)[0] + ".md"
                tmp = tempfile.NamedTemporaryFile(
                    mode="w", suffix=".md", delete=False, encoding="utf-8"
                )
                tmp.write(f"# {os.path.splitext(filename)[0]}\n\n{md_text}")
                tmp.close()
                upload_path = tmp.name
                tmp_path = tmp.name
                tag = "텍스트추출" if method == "text" else "Vision OCR"
                print(f"  PDF → 마크다운 [{tag}] ({len(md_text):,}자)")
            else:
                print("  텍스트 추출 실패, 원본 PDF 업로드")

    # 업로드
    print("업로드 중...")
    try:
        result = api_upload_file(upload_path, upload_filename)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    if not result.get("success"):
        print(f"업로드 실패: {result.get('error', '알 수 없는 오류')}")
        sys.exit(1)

    docs = result.get("documents", [])
    if not docs:
        print("오류: 업로드 후 문서 정보를 가져오지 못했습니다")
        sys.exit(1)

    doc_location = docs[0].get("location", "")
    if not doc_location:
        print(f"오류: location 없음\n{json.dumps(docs[0], ensure_ascii=False, indent=2)}")
        sys.exit(1)

    # 워크스페이스 임베딩
    slug = WS[ws_key]
    print(f"[{WS_DISPLAY[ws_key]}] 임베딩 추가 중...")
    api_post_json(f"/workspace/{slug}/update-embeddings", {"adds": [doc_location], "deletes": []})
    print(f"완료: {filename} → [{ws_key}]")


def cmd_vision_batch(folder_path):
    """폴더 내 이미지 PDF 일괄 Vision OCR → 업로드"""
    if not os.path.isdir(folder_path):
        print(f"오류: 폴더를 찾을 수 없습니다 — {folder_path}")
        sys.exit(1)

    try:
        import fitz  # noqa
    except ImportError:
        print("오류: pymupdf가 필요합니다. pip3 install pymupdf --break-system-packages")
        sys.exit(1)

    pdfs = [
        os.path.join(folder_path, f)
        for f in os.listdir(folder_path)
        if f.lower().endswith(".pdf")
    ]

    if not pdfs:
        print("PDF 파일이 없습니다.")
        return

    image_pdfs = [p for p in pdfs if is_image_pdf(p)]
    print(f"총 {len(pdfs)}개 PDF 중 이미지PDF {len(image_pdfs)}개 처리\n")

    for path in image_pdfs:
        print(f"▶ {os.path.basename(path)}")
        cmd_upload(path)
        print()


def main():
    args = sys.argv[1:]

    if not args or args[0] in ("-h", "--help"):
        print(__doc__)
        sys.exit(0)

    if args[0] == "--list":
        cmd_list()
        return

    if args[0] == "--vision-batch":
        folder = args[1] if len(args) > 1 else "."
        cmd_vision_batch(folder)
        return

    file_path = args[0]
    manual_ws = args[1] if len(args) > 1 else None
    cmd_upload(file_path, manual_ws)


if __name__ == "__main__":
    main()
