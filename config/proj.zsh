# proj: 프로젝트 폴더 인터랙티브 선택 + worktree 지원
# Requires: fzf, jq, git
# Source this file from ~/.zshrc:
#   source ~/projects/agent-orchestration/config/proj.zsh

proj() {
  local root="${PROJECTS_ROOT:-$HOME/projects}"
  local meta_file="$root/.proj-meta.json"

  # ── helpers ─────────────────────────────────────────────
  local meta
  meta=$( [[ -f $meta_file ]] && cat "$meta_file" || echo '{}' )

  _pm_save() { printf '%s\n' "$1" > "$meta_file"; }

  _pm_ago() {
    local diff=$(( $(date +%s) - ${1:-0} ))
    (( diff < 86400   )) && { printf '오늘';             return; }
    (( diff < 172800  )) && { printf '어제';             return; }
    local d=$(( diff / 86400 ))
    (( d < 7   )) && { printf '%d일 전'    $d;           return; }
    (( d < 35  )) && { printf '%d주 전'   $(( d / 7 ));  return; }
    (( d < 365 )) && { printf '%d개월 전' $(( d / 30 )); return; }
    printf '%d년 전' $(( d / 365 ))
  }

  _pm_sortkey() {
    local pdir=$1
    local marker="$pdir/.claude/.last-opened"
    if [[ -f $marker ]]; then
      stat -f '%m' "$marker" 2>/dev/null || echo 0
    else
      local gl; gl=$(git -C "$pdir" log -1 --format='%ct' 2>/dev/null)
      [[ $gl =~ ^[0-9]+$ ]] && echo "$gl" \
        || { stat -f '%m' "$pdir" 2>/dev/null || echo 0; }
    fi
  }

  _pm_touch() {
    mkdir -p "$1/.claude"
    date -u +'%Y-%m-%dT%H:%M:%SZ' > "$1/.claude/.last-opened"
  }

  _pm_ensure_wt_ignore() {
    local gi="$1/.gitignore"
    grep -qs '.claude/worktrees/' "$gi" && return
    printf '\n# Claude Code worktrees\n.claude/worktrees/\n' >> "$gi"
  }

  # ── worktree 메타 헬퍼 (jq 기반) ──────────────────────
  _pm_save_wt_desc() {
    local proj=$1 name=$2 desc=$3
    meta=$(jq --arg p "$proj" --arg n "$name" --arg d "$desc" \
              'if .[$p] == null then .[$p] = {} else . end
               | if .[$p].wt == null then .[$p].wt = {} else . end
               | .[$p].wt[$n] = {desc:$d}' <<<"$meta")
    _pm_save "$meta"
  }

  _pm_remove_wt_meta() {
    local proj=$1 name=$2
    meta=$(jq --arg p "$proj" --arg n "$name" 'del(.[$p].wt[$n])' <<<"$meta")
    _pm_save "$meta"
  }

  _pm_rename_wt_meta() {
    local proj=$1 old=$2 new=$3
    local old_val
    old_val=$(jq --arg p "$proj" --arg n "$old" '.[$p].wt[$n] // {}' <<<"$meta")
    meta=$(jq --arg p "$proj" --arg o "$old" --arg nn "$new" \
              --argjson v "$old_val" \
              'del(.[$p].wt[$o]) | .[$p].wt[$nn] = $v' <<<"$meta")
    _pm_save "$meta"
  }

  # ── 에이전트 런칭 메뉴 ─────────────────────────────────
  _pm_launch_agent() {
    local target_dir=$1
    local agent_menu="claude    Claude Code"$'\n'
    command -v codex  &>/dev/null && agent_menu+="codex     Codex CLI"$'\n'
    command -v gemini &>/dev/null && agent_menu+="gemini    Gemini CLI"$'\n'
    agent_menu+="shell     셸만 이동"$'\n'
    local pick
    pick=$(printf '%s' "$agent_menu" | fzf --layout=reverse --prompt='agent> ' --height=40% --border --no-sort \
               --header="$target_dir") || return 0
    local cmd; cmd=$(awk '{print $1}' <<<"$pick")
    case $cmd in
      claude) claude ;;
      codex)  codex   ;;
      gemini) gemini  ;;
      *)      ;;  # shell — cd만 하고 끝
    esac
  }

  # ── 색상 헬퍼 ──────────────────────────────────────────
  _pm_green()  { printf '\033[32m%s\033[0m\n' "$*"; }
  _pm_red()    { printf '\033[31m%s\033[0m\n' "$*"; }
  _pm_yellow() { printf '\033[33m%s\033[0m' "$*"; }
  _pm_gray()   { printf '\033[90m%s\033[0m\n' "$*"; }
  _pm_mag()    { printf '\033[35m%s\033[0m\n' "$*"; }

  # ── Step 1: 프로젝트 목록 구성 ─────────────────────────
  local rows=() name pdir sk ago pcat pdesc sorted fzf_input line
  for d in "$root"/*/; do
    [[ -d $d ]] || continue
    name="${${d%/}##*/}"
    pdir="$root/$name"
    sk=$(_pm_sortkey "$pdir")
    ago=$(_pm_ago "$sk")
    pcat=$(jq -r --arg n "$name" '.[$n].cat // ""' <<<"$meta")
    pdesc=$(jq -r --arg n "$name" '.[$n].desc // ""' <<<"$meta")
    rows+=("${sk}"$'\t'"${name}"$'\t'"${ago}"$'\t'"${pcat}"$'\t'"${pdesc}")
  done

  sorted=$(printf '%s\n' "${rows[@]}" | sort -t$'\t' -k1 -rn)

  # fzf 입력 빌드
  fzf_input=""
  while IFS=$'\t' read -r sk name ago pcat pdesc _; do
    [[ -z $name ]] && continue
    printf -v line '%-28s %-8s %-6s %s' "$name" "$ago" "$pcat" "$pdesc"
    fzf_input+="$line"$'\n'
  done <<<"$sorted"

  local fzf_header
  fzf_header=$'  ctrl-n: 새 프로젝트  ctrl-e: 설명수정  ctrl-r: 이름변경  ctrl-d: 삭제\n──────────────────────────────────────────────────────────────'

  local fzf_out key sel
  fzf_out=$(printf '%s' "$fzf_input" | fzf --layout=reverse --prompt='proj> ' --height=40% --border --no-sort \
            --header="$fzf_header" \
            --expect='ctrl-n,ctrl-e,ctrl-r,ctrl-d') || return 0
  key=$(head -1 <<<"$fzf_out")
  sel=$(sed -n '2p' <<<"$fzf_out")

  # ── 프로젝트 관리 액션 ─────────────────────────────────
  if [[ $key == 'ctrl-n' ]]; then
    _pm_yellow '  프로젝트 이름: '; read -r pname
    [[ -z $pname ]] && { echo '  취소됨.'; return; }
    local ppath="$root/$pname"
    [[ -d $ppath ]] && { _pm_red "  이미 존재: $ppath"; return; }

    _pm_yellow '  설명 (한글 OK): '; read -r pdesc
    _pm_yellow '  카테고리 (AI/Web/MCP/Bot/Game/Tool/Infra/Etc): '; read -r pcat
    [[ -z $pcat ]] && pcat='Etc'

    mkdir -p "$ppath"
    git -C "$ppath" init -b main &>/dev/null

    cat > "$ppath/CLAUDE.md" <<EOF
