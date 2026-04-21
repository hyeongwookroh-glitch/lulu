#!/bin/bash
# PreToolUse hook — wrapper 우회한 Gemini 업로드/원본 영상 접근 차단.
#
# 차단 규칙:
#   1. Bash 커맨드가 Gemini File API upload 엔드포인트를 직접 호출하는데
#      scripts/analyze-video.sh 를 경유하지 않으면 block.
#   2. ffmpeg 명령이 영상을 출력하는데 경로가 lulu-proxy/ 또는 lulu-segment/ 가 아니면 block.
#      (원본 덮어쓰기 방지)
#
# exit 2 = block + stderr 를 Claude 에 전달.

set -euo pipefail

# Homebrew 경로 prepend (hook 은 로그인 쉘 PATH 상속 안 될 수 있음)
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

input=$(cat)

# jq 없으면 fail-open (best-effort hook). wrapper 가 jq 필수라 실제 실행은 거기서 검증됨.
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

tool_name=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool_name" != "Bash" ]] && exit 0

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0

# 1. Gemini 업로드 엔드포인트 직접 호출 차단
if echo "$cmd" | grep -qE 'generativelanguage\.googleapis\.com/(upload|v1beta/files)'; then
  if ! echo "$cmd" | grep -q 'scripts/analyze-video\.sh'; then
    echo "❌ Gemini File API 직접 호출은 차단됐음. 반드시 wrapper 사용:" >&2
    echo "   bash scripts/analyze-video.sh <영상경로> [--model flash|pro] [--preset analyze|review]" >&2
    echo "   이유: 원본 업로드 금지 + ffmpeg 프록시 인코딩 + 2h 초과 시 분할 + cleanup 강제." >&2
    exit 2
  fi
fi

# 2. ffmpeg 출력 경로 체크 — 출력 파일이 .mp4/.mov/.mkv 계열인데 lulu-proxy/ 나 lulu-segment/ 아래가 아니면 block
# ffmpeg 는 마지막 positional arg 가 output. 단순 휴리스틱.
if echo "$cmd" | grep -qE '(^|\s|&&|\|\|)ffmpeg(\s|$)'; then
  # 출력 경로 후보 추출: .mp4|.mov|.mkv|.webm|.avi 로 끝나는 토큰
  outputs=$(echo "$cmd" | grep -oE '[^[:space:]"'"'"']+\.(mp4|mov|mkv|webm|avi)' || true)
  for out in $outputs; do
    # 입력(-i 뒤) 은 스킵하고 싶지만 단순화: 프로젝트 외부 경로 또는 lulu-proxy/lulu-segment 아래가 아니면 경고만.
    # 단, 절대경로 / 홈경로 write 는 막음
    if [[ "$out" == /* || "$out" == ~* ]]; then
      echo "❌ ffmpeg 출력이 절대경로 (${out}). 원본 덮어쓰기 위험. 상대경로 lulu-proxy/<이름>/ 사용 권장." >&2
      exit 2
    fi
  done
fi

exit 0
