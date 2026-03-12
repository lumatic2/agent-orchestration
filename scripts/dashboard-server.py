from flask import Flask, request, jsonify, Response
import os
import re
import time
import hashlib
import subprocess
import datetime
import random

app = Flask(__name__)

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DASHBOARD_HTML = os.path.join(BASE_DIR, 'dashboard.html')
SCHEDULE_PATH = os.path.expanduser('~/Desktop/agent-orchestration/SCHEDULE.md')
SOMEDAY_PATH = os.path.expanduser('~/Desktop/agent-orchestration/SOMEDAY.md')
SSH_HOSTS = ['windows', 'macair', 'm1', 'm4']
TASK_RE = re.compile(r'^- \[([ x/])\]\s*\[([^\]]*)\]\s*(.*?)\s*(#[^\s#`]+)?\s*$')
DATE_TAG_RE = re.compile(r'`(\d{2}-\d{2}(?:\([^)]+\))?)`')


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


def calc_dday(line_text):
    """Extract MM-DD date tag from line and return dday integer vs today, or None."""
    m = DATE_TAG_RE.search(line_text)
    if not m:
        return None
    date_str = m.group(1)
    # Strip optional weekday suffix like (화)
    date_clean = re.sub(r'\([^)]*\)', '', date_str).strip()
    try:
        today = datetime.date.today()
        month, day = map(int, date_clean.split('-'))
        target = datetime.date(today.year, month, day)
        return (target - today).days
    except (ValueError, AttributeError):
        return None


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

        dday = None
        if section == '마감 있음 (Deadline)':
            dday = calc_dday(line)

        task = {
            'id': task_id,
            'text': parsed['text'],
            'priority': parsed['priority'],
            'category': parsed['category'],
            'status': parsed['status'],
            'section': section,
            'line_idx': idx,
            'raw_line': line,
            'dday': dday,
        }
        tasks.append(task)

    return lines, tasks


def select_today_and_in_progress(tasks):
    SHOW_SECTIONS = {'오늘 (Today)', '마감 있음 (Deadline)'}
    out = []
    seen = set()
    for t in tasks:
        if t['section'] in SHOW_SECTIONS or t['status'] == 'in_progress':
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
                'dday': t.get('dday'),
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


def get_recommendations(tasks):
    """Return top 3 recommended Anytime tasks based on weekday and priority."""
    today = datetime.date.today()
    weekday = today.weekday()  # 0=Mon ... 6=Sun

    if weekday <= 4:  # weekdays
        priority_categories = {'#회사', '#개발'}
        reason_suffix = '평일 집중 카테고리'
    else:  # weekend
        priority_categories = {'#라이프', '#크리에이티브'}
        reason_suffix = '주말 집중 카테고리'

    anytime = [t for t in tasks if t['section'] == '언제든 (Anytime)']

    PRIO_ORDER = {'높': 0, '중': 1, '낮': 2, '-': 3}

    def sort_key(item):
        cat_match = 0 if item['category'] in priority_categories else 1
        prio_rank = PRIO_ORDER.get(item['priority'], 3)
        return (cat_match, prio_rank)

    sorted_tasks = sorted(enumerate(anytime), key=lambda x: sort_key(x[1]))

    result = []
    for _, t in sorted_tasks[:3]:
        cat_match = t['category'] in priority_categories
        reason = f"{t['category']} · {reason_suffix}" if cat_match else f"우선순위 {t['priority']}"
        result.append({
            'text': t['text'],
            'priority': t['priority'],
            'category': t['category'],
            'reason': reason,
        })
    return result


def get_someday_glimpse():
    """Parse SOMEDAY.md and return 1 random item per section, max 3."""
    if not os.path.exists(SOMEDAY_PATH):
        return []

    with open(SOMEDAY_PATH, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    sections = {}
    current_section = None
    ITEM_RE = re.compile(r'^- \[[ x/]\]\s*(?:\[([^\]]*)\]\s*)?(.*?)\s*(#[^\s#`]+)?\s*$')

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('## '):
            current_section = stripped[3:].strip()
            sections.setdefault(current_section, [])
            continue
        if current_section is None:
            continue
        m = ITEM_RE.match(stripped)
        if m:
            priority = (m.group(1) or '-').strip()
            text = (m.group(2) or '').strip()
            category = (m.group(3) or '').strip()
            if not category:
                # Derive category from section heading (e.g. "## #개발" → "#개발")
                tags = re.findall(r'#[^\s#`]+', current_section)
                category = tags[0] if tags else '#기타'
            if text:
                sections[current_section].append({
                    'text': text,
                    'priority': priority if priority in ['높', '중', '낮'] else '-',
                    'category': category,
                })

    result = []
    section_keys = list(sections.keys())
    random.shuffle(section_keys)
    for sec in section_keys:
        items = sections[sec]
        if not items:
            continue
        result.append(random.choice(items))
        if len(result) >= 3:
            break
    return result


@app.route('/api/recommendations', methods=['GET'])
def api_recommendations():
    _, tasks = parse_schedule()
    items = get_recommendations(tasks)
    return jsonify({'items': items})


@app.route('/api/someday', methods=['GET'])
def api_someday():
    items = get_someday_glimpse()
    return jsonify({'items': items})


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
