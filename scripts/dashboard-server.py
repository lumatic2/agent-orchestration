from flask import Flask, request, jsonify, Response
import os
import re
import time
import hashlib
import subprocess

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DASHBOARD_HTML = os.path.join(BASE_DIR, 'dashboard.html')
SCHEDULE_PATH = os.path.expanduser('~/Desktop/agent-orchestration/SCHEDULE.md')
SSH_HOSTS = ['windows', 'macair', 'm1', 'm4']
TASK_RE = re.compile(r'^- \[([ x/])\]\s*\[([^\]]*)\]\s*(.*?)\s*(#[^\s#`]+)?\s*$')


def read_schedule_lines():
    if not os.path.exists(SCHEDULE_PATH):
        return []
    with open(SCHEDULE_PATH, 'r', encoding='utf-8') as f:
        return f.readlines()


def write_schedule_lines(lines):
    with open(SCHEDULE_PATH, 'w', encoding='utf-8') as f:
        f.writelines(lines)


def parse_task_line(line):
    m = TASK_RE.match(line.strip())
    if not m:
        return None
    status_raw = m.group(1)
    priority = m.group(2).strip() or '-'
    body = (m.group(3) or '').strip()
    category = (m.group(4) or '').strip()

    if category and body.endswith(category):
        body = body[: -len(category)].rstrip()

    if status_raw == 'x':
        status = 'completed'
    elif status_raw == '/':
        status = 'in_progress'
    else:
        status = 'pending'

    if priority not in ['높', '중', '낮', '-']:
        priority = '-'

    if not category:
        tags = re.findall(r'#[^\s#`]+', line)
        category = tags[-1] if tags else '#미분류'

    return {
        'status_char': status_raw,
        'status': status,
        'priority': priority,
        'text': body,
        'category': category,
    }


def parse_schedule():
    lines = read_schedule_lines()
    section = ''
    tasks = []

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith('## '):
            section = stripped[3:].strip()
            continue
        parsed = parse_task_line(line)
        if not parsed:
            continue
        task_id = hashlib.sha1(f'{idx}:{section}:{parsed["text"]}'.encode('utf-8')).hexdigest()[:12]
        task = {
            'id': task_id,
            'text': parsed['text'],
            'priority': parsed['priority'],
            'category': parsed['category'],
            'status': parsed['status'],
            'section': section,
            'line_idx': idx,
            'raw_line': line,
        }
        tasks.append(task)

    return lines, tasks


def select_today_and_in_progress(tasks):
    out = []
    seen = set()
    for t in tasks:
        in_today = t['section'] == '오늘 (Today)'
        in_progress = t['status'] == 'in_progress'
        if in_today or in_progress:
            key = (t['text'], t['category'], t['section'])
            if key in seen:
                continue
            seen.add(key)
            out.append({
                'id': t['id'],
                'text': t['text'],
                'priority': t['priority'],
                'category': t['category'],
                'status': t['status'],
                'section': t['section'],
            })
    return out


def ssh_check(host):
    start = time.monotonic()
    try:
        result = subprocess.run(
            [
                'ssh',
                '-o', 'ConnectTimeout=3',
                '-o', 'BatchMode=yes',
                '-o', 'StrictHostKeyChecking=no',
                host,
                'echo ok',
            ],
            timeout=5,
            capture_output=True,
        )
        latency = int((time.monotonic() - start) * 1000)
        return {'online': result.returncode == 0, 'latency_ms': latency}
    except Exception:
        latency = int((time.monotonic() - start) * 1000)
        return {'online': False, 'latency_ms': latency}


def toggle_task_status(line):
    if '- [x]' in line:
        return line.replace('- [x]', '- [ ]', 1)
    if '- [/]' in line:
        return line.replace('- [/]', '- [x]', 1)
    if '- [ ]' in line:
        return line.replace('- [ ]', '- [x]', 1)
    return line


