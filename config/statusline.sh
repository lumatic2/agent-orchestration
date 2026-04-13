#!/usr/bin/env bash
# Claude Code Status Line
# Shows: current directory (cyan) | model (yellow) | 5h usage (green) | 7d usage (magenta)

input=$(cat)

# --- Extract fields using python3 (no jq dependency) ---
model=$(echo "$input" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('model',{}).get('display_name','Unknown'))" 2>/dev/null || echo "Unknown")
cwd=$(echo "$input" | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('workspace',{}).get('current_dir') or d.get('cwd',''))" 2>/dev/null || echo "")
ctx_pct=$(echo "$input" | python -c "import sys,json; d=json.load(sys.stdin); v=d.get('context_window',{}).get('used_percentage'); print(v) if v is not None else print('')" 2>/dev/null || echo "")
five_hour_pct=$(echo "$input" | python -c "import sys,json; d=json.load(sys.stdin); v=d.get('rate_limits',{}).get('five_hour',{}).get('used_percentage'); print(v) if v is not None else print('')" 2>/dev/null || echo "")
seven_day_pct=$(echo "$input" | python -c "import sys,json; d=json.load(sys.stdin); v=d.get('rate_limits',{}).get('seven_day',{}).get('used_percentage'); print(v) if v is not None else print('')" 2>/dev/null || echo "")

# --- ANSI colors ($'...' = escape chars baked in at assignment time) ---
RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[96m'
YELLOW=$'\033[93m'
WHITE=$'\033[97m'
RED=$'\033[31m'

USAGE_OK=$'\033[92m'             # bright green  (< 30%)
USAGE_WARN=$'\033[93m'           # bright yellow (30–59%)
USAGE_HIGH=$'\033[38;2;255;140;0m'  # orange RGB (60–89%)
USAGE_CRIT=$'\033[91m'           # bright red    (90%+)

usage_icon() {
  local pct=$1
  if   [ "$pct" -ge 90 ]; then printf '🔴'
  elif [ "$pct" -ge 60 ]; then printf '🟠'
  elif [ "$pct" -ge 30 ]; then printf '🟡'
  else                         printf '🟢'
  fi
}

usage_color() {
  local pct=$1 warn=$2 high=$3 crit=$4
  if   [ "$pct" -ge "$crit" ]; then printf '%s' "$USAGE_CRIT"
  elif [ "$pct" -ge "$high" ]; then printf '%s' "$USAGE_HIGH"
  elif [ "$pct" -ge "$warn" ]; then printf '%s' "$USAGE_WARN"
  else                              printf '%s' "$USAGE_OK"
  fi
}

ctx_color() {
  local pct=$1
  case "$model" in
    *[Oo]pus*) usage_color "$pct" 10 15 20 ;;
    *)         usage_color "$pct" 30 40 50 ;;
  esac
}

# --- Dir display: project name + worktree ---
proj_name=""
wt_name=""
if [ -n "$cwd" ]; then
  # Normalize Windows backslashes to forward slashes
  cwd="${cwd//\\//}"
  # Detect worktree: path contains /.claude/worktrees/<name>
  if [[ "$cwd" =~ /.claude/worktrees/([^/]+) ]]; then
    wt_name="${BASH_REMATCH[1]}"
    # Project root is everything before /.claude/worktrees
    proj_root="${cwd%%/.claude/worktrees/*}"
    proj_name=$(basename "$proj_root")
  else
    proj_name=$(basename "$cwd")
    wt_name="main"
  fi
fi

# --- Build segments ---
segments=()

# 1. Project + worktree — cyan
if [ -n "$proj_name" ]; then
  segments+=("${CYAN}${proj_name}${RESET}${DIM}:${RESET}${CYAN}${wt_name}${RESET}")
fi

# 2. Model name — yellow
segments+=("${YELLOW}${model}${RESET}")

# 3. Context bar — model-aware thresholds
if [ -n "$ctx_pct" ] && [ "$ctx_pct" != "None" ]; then
  ctx_int=$(echo "${ctx_pct%.*}" | tr -d '\r\n ')
  ctx_int=${ctx_int:-0}
  color=$(ctx_color "$ctx_int")
  segments+=("${color}ctx:${ctx_int}%${RESET}")
fi

# 4. 5-hour usage — emoji indicator
if [ -n "$five_hour_pct" ] && [ "$five_hour_pct" != "None" ]; then
  five_int=$(echo "${five_hour_pct%.*}" | tr -d '\r\n ')
  five_int=${five_int:-0}
  icon=$(usage_icon "$five_int")
  color=$(usage_color "$five_int" 30 60 90)
  segments+=("${icon} ${color}5h:${five_int}%${RESET}")
fi

# 4. Weekly usage — emoji indicator
if [ -n "$seven_day_pct" ] && [ "$seven_day_pct" != "None" ]; then
  seven_int=$(echo "${seven_day_pct%.*}" | tr -d '\r\n ')
  seven_int=${seven_int:-0}
  icon=$(usage_icon "$seven_int")
  color=$(usage_color "$seven_int" 30 60 90)
  segments+=("${icon} ${color}7d:${seven_int}%${RESET}")
fi

# --- Join with separator ---
sep="${DIM} | ${RESET}"
result=""
for seg in "${segments[@]}"; do
  if [ -z "$result" ]; then
    result="$seg"
  else
    result="${result}${sep}${seg}"
  fi
done

printf '%s\n' "$result"
