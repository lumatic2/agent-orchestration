from flask import Flask, request, jsonify
from google import genai
from google.genai import types
import os, json

app = Flask(__name__)

GEMINI_API_KEY = os.environ.get('GEMINI_API_KEY', '')
client = None
history = []  # 대화 히스토리 (메모리)

SYSTEM_PROMPT = """너는 '제이미'야. 갤럭시 S24 Ultra 개인 AI 비서. 반말로 친근하게 대화해.

반드시 아래 JSON만 출력해. 다른 텍스트 절대 포함 금지.
{"type":"TALK"|"PHONE"|"REMOTE", "response":"TTS 응답(간결)", "action":null}

type 기준:
- TALK: 대화, 질문, 정보 요청
- PHONE: 폰 직접 제어 (알람/전화/문자/앱/볼륨/밝기/와이파이/블루투스)
- REMOTE: 다른 기기 작업 (target: windows|macair|m1|m4)

PHONE action 예시:
alarm:  {"command":"alarm",  "time":"HH:MM", "op":"set"}
call:   {"command":"call",   "contact":"이름"}
volume: {"command":"volume", "type":"media", "level":5}
app:    {"command":"app",    "name":"앱이름"}
wifi:   {"command":"wifi",   "op":"on|off"}

REMOTE: {"target":"windows|macair|m1|m4", "payload":"실행할 명령 자연어"}"""

@app.route('/jamie', methods=['POST'])
def jamie():
    global history, client

    data = request.json
    user_text = data.get('text', '').strip()
    if not user_text:
        from flask import Response
        import json as json_mod
        return Response(json_mod.dumps({"type": "TALK", "response": "뭐라고?", "action": None}, ensure_ascii=False), mimetype='application/json')

    # Gemini 클라이언트 초기화
    if client is None:
        api_key = GEMINI_API_KEY or data.get('api_key', '')
        client = genai.Client(api_key=api_key)

    # 히스토리 구성
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

    history.append({"role": "model", "parts": [{"text": response.text}]})
    from flask import Response
    import json as json_mod
    return Response(json_mod.dumps(result, ensure_ascii=False), mimetype='application/json')

@app.route('/ping', methods=['GET'])
def ping():
    return 'pong'

if __name__ == '__main__':
    print("Jamie server started: http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=False)
