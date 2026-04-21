# PreToolUse hook (Windows PowerShell) --- wrapper 우회한 Gemini 업로드/원본 경로 접근 차단.
#
# 차단 규칙:
#   1. Bash 커맨드가 Gemini File API upload 엔드포인트를 직접 호출하는데
#      scripts/analyze-video.(ps1|sh) 를 경유하지 않으면 block.
#   2. ffmpeg 명령이 출력을 절대경로 (드라이브:/ 또는 /) 로 지정하면 block.
#
# exit 2 = block + stderr 를 Claude 에 전달.

$ErrorActionPreference = "Stop"

# stdin 읽기
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }

try {
    $data = $raw | ConvertFrom-Json -ErrorAction Stop
} catch {
    exit 0
}

if ($data.tool_name -ne "Bash") { exit 0 }
$cmd = $data.tool_input.command
if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }

# 1. Gemini 업로드 엔드포인트 직접 호출 차단
if ($cmd -match 'generativelanguage\.googleapis\.com/(upload|v1beta/files)') {
    if ($cmd -notmatch 'scripts[\\/]analyze-video\.(ps1|sh)') {
        [Console]::Error.WriteLine("X Gemini File API 직접 호출은 차단됐음. 반드시 wrapper 사용:")
        [Console]::Error.WriteLine("   pwsh scripts/analyze-video.ps1 <영상경로> [-Model flash|pro] [-Preset analyze|review]")
        [Console]::Error.WriteLine("   이유: 원본 업로드 금지 + ffmpeg 프록시 인코딩 + 2h 초과 시 분할 + cleanup 강제.")
        exit 2
    }
}

# 2. ffmpeg 절대경로 출력 차단
if ($cmd -match '(?:^|\s|&&|\|\|)ffmpeg(?:\s|$)') {
    $matches = [regex]::Matches($cmd, '[^\s"'']+\.(mp4|mov|mkv|webm|avi)')
    foreach ($m in $matches) {
        $out = $m.Value
        # Windows 드라이브 경로 (C:\, D:/) 또는 Unix 절대경로 (/), 홈경로 (~)
        if ($out -match '^[A-Za-z]:[\\/]' -or $out -match '^[\\/]' -or $out -match '^~') {
            [Console]::Error.WriteLine("X ffmpeg 출력이 절대경로 ($out). 원본 덮어쓰기 위험. 상대경로 lulu-proxy\<이름>\ 사용 권장.")
            exit 2
        }
    }
}

exit 0
