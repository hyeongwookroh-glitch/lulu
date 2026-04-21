# analyze-video.ps1 --- Gemini 영상 분석 wrapper (Windows PowerShell 7+)
#
# 사용법:
#   pwsh scripts/analyze-video.ps1 <영상경로> [옵션]
#
# 옵션:
#   -Model flash|pro          기본 flash. pro 는 billing 활성 필수.
#   -Preset analyze|review    기본 analyze (720p/15fps/crf28). review 는 1080p/30fps/crf23.
#   -Prompt "질문"            기본: 포트폴리오 컷리스트 추출 프롬프트.
#   -ClientFootage            외주 고객 영상 업로드 명시 허용. 미지정 시 \client\ 경로 거부.
#   -Keep                     분석 후 Gemini 업로드 파일 삭제 안 함 (디버그용).
#
# 강제 사항:
#   - 원본 영상은 절대 업로드하지 않음. ffmpeg 프록시 인코딩 필수.
#   - 2시간 초과 시 30분 단위 segment 분할.
#   - 분석 종료 후 Gemini File API 업로드 파일 자동 cleanup.
#
# 의존:
#   - ffmpeg, ffprobe (PATH 등록)
#   - curl.exe (Windows 10 1803+ 기본), jq.exe
#   - $env:GEMINI_API_KEY 환경변수

param(
    [Parameter(Mandatory=$true, Position=0)][string]$VideoFile,
    [ValidateSet("flash","pro")][string]$Model = "flash",
    [ValidateSet("analyze","review")][string]$Preset = "analyze",
    [string]$Prompt = "",
    [switch]$ClientFootage,
    [switch]$Keep
)

$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'

# ---------- 사전 검증 ----------
if (-not (Test-Path -LiteralPath $VideoFile)) {
    Write-Error "영상 파일 없음: $VideoFile"
    exit 1
}
if (-not $env:GEMINI_API_KEY) {
    Write-Error "GEMINI_API_KEY 환경변수 미설정. .env 에 추가 후 Lulu 재시작 (run-lulu.bat)."
    exit 1
}
foreach ($c in @("ffmpeg","ffprobe","curl","jq")) {
    if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
        Write-Error "필수 명령어 없음: $c --- GEMINI_SETUP.md 참고해서 설치"
        exit 1
    }
}

# 외주 영상 경로 정책
if (-not $ClientFootage -and $VideoFile -match "[\\/]client[\\/]") {
    Write-Error "외주 영상으로 보임 (경로에 \client\ 포함). Google 서버 업로드 동의 후 -ClientFootage 플래그로 재시도."
    exit 1
}

# 모델/프리셋 매핑
switch ($Model) {
    "flash" { $ModelId = "gemini-2.5-flash" }
    "pro"   { $ModelId = "gemini-2.5-pro" }
}
switch ($Preset) {
    "analyze" { $Scale="1280:-2"; $Fps="15"; $Crf="28" }
    "review"  { $Scale="1920:-2"; $Fps="30"; $Crf="23" }
}

# 기본 프롬프트
if (-not $Prompt) {
    $Prompt = @'
이 영상을 포트폴리오 정리용으로 분석해줘. 아래 JSON 스키마로 출력:
{
  "summary": "영상 한줄 요약",
  "cuts": [
    {
      "in": "HH:MM:SS",
      "out": "HH:MM:SS",
      "type": "컷 유형 (인서트/와이드/클로즈업/트랜지션 등)",
      "comment": "핵심 시각적/연출 메모",
      "tags": ["감정/템포/무드 태그 (예: 활기찬, 잔잔한, 고조)"]
    }
  ],
  "highlights": ["추천 하이라이트 구간 HH:MM:SS - HH:MM:SS 와 이유"]
}
JSON 만 출력. 설명 문장 금지.
'@
}

# ---------- 출력 경로 ----------
$Stem = [System.IO.Path]::GetFileNameWithoutExtension($VideoFile)
$ProxyDir = "lulu-proxy\$Stem"
$SegDir   = "lulu-segment\$Stem"
$CacheDir = ".gemini-files"
$null = New-Item -ItemType Directory -Force -Path $ProxyDir, $SegDir, $CacheDir
$ProxyFile = Join-Path $ProxyDir "proxy.mp4"
$UploadedNames = Join-Path $CacheDir "$Stem.names"
Set-Content -LiteralPath $UploadedNames -Value "" -NoNewline

# ---------- cleanup ----------
function Invoke-Cleanup {
    if ($Keep) {
        [Console]::Error.WriteLine("[cleanup] -Keep 지정됨. Gemini 업로드 파일 보존.")
        return
    }
    if (Test-Path -LiteralPath $UploadedNames) {
        $names = Get-Content -LiteralPath $UploadedNames | Where-Object { $_ -ne "" }
        if ($names) {
            [Console]::Error.WriteLine("[cleanup] Gemini 업로드 파일 삭제 중...")
            foreach ($n in $names) {
                & curl.exe -sS -X DELETE -H "x-goog-api-key: $env:GEMINI_API_KEY" "https://generativelanguage.googleapis.com/v1beta/${n}" 2>$null | Out-Null
            }
        }
    }
}

