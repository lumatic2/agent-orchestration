# PowerShell Profile - yusun

# ─── Python 3.12 PATH ────────────────────────────────────────────────────────
$py312 = "$env:LOCALAPPDATA\Programs\Python\Python312"
if (Test-Path $py312) {
    $env:PATH = "$py312;$py312\Scripts;$env:PATH"
}

# ─── proj: 프로젝트 폴더 인터랙티브 선택 + worktree 지원 ──────────────────
function proj {
    $projectsRoot = "$HOME\projects"
    $metaFile = Join-Path $projectsRoot ".proj-meta.json"

    # ── 메타데이터 로드/저장 ──────────────────────────────────
    function Load-Meta {
        if (Test-Path $metaFile) {
            return (Get-Content $metaFile -Raw -Encoding UTF8 | ConvertFrom-Json)
        }
        return [PSCustomObject]@{}
    }

    function Save-Meta($obj) {
        $obj | ConvertTo-Json -Depth 3 | Set-Content $metaFile -Encoding UTF8
    }

    function Get-Meta([string]$name, $meta) {
        if ($meta.PSObject.Properties[$name]) {
            return $meta.$name
        }
        return $null
    }

    # ── 공통 헬퍼 ─────────────────────────────────────────────
    function Format-Ago([long]$ts) {
        $diff = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $ts
        if ($diff -lt  86400) { return "오늘" }
        if ($diff -lt 172800) { return "어제" }
        $d = [math]::Floor($diff / 86400)
        if ($d -lt  7) { return "${d}일 전" }
        $w = [math]::Floor($d / 7)
        if ($w -lt  5) { return "${w}주 전" }
        $m = [math]::Floor($d / 30)
        if ($m -lt 12) { return "${m}개월 전" }
        return "$([math]::Floor($d / 365))년 전"
    }

    function Pick-Menu {
        param(
            [string[]]$Items,
            [string]$Header
        )
        $sel = 0
        $cnt = $Items.Count

        function Redraw($s, $first) {
            if (-not $first) {
                [Console]::SetCursorPosition(0, [Console]::CursorTop - $cnt)
            }
            for ($i = 0; $i -lt $cnt; $i++) {
                if ($i -eq $s) {
                    Write-Host "> $($Items[$i])" -ForegroundColor Cyan
                } else {
                    Write-Host "  $($Items[$i])" -ForegroundColor DarkGray
                }
            }
        }

        [Console]::CursorVisible = $false
        if ($Header) { Write-Host "  $Header" -ForegroundColor DarkYellow }
        Write-Host ""
        Redraw $sel $true

        while ($true) {
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow"   { if ($sel -gt 0) { $sel-- }; Redraw $sel $false }
                "DownArrow" { if ($sel -lt $cnt - 1) { $sel++ }; Redraw $sel $false }
                "Enter"     { [Console]::CursorVisible = $true; Write-Host ""; return $sel }
                "Escape"    { [Console]::CursorVisible = $true; Write-Host ""; return -1 }
            }
        }
    }

    function Ensure-WorktreeIgnore([string]$projPath) {
        $gi = Join-Path $projPath ".gitignore"
        $pattern = ".claude/worktrees/"
        if (Test-Path $gi) {
            $content = Get-Content $gi -Raw -ErrorAction SilentlyContinue
            if ($content -and $content.Contains($pattern)) { return }
        }
        Add-Content -Path $gi -Value "`n# Claude Code worktrees`n$pattern"
    }

    function Touch-ProjectMarker([string]$path) {
        $marker = Join-Path $path ".claude\.last-opened"
        $dir = Split-Path $marker -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::WriteAllText($marker, (Get-Date -Format "o"))
    }

    # ── Step 1: 프로젝트 목록 + 관리 메뉴 ─────��──────────────
    $meta = Load-Meta

    $projects = Get-ChildItem -Path $projectsRoot -Directory | ForEach-Object {
        $name = $_.Name
        $path = $_.FullName
        $marker = Join-Path $path ".claude\.last-opened"
        if (Test-Path $marker) {
            $sortKey = [long]((Get-Item $marker).LastWriteTime.ToUniversalTime() - [datetime]"1970-01-01").TotalSeconds
        } else {
            $gitLog = git -C $path log -1 --format="%ct" 2>$null
            $sortKey = if ($gitLog -and $gitLog -match '^\d+$') { [long]$gitLog }
                       else { [long]($_.LastWriteTime.ToUniversalTime() - [datetime]"1970-01-01").TotalSeconds }
        }
        $m = Get-Meta $name $meta
        [PSCustomObject]@{
            Name    = $name
            Path    = $path
            SortKey = $sortKey
            Cat     = if ($m) { $m.cat } else { "" }
            Desc    = if ($m) { $m.desc } else { "" }
        }
    } | Sort-Object SortKey -Descending

    # 프로젝트 행 + 하단 관리 메뉴
    $lines = [System.Collections.Generic.List[string]]::new()
    $lineActions = [System.Collections.Generic.List[string]]::new()

    foreach ($p in $projects) {
        $ago = Format-Ago $p.SortKey
        $catStr = if ($p.Cat) { $p.Cat.PadRight(6) } else { "      " }
        $descStr = if ($p.Desc) { $p.Desc } else { "" }
        $lines.Add("$($p.Name.PadRight(28))$($ago.PadRight(8))$catStr$descStr")
        $lineActions.Add("open:$($p.Path)")
    }

    # 구분선 + 관리 메뉴
    $lines.Add("---")
    $lineActions.Add("noop")
    $lines.Add("[+new]   새 프로젝트 만들기")
    $lineActions.Add("proj-new")
    $lines.Add("[edit]   프로젝트 설명/카테고리 수정")
    $lineActions.Add("proj-edit")
    $lines.Add("[ren]    프로젝트 이름변경")
    $lineActions.Add("proj-ren")
    $lines.Add("[del]    프로젝트 삭제")
    $lineActions.Add("proj-del")

    $idx = Pick-Menu -Items $lines.ToArray() -Header "Select a project"
    if ($idx -lt 0) { return }

    $action1 = $lineActions[$idx]

    # ── 프로젝트 관리 액션 ────────────────────────────────────
    if ($action1 -eq "noop") { return }

    if ($action1 -eq "proj-new") {
        Write-Host -NoNewline "  프로젝트 이름: " -ForegroundColor Yellow
        $newProjName = Read-Host
        if (-not $newProjName) { Write-Host "  취소됨."; return }

        $newProjPath = Join-Path $projectsRoot $newProjName
        if (Test-Path $newProjPath) {
            Write-Host "  이미 존재: $newProjPath" -ForegroundColor Red
            return
        }

        Write-Host -NoNewline "  설명 (한글 OK): " -ForegroundColor Yellow
        $newDesc = Read-Host
        Write-Host -NoNewline "  카테고리 (AI/Web/MCP/Bot/Game/Tool/Infra/Etc): " -ForegroundColor Yellow
        $newCat = Read-Host
        if (-not $newCat) { $newCat = "Etc" }

        New-Item -ItemType Directory -Path $newProjPath -Force | Out-Null
        git -C $newProjPath init --initial-branch=main 2>&1 | Out-Null

        # CLAUDE.md 자동 생성
        $claudeContent = @"
# $newProjName

> $newDesc

## Tech Stack
<!-- 사용 기술 스택 -->

## Structure
<!-- 주요 디렉토리/파일 구조 -->

## Conventions
<!-- 코딩 컨벤션, 네이밍 규칙 등 -->
"@
        Set-Content -Path (Join-Path $newProjPath "CLAUDE.md") -Value $claudeContent -Encoding UTF8

        # .gitignore 기본 설정
        $giContent = @"
# Claude Code
.claude/worktrees/
.claude/.last-opened
"@
        Set-Content -Path (Join-Path $newProjPath ".gitignore") -Value $giContent -Encoding UTF8

        # 메타데이터 등록
        $meta | Add-Member -NotePropertyName $newProjName -NotePropertyValue ([PSCustomObject]@{ cat=$newCat; desc=$newDesc }) -Force
        Save-Meta $meta

        Touch-ProjectMarker $newProjPath
        Set-Location $newProjPath
        Write-Host "  -> $newProjPath" -ForegroundColor Green
        return
    }

    if ($action1 -eq "proj-edit") {
        $editItems = $projects | ForEach-Object {
            $catStr = if ($_.Cat) { "[$($_.Cat)]" } else { "[   ]" }
            "$($_.Name.PadRight(28))$catStr  $($_.Desc)"
        }
        $editPick = Pick-Menu -Items $editItems -Header "설명/카테고리 수정할 프로젝트 선택"
        if ($editPick -lt 0) { return }

        $target = $projects[$editPick]
        $curMeta = Get-Meta $target.Name $meta

        $curDesc = if ($curMeta) { $curMeta.desc } else { "" }
        $curCat  = if ($curMeta) { $curMeta.cat  } else { "" }

        Write-Host "  현재: [$curCat] $curDesc" -ForegroundColor DarkGray
        Write-Host -NoNewline "  설명 (Enter=유지): " -ForegroundColor Yellow
        $newDesc = Read-Host
        if (-not $newDesc) { $newDesc = $curDesc }
        Write-Host -NoNewline "  카테고리 (Enter=유지, 현재=$curCat): " -ForegroundColor Yellow
        $newCat = Read-Host
        if (-not $newCat) { $newCat = $curCat }

        $meta | Add-Member -NotePropertyName $target.Name -NotePropertyValue ([PSCustomObject]@{ cat=$newCat; desc=$newDesc }) -Force
        Save-Meta $meta
        Write-Host "  저장 완료: [$newCat] $newDesc" -ForegroundColor Green
        return
    }

    if ($action1 -eq "proj-ren") {
        $renItems = $projects | ForEach-Object { $_.Name }
        $renPick = Pick-Menu -Items $renItems -Header "이름변경할 프로젝트 선택"
        if ($renPick -lt 0) { return }

        $target = $projects[$renPick]
        Write-Host -NoNewline "  새 ���름 ($($target.Name)): " -ForegroundColor Yellow
        $newName = Read-Host
        if (-not $newName) { Write-Host "  취소됨."; return }

        $newPath = Join-Path $projectsRoot $newName
        if (Test-Path $newPath) {
            Write-Host "  이미 존재: $newPath" -ForegroundColor Red
            return
        }

        $curDir = (Get-Location).Path
        if ($curDir.StartsWith($target.Path)) {
            Set-Location $projectsRoot
        }

        Rename-Item -Path $target.Path -NewName $newName
        if ($?) {
            # 메타데이터도 키 변경
            $oldMeta = Get-Meta $target.Name $meta
            if ($oldMeta) {
                $meta.PSObject.Properties.Remove($target.Name)
                $meta | Add-Member -NotePropertyName $newName -NotePropertyValue $oldMeta -Force
                Save-Meta $meta
            }
            Write-Host "  변경 완료: $($target.Name) -> $newName" -ForegroundColor Green
        } else {
            Write-Host "  이름변경 실패. 다른 프로세스가 폴더를 사용 중일 수 있음" -ForegroundColor Red
        }
        return
    }

    if ($action1 -eq "proj-del") {
        $delItems = $projects | ForEach-Object { $_.Name }
        $delPick = Pick-Menu -Items $delItems -Header "삭제할 프로젝트 선택"
        if ($delPick -lt 0) { return }

        $target = $projects[$delPick]
        Write-Host -NoNewline "  '$($target.Name)' 을 정말 삭제? 복구 불가 (y/N): " -ForegroundColor Red
        $confirm = Read-Host
        if ($confirm -eq 'y' -or $confirm -eq 'Y') {
            $curDir = (Get-Location).Path
            if ($curDir.StartsWith($target.Path)) {
                Set-Location $projectsRoot
            }
            Remove-Item -Path $target.Path -Recurse -Force
            if ($?) {
                # 메타데이터도 제거
                if ($meta.PSObject.Properties[$target.Name]) {
                    $meta.PSObject.Properties.Remove($target.Name)
                    Save-Meta $meta
                }
                Write-Host "  삭제 완료: $($target.Name)" -ForegroundColor Green
            } else {
                Write-Host "  삭제 실패." -ForegroundColor Red
            }
        } else {
            Write-Host "  취소됨."
        }
        return
    }

    # ── Step 2: 프로젝트 선택됨 → git 여부 체크 ──────────────
    $projPath = $action1.Substring(5)  # "open:" 제거
    $projName = Split-Path $projPath -Leaf
    $isGit = (git -C $projPath rev-parse --git-dir 2>$null) -ne $null

    if (-not $isGit) {
        Touch-ProjectMarker $projPath
        Set-Location $projPath
        Write-Host "-> $projPath" -ForegroundColor Green
        return
    }

    # ── Step 3: 2단계 메뉴 (root / worktree) ──────────────────
    $projMeta = Get-Meta $projName $meta
    $wtMeta = if ($projMeta -and $projMeta.PSObject.Properties["wt"]) { $projMeta.wt } else { $null }

    $menuItems = [System.Collections.Generic.List[string]]::new()
    $menuActions = [System.Collections.Generic.List[string]]::new()

    $branch = git -C $projPath branch --show-current 2>$null
    if (-not $branch) { $branch = "HEAD" }
    $menuItems.Add("[main]  프로젝트 루트  ($branch)")
    $menuActions.Add("root")

    # 기존 worktree 목록 (날짜 + 설명 포함)
    $wtList = git -C $projPath worktree list --porcelain 2>$null
    $wtEntries = @()
    $wtPath = $null
    foreach ($line in $wtList) {
        if ($line -match '^worktree (.+)$') {
            $wtPath = $Matches[1]
        }
        if ($line -match '^branch refs/heads/(.+)$' -and $wtPath) {
            $normWt = (Resolve-Path $wtPath -ErrorAction SilentlyContinue).Path
            $normProj = (Resolve-Path $projPath -ErrorAction SilentlyContinue).Path
            if ($normWt -ne $normProj) {
                $wtName = Split-Path $wtPath -Leaf
                $wtBranch = $Matches[1]

                # worktree 날짜: git log > ���더 수정시각
                $wtGitLog = git -C $wtPath log -1 --format="%ct" 2>$null
                if ($wtGitLog -and $wtGitLog -match '^\d+$') {
                    $wtSortKey = [long]$wtGitLog
                } else {
                    $wtSortKey = [long]((Get-Item $wtPath).LastWriteTime.ToUniversalTime() - [datetime]"1970-01-01").TotalSeconds
                }
                $wtAgo = Format-Ago $wtSortKey

                # worktree 설명
                $wtDesc = ""
                if ($wtMeta -and $wtMeta.PSObject.Properties[$wtName]) {
                    $wtDesc = $wtMeta.$wtName.desc
                }

                $wtEntries += [PSCustomObject]@{ Name=$wtName; Branch=$wtBranch; Path=$wtPath; SortKey=$wtSortKey }
                $descSuffix = if ($wtDesc) { "  $wtDesc" } else { "" }
                $menuItems.Add("[wt]    $($wtName.PadRight(20))$($wtAgo.PadRight(8))$descSuffix")
                $menuActions.Add("wt:$wtPath")
            }
            $wtPath = $null
        }
    }

    $menuItems.Add("---")
    $menuActions.Add("noop")
    $menuItems.Add("[+new]   새 worktree 만들기")
    $menuActions.Add("new")

    if ($wtEntries.Count -gt 0) {
        $menuItems.Add("[edit]   worktree 설명 수정")
        $menuActions.Add("wt-edit")
        $menuItems.Add("[ren]    worktree 이름변경")
        $menuActions.Add("ren")
        $menuItems.Add("[del]    worktree 삭제")
        $menuActions.Add("del")
    }

    $pick = Pick-Menu -Items $menuItems.ToArray() -Header "$projName"
    if ($pick -lt 0) { return }

    $action = $menuActions[$pick]
    if ($action -eq "noop") { return }

    # worktree 메타 저장 헬퍼
    function Save-WtDesc([string]$name, [string]$desc) {
        $pm = Get-Meta $projName $meta
        if (-not $pm) {
            $pm = [PSCustomObject]@{ cat="Etc"; desc=""; wt=[PSCustomObject]@{} }
            $meta | Add-Member -NotePropertyName $projName -NotePropertyValue $pm -Force
        }
        if (-not $pm.PSObject.Properties["wt"]) {
            $pm | Add-Member -NotePropertyName "wt" -NotePropertyValue ([PSCustomObject]@{}) -Force
        }
        $pm.wt | Add-Member -NotePropertyName $name -NotePropertyValue ([PSCustomObject]@{ desc=$desc }) -Force
        Save-Meta $meta
    }

    function Remove-WtMeta([string]$name) {
        $pm = Get-Meta $projName $meta
        if ($pm -and $pm.PSObject.Properties["wt"] -and $pm.wt.PSObject.Properties[$name]) {
            $pm.wt.PSObject.Properties.Remove($name)
            Save-Meta $meta
        }
    }

    function Rename-WtMeta([string]$oldName, [string]$newName) {
        $pm = Get-Meta $projName $meta
        if ($pm -and $pm.PSObject.Properties["wt"] -and $pm.wt.PSObject.Properties[$oldName]) {
            $oldVal = $pm.wt.$oldName
            $pm.wt.PSObject.Properties.Remove($oldName)
            $pm.wt | Add-Member -NotePropertyName $newName -NotePropertyValue $oldVal -Force
            Save-Meta $meta
        }
    }

    switch -Wildcard ($action) {
        "root" {
            Touch-ProjectMarker $projPath
            Set-Location $projPath
            Write-Host "-> $projPath" -ForegroundColor Green
        }

        "wt:*" {
            $target = $action.Substring(3)
            if (Test-Path $target) {
                Touch-ProjectMarker $projPath
                Set-Location $target
                Write-Host "-> $target" -ForegroundColor Magenta
            } else {
                Write-Host "경로 없음: $target" -ForegroundColor Red
            }
        }

        "new" {
            Write-Host -NoNewline "  Worktree 이름 (예: auth-refactor): " -ForegroundColor Yellow
            $wtName = Read-Host
            if (-not $wtName) { Write-Host "취소됨."; return }

            Write-Host -NoNewline "  설명 (Enter=생략): " -ForegroundColor Yellow
            $wtDesc = Read-Host

            Ensure-WorktreeIgnore $projPath

            $wtDir = Join-Path $projPath ".claude\worktrees\$wtName"
            $parentDir = Split-Path $wtDir -Parent
            if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }

            $result = git -C $projPath worktree add $wtDir -b $wtName 2>&1
            if ($LASTEXITCODE -eq 0) {
                $includeFile = Join-Path $projPath ".worktreeinclude"
                if (Test-Path $includeFile) {
                    Get-Content $includeFile | ForEach-Object {
                        $f = $_.Trim()
                        if ($f -and -not $f.StartsWith("#")) {
                            $src = Join-Path $projPath $f
                            if (Test-Path $src) {
                                $dst = Join-Path $wtDir $f
                                $dstDir = Split-Path $dst -Parent
                                if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
                                Copy-Item $src $dst
                            }
                        }
                    }
                }

                # 설명 저장
                if ($wtDesc) { Save-WtDesc $wtName $wtDesc }

                Touch-ProjectMarker $projPath
                Set-Location $wtDir
                Write-Host "-> Worktree '$wtName' ($wtDir)" -ForegroundColor Magenta
                Write-Host "   claude 를 실행하면 이 브랜치에서 작업합니다" -ForegroundColor DarkGray
            } else {
                Write-Host "Worktree 생성 실패:" -ForegroundColor Red
                Write-Host $result -ForegroundColor Red
            }
        }

        "wt-edit" {
            $editItems = $wtEntries | ForEach-Object {
                $d = ""
                if ($wtMeta -and $wtMeta.PSObject.Properties[$_.Name]) { $d = $wtMeta.($_.Name).desc }
                "$($_.Name.PadRight(24))$d"
            }
            $editPick = Pick-Menu -Items $editItems -Header "설명 수정할 worktree 선택"
            if ($editPick -lt 0) { return }

            $editTarget = $wtEntries[$editPick]
            $curDesc = ""
            if ($wtMeta -and $wtMeta.PSObject.Properties[$editTarget.Name]) {
                $curDesc = $wtMeta.($editTarget.Name).desc
            }

            if ($curDesc) {
                Write-Host "  현재: $curDesc" -ForegroundColor DarkGray
            }
            Write-Host -NoNewline "  새 설명 (Enter=유지): " -ForegroundColor Yellow
            $newDesc = Read-Host
            if (-not $newDesc) { $newDesc = $curDesc }

            if ($newDesc) {
                Save-WtDesc $editTarget.Name $newDesc
                Write-Host "  저장 완료: $($editTarget.Name) -> $newDesc" -ForegroundColor Green
            }
        }

        "ren" {
            $renItems = $wtEntries | ForEach-Object { "$($_.Name.PadRight(24))($($_.Branch))" }
            $renPick = Pick-Menu -Items $renItems -Header "이름변경할 worktree 선택"
            if ($renPick -lt 0) { return }

            $renTarget = $wtEntries[$renPick]
            Write-Host -NoNewline "  새 이름: " -ForegroundColor Yellow
            $newName = Read-Host
            if (-not $newName) { Write-Host "  취소됨."; return }

            $oldDir = $renTarget.Path
            $newDir = Join-Path (Split-Path $oldDir -Parent) $newName

            $savedDir = (Get-Location).Path
            if ($savedDir.StartsWith($oldDir)) {
                Set-Location $projPath
            }

            git -C $projPath worktree move $oldDir $newDir 2>&1
            if ($LASTEXITCODE -eq 0) {
                git -C $projPath branch -m $renTarget.Branch $newName 2>&1
                Rename-WtMeta $renTarget.Name $newName
                Write-Host "  변경 완료: $($renTarget.Name) -> $newName" -ForegroundColor Green
            } else {
                Write-Host "  이름변경 실패. 다른 터미널이 해당 폴더에 있을 수 있음" -ForegroundColor Red
            }
        }

        "del" {
            $delItems = $wtEntries | ForEach-Object { "$($_.Name.PadRight(24))($($_.Branch))" }
            $delPick = Pick-Menu -Items $delItems -Header "삭제할 worktree 선택"
            if ($delPick -lt 0) { return }

            $delTarget = $wtEntries[$delPick]
            Write-Host -NoNewline "  '$($delTarget.Name)' 삭제? 브랜치는 유지됩니다. (y/N): " -ForegroundColor Yellow
            $confirm = Read-Host
            if ($confirm -eq 'y' -or $confirm -eq 'Y') {
                $curDir = (Get-Location).Path
                if ($curDir.StartsWith($delTarget.Path)) {
                    Set-Location $projPath
                }
                git -C $projPath worktree remove $delTarget.Path 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Remove-WtMeta $delTarget.Name
                    Write-Host "  삭제 완료: $($delTarget.Name)" -ForegroundColor Green
                } else {
                    Write-Host "  삭제 실패. --force 필요할 수 있음" -ForegroundColor Red
                }
            } else {
                Write-Host "  취소됨."
            }
        }
    }
}
