# setup-video-analysis.ps1 --- 영상 분석 기능 1-shot 셋업 (Windows)
#
# 친구가 해야 할 건 딱 하나: Gemini API key 발급 후 .env 에 붙여넣기.
# 나머지는 이 스크립트가 다 처리:
#   1. winget 으로 ffmpeg / jq / PowerShell 7 설치 (이미 있으면 스킵)
#   2. .env 없으면 .env.example 복사 + API key 입력 유도
#   3. .claude/settings.local.json 의 PreToolUse 블록 idempotent 추가
#
# 실행:
#   pwsh scripts/setup-video-analysis.ps1
#   (PowerShell 5 에서도 동작하되 7 권장)

$ErrorActionPreference = "Stop"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-OK($msg) { Write-Host "    OK: $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    주의: $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "    실패: $msg" -ForegroundColor Red }

# ---------- 0. winget 확인 ----------
Write-Step "winget 존재 확인"
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Fail "winget 없음. Windows 10 1809+ 또는 Windows 11 필요."
    Write-Host "    해결: Microsoft Store 에서 'App Installer' 설치 후 재실행."
    exit 1
}
Write-OK "winget 사용 가능"

# ---------- 1. 의존성 설치 ----------
function Install-IfMissing($cmd, $wingetId, $displayName) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-OK "$displayName 이미 설치됨 ($cmd)"
        return
    }
    Write-Step "$displayName 설치 중 (winget install $wingetId)..."
    & winget install --id $wingetId --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "$displayName 설치 실패. 수동 설치 필요."
        Write-Host "    참고: https://github.com/microsoft/winget-pkgs/tree/master/manifests"
        exit 1
    }
    Write-OK "$displayName 설치 완료"
}

Install-IfMissing "ffmpeg" "Gyan.FFmpeg" "FFmpeg"
Install-IfMissing "jq" "jqlang.jq" "jq"
Install-IfMissing "pwsh" "Microsoft.PowerShell" "PowerShell 7"

# winget 으로 설치한 도구는 현재 세션 PATH 에 반영 안 될 수 있음 → 재시작 안내
Write-Warn "설치 후 현재 PowerShell 세션은 PATH 갱신 전. Lulu 재시작 후 wrapper 사용 가능."

# ---------- 2. .env 셋업 ----------
Write-Step ".env 파일 확인"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $RepoRoot ".env"
$EnvExample = Join-Path $RepoRoot ".env.example"

if (-not (Test-Path -LiteralPath $EnvFile)) {
    if (Test-Path -LiteralPath $EnvExample) {
        Copy-Item -LiteralPath $EnvExample -Destination $EnvFile
        Write-OK ".env 생성됨 (.env.example 복사)"
    } else {
        New-Item -ItemType File -Path $EnvFile -Force | Out-Null
        Write-OK ".env 생성됨 (빈 파일)"
    }
} else {
    Write-OK ".env 이미 존재"
}

# GEMINI_API_KEY 키 존재 확인
$envContent = Get-Content -LiteralPath $EnvFile -Raw -ErrorAction SilentlyContinue
if ($envContent -notmatch '(?m)^GEMINI_API_KEY\s*=\s*\S') {
    Write-Warn "GEMINI_API_KEY 가 .env 에 아직 없음 (또는 비어있음)."
    Write-Host "    작업: Google AI Studio 에서 key 발급 후 .env 에 붙여넣기:"
    Write-Host "       1. https://aistudio.google.com/apikey 접속 (본인 Google 계정)"
    Write-Host "       2. 'Create API key' → 복사"
    Write-Host "       3. $EnvFile 파일에 아래 줄 추가 (또는 빈 값 채우기):"
    Write-Host "          GEMINI_API_KEY=발급받은_key"
    Write-Host "       4. 저장 후 Lulu 재시작 (run-lulu.bat)"
} else {
    Write-OK "GEMINI_API_KEY 이미 설정됨"
}

# ---------- 3. settings.local.json 에 PreToolUse 주입 ----------
# PS 5/7 호환 위해 JSON 파싱 대신 문자열 기반 체크. 기존 파일 있으면 PreToolUse 키만 확인.
Write-Step ".claude/settings.local.json PreToolUse 블록 주입"
$ClaudeDir = Join-Path $RepoRoot ".claude"
$LocalSettings = Join-Path $ClaudeDir "settings.local.json"
$null = New-Item -ItemType Directory -Force -Path $ClaudeDir

$Template = @'
{
  "dangerouslySkipPermissions": true,
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/session-start.ps1" }] }],
    "PreCompact":   [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/pre-compact.ps1" }] }],
    "PostCompact":  [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/post-compact.ps1" }] }],
    "Stop":         [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/stop.ps1" }] }],
    "PreToolUse":   [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/pre-tool-use.ps1" }] }],
    "PostToolUseFailure": [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/tool-error.ps1" }] }]
  }
}
'@

if (-not (Test-Path -LiteralPath $LocalSettings)) {
    Set-Content -LiteralPath $LocalSettings -Value $Template -Encoding UTF8
    Write-OK "settings.local.json 신규 생성 (Windows override + PreToolUse 포함)"
} else {
    $content = Get-Content -LiteralPath $LocalSettings -Raw
    if ($content -match '"PreToolUse"') {
        Write-OK "PreToolUse 이미 존재 — 스킵"
    } else {
        Write-Warn "settings.local.json 이 이미 있는데 PreToolUse 가 없음."
        Write-Host "    수동 병합 필요 — 아래 블록을 hooks 안에 추가:"
        Write-Host ""
        Write-Host '    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "powershell -ExecutionPolicy Bypass -File hooks/pre-tool-use.ps1" }] }]' -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "    파일 경로: $LocalSettings"
    }
}

# ---------- 완료 ----------
Write-Host ""
Write-Host "======================================================" -ForegroundColor Green
Write-Host " 셋업 완료. 남은 수동 작업:" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host ""
if ($envContent -notmatch '(?m)^GEMINI_API_KEY\s*=\s*\S') {
    Write-Host " 1. Google AI Studio 에서 Gemini API key 발급" -ForegroundColor White
    Write-Host "    https://aistudio.google.com/apikey" -ForegroundColor DarkGray
    Write-Host " 2. $EnvFile 의 GEMINI_API_KEY= 에 붙여넣기" -ForegroundColor White
    Write-Host " 3. Lulu 재시작 (run-lulu.bat 닫고 다시 실행)" -ForegroundColor White
} else {
    Write-Host " 이미 모든 준비 완료. Lulu 재시작 후 아래 명령어로 테스트:" -ForegroundColor White
    Write-Host '   pwsh scripts/analyze-video.ps1 "C:\path\to\video.mp4"' -ForegroundColor DarkGray
}
Write-Host ""