try {
    # ---------- 1. 프록시 인코딩 ----------
    [Console]::Error.WriteLine("[1/4] 프록시 인코딩 ($Preset): $VideoFile -> $ProxyFile")
    & ffmpeg -y -loglevel error -i $VideoFile `
        -vf "scale=$Scale,fps=$Fps" `
        -c:v libx264 -crf $Crf -preset fast `
        -c:a aac -b:a 96k `
        $ProxyFile
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg 프록시 인코딩 실패" }

    $DurStr = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $ProxyFile
    $Duration = [math]::Floor([double]$DurStr)

    # ---------- 2. 분할 ----------
    $Segments = @()
    if ($Duration -gt 7200) {
        [Console]::Error.WriteLine("[2/4] 2시간 초과 ($Duration s). 1800s 단위 분할.")
        & ffmpeg -y -loglevel error -i $ProxyFile `
            -c copy -f segment -segment_time 1800 -reset_timestamps 1 `
            (Join-Path $SegDir "seg_%03d.mp4")
        if ($LASTEXITCODE -ne 0) { throw "ffmpeg 분할 실패" }
        $Segments = Get-ChildItem -LiteralPath $SegDir -Filter "seg_*.mp4" | Sort-Object Name | ForEach-Object { $_.FullName }
    } else {
        [Console]::Error.WriteLine("[2/4] 분할 불필요 ($Duration s).")
        $Segments = @($ProxyFile)
    }

    # ---------- 3. 업로드 + 분석 ----------
    function Upload-Video([string]$Path) {
        $size = (Get-Item -LiteralPath $Path).Length
        $display = [System.IO.Path]::GetFileName($Path)
        $startBody = @{ file = @{ display_name = $display } } | ConvertTo-Json -Compress

        $headersFile = New-TemporaryFile
        & curl.exe -sS -D $headersFile.FullName -o NUL `
            -H "x-goog-api-key: $env:GEMINI_API_KEY" `
            -H "X-Goog-Upload-Protocol: resumable" `
            -H "X-Goog-Upload-Command: start" `
            -H "X-Goog-Upload-Header-Content-Length: $size" `
            -H "X-Goog-Upload-Header-Content-Type: video/mp4" `
            -H "Content-Type: application/json" `
            -d $startBody `
            "https://generativelanguage.googleapis.com/upload/v1beta/files"

        $headerLines = Get-Content -LiteralPath $headersFile.FullName
        Remove-Item -LiteralPath $headersFile.FullName -ErrorAction SilentlyContinue

        $uploadUrl = $null
        foreach ($line in $headerLines) {
            if ($line -match '^(?i)x-goog-upload-url:\s*(.+)$') {
                $uploadUrl = $Matches[1].Trim()
                break
            }
        }
        if (-not $uploadUrl) { throw "업로드 URL 획득 실패: $Path" }

        $metaRaw = & curl.exe -sS -X POST `
            -H "Content-Length: $size" `
            -H "X-Goog-Upload-Offset: 0" `
            -H "X-Goog-Upload-Command: upload, finalize" `
            --data-binary "@$Path" `
            $uploadUrl
        $metaJson = ($metaRaw | Out-String).Trim()
        $meta = $metaJson | ConvertFrom-Json
        $fname = $meta.file.name
        if (-not $fname) { throw "업로드 실패 응답: $metaJson" }
        Add-Content -LiteralPath $UploadedNames -Value $fname

        # ACTIVE 폴링
        for ($i=0; $i -lt 60; $i++) {
            $stateRaw = & curl.exe -sS -H "x-goog-api-key: $env:GEMINI_API_KEY" "https://generativelanguage.googleapis.com/v1beta/${fname}"
            $stateJson = ($stateRaw | Out-String).Trim()
            $state = ($stateJson | ConvertFrom-Json).state
            if ($state -eq "ACTIVE") { break }
            if ($state -eq "FAILED") { throw "Gemini 처리 실패: $fname" }
            Start-Sleep -Seconds 2
        }
        return $meta.file.uri
    }

    function Call-Gemini([string]$Uri, [string]$P) {
        $payload = @{
            contents = @(@{
                parts = @(
                    @{ file_data = @{ mime_type = "video/mp4"; file_uri = $Uri } },
                    @{ text = $P }
                )
            })
        } | ConvertTo-Json -Depth 10 -Compress
        $tempBody = New-TemporaryFile
        [System.IO.File]::WriteAllText($tempBody.FullName, $payload, [System.Text.Encoding]::UTF8)
        $respRaw = & curl.exe -sS -X POST `
            -H "x-goog-api-key: $env:GEMINI_API_KEY" `
            -H "Content-Type: application/json" `
            -d "@$($tempBody.FullName)" `
            "https://generativelanguage.googleapis.com/v1beta/models/${ModelId}:generateContent"
        Remove-Item -LiteralPath $tempBody.FullName -ErrorAction SilentlyContinue
        $resp = ($respRaw | Out-String).Trim()
        $parsed = $resp | ConvertFrom-Json
        return $parsed.candidates[0].content.parts[0].text
    }

    [Console]::Error.WriteLine("[3/4] 업로드 + 분석 (segments=$($Segments.Count), model=$ModelId)")
    $Results = @()
    foreach ($seg in $Segments) {
        [Console]::Error.WriteLine("  - $seg 업로드 중...")
        $uri = Upload-Video $seg
        [Console]::Error.WriteLine("  - $seg 분석 중...")
        $Results += ,(Call-Gemini $uri $Prompt)
    }

    # ---------- 4. 통합 ----------
    [Console]::Error.WriteLine("[4/4] 결과 출력")
    if ($Results.Count -eq 1) {
        Write-Output $Results[0]
    } else {
        $merged = [ordered]@{ segments = @() }
        foreach ($r in $Results) {
            try { $merged.segments += ,($r | ConvertFrom-Json) }
            catch { $merged.segments += $r }
        }
        Write-Output ($merged | ConvertTo-Json -Depth 20)
    }
}
finally {
    Invoke-Cleanup
}
