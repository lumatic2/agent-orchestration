from flask import Flask, request, jsonify, Response
from google import genai
from google.genai import types
import os, json, subprocess, urllib.request, datetime

# .env 파일에서 환경변수 로드
_env_path = os.path.join(os.path.dirname(__file__), '.env')
if os.path.exists(_env_path):
    for _line in open(_env_path, encoding='utf-8'):
        _line = _line.strip()
        if _line and not _line.startswith('#') and '=' in _line:
            _k, _v = _line.split('=', 1)
            os.environ.setdefault(_k.strip(), _v.strip())

app = Flask(__name__)

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')
client = None
history = []

SSH_HOSTS = {'windows': 'windows', 'macair': 'macair', 'm1': 'm1', 'm4': 'm4'}

NOTION_TOKEN = None
GANTT_DB_ID = '30785046-ff55-81bc-b093-dfbd85d74ac5'


def _notion_token():
    global NOTION_TOKEN
    if NOTION_TOKEN:
        return NOTION_TOKEN
    NOTION_TOKEN = os.environ.get('PERSONAL_NOTION_TOKEN', '')
    if not NOTION_TOKEN:
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, 'Environment')
            NOTION_TOKEN = winreg.QueryValueEx(key, 'PERSONAL_NOTION_TOKEN')[0]
        except Exception:
            pass
    return NOTION_TOKEN


def query_today_tasks() -> str:
    token = _notion_token()
    if not token:
        return '(Notion 토큰 없음)'
    today = datetime.date.today().isoformat()
    body = json.dumps({
        'page_size': 10,
        'filter': {
            'property': '시작 날짜',
            'date': {'on_or_before': today}
        },
        'sorts': [{'property': '시작 날짜', 'direction': 'descending'}]
    }).encode('utf-8')
    try:
        req = urllib.request.Request(
            f'https://api.notion.com/v1/databases/{GANTT_DB_ID}/query',
            data=body,
            headers={
                'Authorization': f'Bearer {token}',
                'Notion-Version': '2022-06-28',
                'Content-Type': 'application/json'
            }
        )
        res = urllib.request.urlopen(req, timeout=10)
        data = json.loads(res.read().decode('utf-8'))
        tasks = []
        for p in data.get('results', []):
            props = p['properties']
            name_parts = props.get('작업/프로젝트 이름', {}).get('title', [])
            name = name_parts[0]['plain_text'] if name_parts else '(이름없음)'
            status_obj = props.get('완료', {})
            status = status_obj.get('status', {}).get('name', '') if status_obj else ''
            tasks.append(f'- {name}' + (f' [{status}]' if status else ''))
        if not tasks:
            return f'오늘 기준 진행 중인 간트 차트 항목이 없어.'
        names = [t.replace('- ', '') for t in tasks[:5]]
        return f'간트 차트에 {len(tasks)}개 항목이 있어. {", ".join(names[:3])}' + ('등이야.' if len(names) > 3 else '야.')
    except Exception as e:
        return f'(Notion 조회 오류: {e})'

SYSTEM_PROMPT = """너는 '제이미'야. 갤럭시 S24 Ultra 개인 AI 비서. 반말로 친근하게 대화해.

반드시 아래 JSON만 출력해. 다른 텍스트 절대 포함 금지.
{"type":"TALK"|"PHONE"|"REMOTE"|"NOTION"|"END", "response":"TTS 응답(간결)", "action":null}

type 기준:
- TALK: 일반 대화, 질문, 정보 요청
- PHONE: 폰 직접 제어 (알람/전화/문자/앱/볼륨/밝기/와이파이/블루투스)
- REMOTE: windows/macair/m1/m4 기기에서 실행/확인. 기기 이름 언급 시 REMOTE.
- NOTION: 노션 조회/메모 관련. "할 일", "일정", "간트", "노션" 언급 시 NOTION. action: {"query":"today_tasks"|"memo", "content":"메모 내용(선택)"}
- END: 대화 종료. "종료", "그만", "꺼", "끝", "바이", "잘게" 등 종료 의도 시. response는 짧은 작별인사.

REMOTE 트리거 예시 (이런 말이 나오면 반드시 REMOTE):
- "M1에서 ~", "Windows에서 ~", "맥에서 ~" → REMOTE
- "파일 목록", "상태 확인", "로그 봐줘", "실행해줘" + 기기명 → REMOTE

PHONE action 예시:
alarm:  {"command":"alarm",  "time":"HH:MM", "op":"set"}
call:   {"command":"call",   "contact":"이름"}
volume: {"command":"volume", "type":"media", "level":5}
app:    {"command":"app",    "name":"앱이름"}

REMOTE action: {"target":"windows|macair|m1|m4", "payload":"사용자 의도 자연어"}"""

BASH_PROMPT = """아래 사용자 의도를 {target} 기기에서 실행할 bash 명령어 한 줄로만 출력해. 다른 텍스트 없이 명령어만.

기기 정보:
- windows: Git Bash, 유저 '1', 프로젝트 경로 C:/Users/1/Desktop/
- m1/macair: macOS, 유저 luma2, 프로젝트 경로 ~/Desktop/
- m4: macOS, 유저 luma3, 프로젝트 경로 ~/Desktop/

사용자 의도: {intent}"""