# $pname

> $pdesc

## Tech Stack
<!-- 사용 기술 스택 -->

## Structure
<!-- 주요 디렉토리/파일 구조 -->

## Conventions
<!-- 코딩 컨벤션, 네이밍 규칙 등 -->
EOF

    cat > "$ppath/.gitignore" <<EOF
# Claude Code
.claude/worktrees/
.claude/.last-opened
EOF

    meta=$(jq --arg n "$pname" --arg c "$pcat" --arg d "$pdesc" \
              '.[$n] = {cat:$c, desc:$d}' <<<"$meta")
    _pm_save "$meta"
    _pm_touch "$ppath"
    cd "$ppath" && _pm_green "  -> $ppath"
    return
  fi

  if [[ $key == 'ctrl-e' ]]; then
    local edit_input=""
    while IFS=$'\t' read -r sk name ago pcat pdesc _; do
      [[ -z $name ]] && continue
      printf -v line '%-28s [%-6s] %s' "$name" "$pcat" "$pdesc"
      edit_input+="$line"$'\n'
    done <<<"$sorted"
    local esel
    esel=$(printf '%s' "$edit_input" | fzf --layout=reverse --prompt='edit> ' --height=40% --border --no-sort \
               --header='설명/카테고리 수정할 프로젝트 선택') || return 0
    local ename; ename=$(awk '{print $1}' <<<"$esel")
    local cur_cat; cur_cat=$(jq -r --arg n "$ename" '.[$n].cat // ""' <<<"$meta")
    local cur_desc; cur_desc=$(jq -r --arg n "$ename" '.[$n].desc // ""' <<<"$meta")
    _pm_gray "  현재: [$cur_cat] $cur_desc"
    _pm_yellow "  설명 (Enter=유지): "; read -r new_desc
    [[ -z $new_desc ]] && new_desc="$cur_desc"
    _pm_yellow "  카테고리 (Enter=유지, 현재=$cur_cat): "; read -r new_cat
    [[ -z $new_cat ]] && new_cat="$cur_cat"
    meta=$(jq --arg n "$ename" --arg c "$new_cat" --arg d "$new_desc" \
              '.[$n] = {cat:$c, desc:$d}' <<<"$meta")
    _pm_save "$meta"
    _pm_green "  저장 완료: [$new_cat] $new_desc"
    return
  fi

  if [[ $key == 'ctrl-r' ]]; then
    local ren_input=""
    while IFS=$'\t' read -r sk name _ _ _ _; do
      [[ -z $name ]] && continue
      ren_input+="$name"$'\n'
    done <<<"$sorted"
    local rsel
    rsel=$(printf '%s' "$ren_input" | fzf --layout=reverse --prompt='rename> ' --height=40% --border --no-sort \
               --header='이름변경할 프로젝트 선택') || return 0
    local rname="${rsel%% *}"
    _pm_yellow "  새 이름 ($rname): "; read -r new_name
    [[ -z $new_name ]] && { echo '  취소됨.'; return; }
    local new_path="$root/$new_name"
    [[ -d $new_path ]] && { _pm_red "  이미 존재: $new_path"; return; }
    [[ $PWD == "$root/$rname"* ]] && cd "$root"
    if mv "$root/$rname" "$new_path"; then
      local old_val; old_val=$(jq --arg n "$rname" '.[$n] // {}' <<<"$meta")
      meta=$(jq --arg o "$rname" --arg nn "$new_name" --argjson v "$old_val" \
                'del(.[$o]) | .[$nn] = $v' <<<"$meta")
      _pm_save "$meta"
      _pm_green "  변경 완료: $rname -> $new_name"
    else
      _pm_red '  이름변경 실패'
    fi
    return
  fi

  if [[ $key == 'ctrl-d' ]]; then
    local del_input=""
    while IFS=$'\t' read -r sk name _ _ _ _; do
      [[ -z $name ]] && continue
      del_input+="$name"$'\n'
    done <<<"$sorted"
    local dsel
    dsel=$(printf '%s' "$del_input" | fzf --layout=reverse --prompt='delete> ' --height=40% --border --no-sort \
               --header='삭제할 프로젝트 선택') || return 0
    local dname="${dsel%% *}"
    _pm_red "  '$dname' 을 정말 삭제? 복구 불가 (y/N): "; read -r confirm
    if [[ $confirm == [yY] ]]; then
      [[ $PWD == "$root/$dname"* ]] && cd "$root"
      rm -rf "$root/$dname"
      meta=$(jq --arg n "$dname" 'del(.[$n])' <<<"$meta")
      _pm_save "$meta"
      _pm_green "  삭제 완료: $dname"
    else
      echo '  취소됨.'
    fi
    return
  fi

  # ── 프로젝트 선택됨 ────────────────────────────────────
  [[ -z $sel ]] && return 0
  local proj_name; proj_name=$(awk '{print $1}' <<<"$sel")
  local proj_path="$root/$proj_name"
  [[ -d $proj_path ]] || { _pm_red "경로 없음: $proj_path"; return 1; }

  if ! git -C "$proj_path" rev-parse --git-dir &>/dev/null; then
    _pm_touch "$proj_path"
    cd "$proj_path" && _pm_green "-> $proj_path"
    _pm_launch_agent "$proj_path"
    return
  fi

  # ── Step 2: root vs worktree 선택 ──────────────────────
  local branch; branch=$(git -C "$proj_path" branch --show-current 2>/dev/null || echo 'HEAD')
  local wt_meta; wt_meta=$(jq -r --arg n "$proj_name" '.[$n].wt // {}' <<<"$meta")

  # worktree 목록 파싱
  local -a wt_paths wt_names
  local cur_wt="" real_wt real_proj
  while IFS= read -r line; do
    if [[ $line =~ ^worktree\ (.+)$ ]]; then
      cur_wt="${match[1]}"
    elif [[ $line =~ ^branch\ refs/heads/ && -n $cur_wt ]]; then
      real_wt=$(realpath "$cur_wt" 2>/dev/null || echo "$cur_wt")
      real_proj=$(realpath "$proj_path" 2>/dev/null || echo "$proj_path")
      if [[ $real_wt != $real_proj ]]; then
        wt_paths+=("$cur_wt")
        wt_names+=("${cur_wt##*/}")
      fi
      cur_wt=""
    fi
  done < <(git -C "$proj_path" worktree list --porcelain 2>/dev/null)

  local wt_fzf wn wp wsk wago wdesc wline
  wt_fzf="[main]  프로젝트 루트  ($branch)"$'\n'
  for ((i=1; i<=${#wt_paths[@]}; i++)); do
    wn="${wt_names[$i]}"
    wp="${wt_paths[$i]}"
    wsk=$(_pm_sortkey "$wp")
    wago=$(_pm_ago "$wsk")
    wdesc=$(jq -r --arg n "$wn" '.[$n].desc // ""' <<<"$wt_meta")
    printf -v wline '[wt]    %-20s %-8s %s' "$wn" "$wago" "$wdesc"
    wt_fzf+="$wline"$'\n'
  done

  local wt_header
  wt_header="  ctrl-n: 새 worktree"
  if (( ${#wt_paths[@]} > 0 )); then
    wt_header+="  ctrl-e: 설명수정  ctrl-r: 이름변경  ctrl-d: 삭제"
  fi
  wt_header+=$'\n──────────────────────────────────────────────────────────────'

  local wt_expect='ctrl-n'
  (( ${#wt_paths[@]} > 0 )) && wt_expect='ctrl-n,ctrl-e,ctrl-r,ctrl-d'

  local wfzf_out wkey wsel
  wfzf_out=$(printf '%s' "$wt_fzf" | fzf --layout=reverse --prompt="${proj_name}> " --height=40% --border --no-sort \
             --header="$wt_header" \
             --expect="$wt_expect") || return 0
  wkey=$(head -1 <<<"$wfzf_out")
  wsel=$(sed -n '2p' <<<"$wfzf_out")

  if [[ -z $wkey && $wsel == '[main]'* ]]; then
    _pm_touch "$proj_path"
    cd "$proj_path" && _pm_green "-> $proj_path"
    _pm_launch_agent "$proj_path"
    return
  fi

  if [[ -z $wkey && $wsel == '[wt]'* ]]; then
    local wt_sel_name; wt_sel_name=$(awk '{print $2}' <<<"$wsel")
    local wt_target=""
    for ((i=1; i<=${#wt_names[@]}; i++)); do
      [[ ${wt_names[$i]} == "$wt_sel_name" ]] && { wt_target="${wt_paths[$i]}"; break; }
    done
    if [[ -d $wt_target ]]; then
      _pm_touch "$proj_path"
      cd "$wt_target" && _pm_mag "-> $wt_target"
      _pm_launch_agent "$wt_target"
    else
      _pm_red "경로 없음: $wt_sel_name"
    fi
    return
  fi

  if [[ $wkey == 'ctrl-n' ]]; then
    _pm_yellow '  Worktree 이름 (예: auth-refactor): '; read -r wt_name
    [[ -z $wt_name ]] && { echo '취소됨.'; return; }
    _pm_yellow '  설명 (Enter=생략): '; read -r wt_desc

    _pm_ensure_wt_ignore "$proj_path"
    local wt_dir="$proj_path/.claude/worktrees/$wt_name"
    mkdir -p "$(dirname "$wt_dir")"

    if git -C "$proj_path" worktree add "$wt_dir" -b "$wt_name"; then
      local inc="$proj_path/.worktreeinclude"
      if [[ -f $inc ]]; then
        while IFS= read -r f; do
          f="${f## }"; f="${f%% }"
          [[ -z $f || $f == '#'* ]] && continue
          local src="$proj_path/$f"
          [[ -f $src ]] && cp -p "$src" "$wt_dir/$f"
        done < "$inc"
      fi
      if [[ -n $wt_desc ]]; then
        _pm_save_wt_desc "$proj_name" "$wt_name" "$wt_desc"
      fi
      _pm_touch "$proj_path"
      cd "$wt_dir"
      _pm_mag "-> Worktree '$wt_name' ($wt_dir)"
      _pm_gray "   claude 를 실행하면 이 브랜치에서 작업합니다"
      _pm_launch_agent "$wt_dir"
    else
      _pm_red 'Worktree 생성 실패'
    fi
    return
  fi

  if [[ $wkey == 'ctrl-e' ]]; then
    local wedit_input="" wd
    for ((i=1; i<=${#wt_names[@]}; i++)); do
      wn="${wt_names[$i]}"
      wd=$(jq -r --arg n "$wn" '.[$n].desc // ""' <<<"$wt_meta")
      printf -v wline '%-24s %s' "$wn" "$wd"
      wedit_input+="$wline"$'\n'
    done
    local wesel
    wesel=$(printf '%s' "$wedit_input" | fzf --layout=reverse --prompt='edit wt> ' --height=40% --border --no-sort \
                --header='설명 수정할 worktree 선택') || return 0
    local wen; wen=$(awk '{print $1}' <<<"$wesel")
    local wcur; wcur=$(jq -r --arg n "$wen" '.[$n].desc // ""' <<<"$wt_meta")
    [[ -n $wcur ]] && _pm_gray "  현재: $wcur"
    _pm_yellow '  새 설명 (Enter=유지): '; read -r wnew
    [[ -z $wnew ]] && wnew="$wcur"
    if [[ -n $wnew ]]; then
      _pm_save_wt_desc "$proj_name" "$wen" "$wnew"
      _pm_green "  저장 완료: $wen -> $wnew"
    fi
    return
  fi

  if [[ $wkey == 'ctrl-r' ]]; then
    local wren_input=""
    for ((i=1; i<=${#wt_names[@]}; i++)); do
      wren_input+="${wt_names[$i]}"$'\n'
    done
    local wrsel
    wrsel=$(printf '%s' "$wren_input" | fzf --layout=reverse --prompt='rename wt> ' --height=40% --border --no-sort \
                --header='이름변경할 worktree 선택') || return 0
    local wrname="${wrsel%% *}"
    _pm_yellow '  새 이름: '; read -r wrnew
    [[ -z $wrnew ]] && { echo '  취소됨.'; return; }
    local wold_dir="$proj_path/.claude/worktrees/$wrname"
    local wnew_dir="$proj_path/.claude/worktrees/$wrnew"
    [[ $PWD == "$wold_dir"* ]] && cd "$proj_path"
    if git -C "$proj_path" worktree move "$wold_dir" "$wnew_dir"; then
      git -C "$proj_path" branch -m "$wrname" "$wrnew" 2>/dev/null
      _pm_rename_wt_meta "$proj_name" "$wrname" "$wrnew"
      _pm_green "  변경 완료: $wrname -> $wrnew"
    else
      _pm_red '  이름변경 실패 (다른 터미널이 해당 폴더에 있을 수 있음)'
    fi
    return
  fi

  if [[ $wkey == 'ctrl-d' ]]; then
    local wdel_input=""
    for ((i=1; i<=${#wt_names[@]}; i++)); do wdel_input+="${wt_names[$i]}"$'\n'; done
    local wdsel
    wdsel=$(printf '%s' "$wdel_input" | fzf --layout=reverse --prompt='delete wt> ' --height=40% --border --no-sort \
                --header='삭제할 worktree 선택') || return 0
    local wdname="${wdsel%% *}"
    _pm_yellow "  '$wdname' 삭제? 브랜치는 유지됩니다. (y/N): "; read -r wdconfirm
    if [[ $wdconfirm == [yY] ]]; then
      local wdpath="$proj_path/.claude/worktrees/$wdname"
      [[ $PWD == "$wdpath"* ]] && cd "$proj_path"
      if git -C "$proj_path" worktree remove "$wdpath"; then
        _pm_remove_wt_meta "$proj_name" "$wdname"
        _pm_green "  삭제 완료: $wdname"
      else
        _pm_red '  삭제 실패 (--force 필요할 수 있음)'
      fi
    else
      echo '  취소됨.'
    fi
    return
  fi
}