@app.route('/', methods=['GET'])
def index():
    if not os.path.exists(DASHBOARD_HTML):
        return Response('dashboard.html not found', status=404)
    with open(DASHBOARD_HTML, 'r', encoding='utf-8') as f:
        return Response(f.read(), mimetype='text/html; charset=utf-8')


@app.route('/manifest.json', methods=['GET'])
def manifest():
    return jsonify({
        'name': 'Dashboard',
        'short_name': 'Dash',
        'background_color': '#1a1a2e',
        'theme_color': '#0f3460',
        'display': 'standalone',
        'start_url': '/',
    })


@app.route('/api/devices', methods=['GET'])
def api_devices():
    return jsonify({host: ssh_check(host) for host in SSH_HOSTS})


@app.route('/api/tasks', methods=['GET'])
def api_tasks():
    _, tasks = parse_schedule()
    return jsonify({'tasks': select_today_and_in_progress(tasks)})


@app.route('/api/tasks/complete', methods=['POST'])
def api_tasks_complete():
    payload = request.get_json(silent=True) or {}
    task_text = (payload.get('task_text') or '').strip()
    if not task_text:
        return jsonify({'ok': False, 'error': 'task_text is required'}), 400

    lines, tasks = parse_schedule()
    target = next((t for t in tasks if t['text'] == task_text), None)
    if not target:
        return jsonify({'ok': False, 'error': 'task not found'}), 404

    idx = target['line_idx']
    lines[idx] = toggle_task_status(lines[idx])
    write_schedule_lines(lines)
    return jsonify({'ok': True})


@app.route('/api/tasks/add', methods=['POST'])
def api_tasks_add():
    payload = request.get_json(silent=True) or {}
    text = (payload.get('text') or '').strip()
    priority = (payload.get('priority') or '-').strip()
    category = (payload.get('category') or '미분류').strip()

    if not text:
        return jsonify({'ok': False, 'error': 'text is required'}), 400
    if priority not in ['높', '중', '낮', '-']:
        priority = '-'
    if not category.startswith('#'):
        category = f'#{category}'

    lines = read_schedule_lines()
    insert_at = None
    in_today = False

    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped == '## 오늘 (Today)':
            in_today = True
            continue
        if in_today and stripped.startswith('## '):
            insert_at = i
            break

    if insert_at is None:
        if in_today:
            insert_at = len(lines)
        else:
            lines.extend(['\n', '## 오늘 (Today)\n'])
            insert_at = len(lines)

    new_line = f'- [ ] [{priority}] {text} {category}\n'
    lines.insert(insert_at, new_line)
    write_schedule_lines(lines)

    return jsonify({'ok': True})


@app.route('/api/tasks/remove', methods=['POST'])
def api_tasks_remove():
    payload = request.get_json(silent=True) or {}
    task_text = (payload.get('task_text') or '').strip()
    if not task_text:
        return jsonify({'ok': False, 'error': 'task_text is required'}), 400

    lines, tasks = parse_schedule()
    target = next((t for t in tasks if t['text'] == task_text), None)
    if not target:
        return jsonify({'ok': False, 'error': 'task not found'}), 404

    del lines[target['line_idx']]
    write_schedule_lines(lines)
    return jsonify({'ok': True})


@app.route('/api/projects', methods=['GET'])
def api_projects():
    _, tasks = parse_schedule()
    grouped = {}

    for t in tasks:
        category = t['category'] or '#미분류'
        if category not in grouped:
            grouped[category] = {'total': 0, 'completed': 0, 'in_progress': 0, 'percent': 0}
        grouped[category]['total'] += 1
        if t['status'] == 'completed':
            grouped[category]['completed'] += 1
        if t['status'] == 'in_progress':
            grouped[category]['in_progress'] += 1

    for category, data in grouped.items():
        total = data['total']
        data['percent'] = round((data['completed'] / total) * 100, 1) if total else 0

    return jsonify(grouped)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8765, debug=False)