SUMMARY_PROMPT = """아래는 원격 기기에서 실행한 명령 결과야.
결과를 바탕으로 사용자에게 반말로 짧게 알려줘. 예: "M1 홈 폴더에 Desktop, projects, notion_db.py 등이 있어."
완전한 문장으로 끝내줘. JSON 금지. 텍스트만.

실행 결과:
"""


def intent_to_cmd(target: str, intent: str) -> str:
    prompt = BASH_PROMPT.format(target=target, intent=intent)
    try:
        resp = client.models.generate_content(
            model='gemini-2.5-flash',
            config=types.GenerateContentConfig(temperature=0.1, max_output_tokens=150),
            contents=[{"role": "user", "parts": [{"text": prompt}]}]
        )
        return resp.text.strip().strip('`').split('\n')[0]
    except Exception as e:
        return f'echo "명령 변환 실패: {e}"'


def ssh_run(host: str, cmd: str, timeout: int = 20) -> str:
    try:
        result = subprocess.run(
            ['ssh', '-o', 'ConnectTimeout=10', '-o', 'BatchMode=yes', host, cmd],
            capture_output=True, timeout=timeout
        )
        output = (result.stdout + result.stderr).decode('utf-8', errors='replace').strip()
        return output[:2000] if output else '(출력 없음)'
    except subprocess.TimeoutExpired:
        return '(명령 타임아웃)'
    except Exception as e:
        return f'(SSH 오류: {e})'


def summarize(raw: str) -> str:
    try:
        resp = client.models.generate_content(
            model='gemini-2.5-flash',
            config=types.GenerateContentConfig(temperature=0.5, max_output_tokens=200),
            contents=[{"role": "user", "parts": [{"text": SUMMARY_PROMPT + raw}]}]
        )
        return resp.text.strip()
    except Exception:
        return raw[:200]


@app.route('/jamie', methods=['POST'])
def jamie():
    global history, client

    data = request.json
    user_text = data.get('text', '').strip()
    if not user_text:
        return Response(json.dumps({"type": "TALK", "response": "뭐라고?", "action": None}, ensure_ascii=False), mimetype='application/json')

    if client is None:
        api_key = GEMINI_API_KEY or data.get('api_key', '')
        client = genai.Client(api_key=api_key)

    # 종료 키워드 직접 감지 (Gemini 거치지 않음)
    END_KEYWORDS = ['종료', '그만', '꺼줘', '꺼', '끝내', '바이', '잘게', '닫아']
    if any(kw in user_text for kw in END_KEYWORDS):
        return Response(json.dumps({"type": "END", "response": "알겠어, 종료할게~", "action": None}, ensure_ascii=False), mimetype='application/json')

    history.append({"role": "user", "parts": [{"text": user_text}]})
    if len(history) > 6:
        history = history[-6:]

    try:
        response = client.models.generate_content(
            model='gemini-2.5-flash',
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_PROMPT,
                response_mime_type='application/json',
                temperature=0.7,
                max_output_tokens=512,
            ),
            contents=history
        )
        result = json.loads(response.text)
    except Exception as e:
        return jsonify({"type": "TALK", "response": "오류가 났어. 다시 말해줘.", "action": None, "error": str(e)})

    # REMOTE: 자연어 payload → bash 명령어 변환 → SSH 실행 → 요약
    _dbg = open('C:/Users/1/Desktop/jamie/debug.log', 'a', encoding='utf-8')
    _dbg.write(f"type={result.get('type')} action_type={type(result.get('action')).__name__} action={result.get('action')}\n")
    _dbg.flush()
    if result.get('type') == 'REMOTE' and isinstance(result.get('action'), dict):
        action = result['action']
        target = action.get('target', '')
        intent = action.get('payload', '') or action.get('cmd', '')
        _dbg.write(f"target={target!r} intent={intent!r} in_hosts={target in SSH_HOSTS}\n")
        _dbg.flush()
        if target in SSH_HOSTS and intent:
            cmd = intent_to_cmd(target, intent)
            _dbg.write(f"cmd={cmd!r}\n")
            _dbg.flush()
            raw = ssh_run(SSH_HOSTS[target], cmd)
            _dbg.write(f"raw={raw[:300]!r}\n")
            _dbg.flush()
            result['response'] = summarize(raw)
            result['action']['cmd_executed'] = cmd
    _dbg.close()

    # NOTION: 간트 차트 조회
    if result.get('type') == 'NOTION':
        action = result.get('action') or {}
        query = action.get('query', 'today_tasks') if isinstance(action, dict) else 'today_tasks'
        if query == 'today_tasks':
            result['response'] = query_today_tasks()

    history.append({"role": "model", "parts": [{"text": json.dumps(result, ensure_ascii=False)}]})
    return Response(json.dumps(result, ensure_ascii=False), mimetype='application/json')


@app.route('/ping', methods=['GET'])
def ping():
    return 'pong'


if __name__ == '__main__':
    print("Jamie server started: http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=False)
