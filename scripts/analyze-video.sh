#!/bin/bash
# analyze-video.sh — Gemini 영상 분석 wrapper
#
# 사용법:
#   scripts/analyze-video.sh <영상경로> [옵션]
#
# 옵션:
#   --model flash|pro       기본 flash. pro 는 billing 활성 필수.
#   --preset analyze|review 기본 analyze (720p/15fps/crf28). review 는 1080p/30fps/crf23.
#   --prompt "질문"         기본: 포트폴리오 컷리스트 추출 프롬프트.
#   --client-footage        외주 고객 영상 업로드 명시 허용. 미지정 시 client/ 경로 거부.
#   --keep                  분석 후 Gemini File API 업로드 파일 삭제 안 함 (디버그용).
#
# 강제 사항:
#   - 원본 영상은 절대 업로드하지 않음. ffmpeg 프록시 인코딩 필수.
#   - 2시간 초과 시 30분 단위 segment 분할.
#   - 분석 종료 후 Gemini File API 업로드 파일 자동 cleanup (--keep 제외).
#
# 의존:
#   - ffmpeg, ffprobe (brew install ffmpeg)
#   - curl, jq
#   - GEMINI_API_KEY 환경변수

set -euo pipefail

# ---------- 인자 파싱 ----------
MODEL="flash"
PRESET="analyze"
PROMPT=""
CLIENT_FOOTAGE=0
KEEP=0
INPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --preset) PRESET="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    --client-footage) CLIENT_FOOTAGE=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
    *) INPUT="$1"; shift ;;
  esac
done

# ---------- 사전 검증 ----------
if [[ -z "$INPUT" ]]; then
  echo "사용법: $0 <영상경로> [옵션]" >&2
  exit 1
fi
if [[ ! -f "$INPUT" ]]; then
  echo "영상 파일 없음: $INPUT" >&2
  exit 1
fi
if [[ -z "${GEMINI_API_KEY:-}" ]]; then
  echo "GEMINI_API_KEY 환경변수 미설정. .env 에 추가하고 쉘 재시작 또는 'source .env'." >&2
  exit 1
fi
for cmd in ffmpeg ffprobe curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "필수 명령어 없음: $cmd — brew install ffmpeg jq" >&2
    exit 1
  fi
done

# 외주 영상 경로 정책
if [[ "$CLIENT_FOOTAGE" -eq 0 && "$INPUT" == *"/client/"* ]]; then
  echo "외주 영상으로 보임 (경로에 /client/ 포함). Google 서버 업로드 동의 후 --client-footage 플래그로 재시도." >&2
  exit 1
fi

# 모델 매핑
case "$MODEL" in
  flash) MODEL_ID="gemini-2.5-flash" ;;
  pro)   MODEL_ID="gemini-2.5-pro" ;;
  *) echo "지원하지 않는 모델: $MODEL (flash|pro)" >&2; exit 1 ;;
esac

# 프리셋 매핑
case "$PRESET" in
  analyze) SCALE="1280:-2"; FPS="15"; CRF="28" ;;
  review)  SCALE="1920:-2"; FPS="30"; CRF="23" ;;
  *) echo "지원하지 않는 프리셋: $PRESET (analyze|review)" >&2; exit 1 ;;
esac

# 기본 프롬프트
if [[ -z "$PROMPT" ]]; then
  PROMPT=$(cat <<'EOF'
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
EOF
)
fi

# ---------- 출력 경로 ----------
STEM="$(basename "${INPUT%.*}")"
PROXY_DIR="lulu-proxy/${STEM}"
SEGMENT_DIR="lulu-segment/${STEM}"
CACHE_DIR=".gemini-files"
mkdir -p "$PROXY_DIR" "$SEGMENT_DIR" "$CACHE_DIR"
PROXY_FILE="${PROXY_DIR}/proxy.mp4"
UPLOADED_NAMES_FILE="${CACHE_DIR}/${STEM}.names"
: > "$UPLOADED_NAMES_FILE"

# ---------- cleanup trap ----------
cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    echo "[cleanup] --keep 지정됨. Gemini 업로드 파일 보존." >&2
    return
  fi
  if [[ -s "$UPLOADED_NAMES_FILE" ]]; then
    echo "[cleanup] Gemini 업로드 파일 삭제 중..." >&2
    while read -r name; do
      [[ -z "$name" ]] && continue
      curl -sS -X DELETE \
        -H "x-goog-api-key: ${GEMINI_API_KEY}" \
        "https://generativelanguage.googleapis.com/v1beta/${name}" >/dev/null || true
    done < "$UPLOADED_NAMES_FILE"
  fi
}
trap cleanup EXIT

# ---------- 1. 프록시 인코딩 ----------
echo "[1/4] 프록시 인코딩 (preset=${PRESET}): ${INPUT} -> ${PROXY_FILE}" >&2
ffmpeg -y -loglevel error -i "$INPUT" \
  -vf "scale=${SCALE},fps=${FPS}" \
  -c:v libx264 -crf "$CRF" -preset fast \
  -c:a aac -b:a 96k \
  "$PROXY_FILE"

DURATION=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$PROXY_FILE")
DURATION_INT=${DURATION%.*}

# ---------- 2. 분할 (2시간 초과 시) ----------
SEGMENTS=()
if (( DURATION_INT > 7200 )); then
  echo "[2/4] 2시간 초과 (${DURATION_INT}s). 1800s 단위 분할." >&2
  ffmpeg -y -loglevel error -i "$PROXY_FILE" \
    -c copy -f segment -segment_time 1800 -reset_timestamps 1 \
    "${SEGMENT_DIR}/seg_%03d.mp4"
  while IFS= read -r -d '' f; do SEGMENTS+=("$f"); done < <(find "$SEGMENT_DIR" -name 'seg_*.mp4' -print0 | sort -z)
else
  echo "[2/4] 분할 불필요 (${DURATION_INT}s)." >&2
  SEGMENTS=("$PROXY_FILE")
fi

# ---------- 3. 업로드 + 분석 ----------
upload_file() {
  local path="$1"
  local size mime
  size=$(wc -c < "$path" | tr -d ' ')
  mime="video/mp4"
  local display
  display="$(basename "$path")"

  # resumable upload start
  local start_json
  start_json=$(jq -n --arg name "$display" '{file: {display_name: $name}}')
  local headers_file
  headers_file=$(mktemp)
  curl -sS -D "$headers_file" -o /dev/null \
    -H "x-goog-api-key: ${GEMINI_API_KEY}" \
    -H "X-Goog-Upload-Protocol: resumable" \
    -H "X-Goog-Upload-Command: start" \
    -H "X-Goog-Upload-Header-Content-Length: ${size}" \
    -H "X-Goog-Upload-Header-Content-Type: ${mime}" \
    -H "Content-Type: application/json" \
    -d "$start_json" \
    "https://generativelanguage.googleapis.com/upload/v1beta/files"
  local upload_url
  upload_url=$(awk -F': ' 'tolower($1)=="x-goog-upload-url"{print $2}' "$headers_file" | tr -d '\r\n')
  rm -f "$headers_file"
  if [[ -z "$upload_url" ]]; then
    echo "업로드 URL 획득 실패: $path" >&2; return 1
  fi

  # upload bytes + finalize
  local meta
  meta=$(curl -sS -X POST \
    -H "Content-Length: ${size}" \
    -H "X-Goog-Upload-Offset: 0" \
    -H "X-Goog-Upload-Command: upload, finalize" \
    --data-binary "@${path}" \
    "$upload_url")
  local fname furi
  fname=$(echo "$meta" | jq -r '.file.name')
  furi=$(echo "$meta" | jq -r '.file.uri')
  if [[ "$fname" == "null" || -z "$fname" ]]; then
    echo "업로드 실패 응답: $meta" >&2; return 1
  fi
  echo "$fname" >> "$UPLOADED_NAMES_FILE"

  # ACTIVE 상태 폴링 (영상은 처리 시간 걸림)
  for _ in $(seq 1 60); do
    local state
    state=$(curl -sS \
      -H "x-goog-api-key: ${GEMINI_API_KEY}" \
      "https://generativelanguage.googleapis.com/v1beta/${fname}" | jq -r '.state')
    if [[ "$state" == "ACTIVE" ]]; then break; fi
    if [[ "$state" == "FAILED" ]]; then echo "Gemini 처리 실패: $fname" >&2; return 1; fi
    sleep 2
  done

  echo "$furi"
}

call_gemini() {
  local file_uri="$1" prompt="$2"
  local payload
  payload=$(jq -n --arg uri "$file_uri" --arg mime "video/mp4" --arg prompt "$prompt" '{
    contents: [{
      parts: [
        {file_data: {mime_type: $mime, file_uri: $uri}},
        {text: $prompt}
      ]
    }]
  }')
  curl -sS -X POST \
    -H "x-goog-api-key: ${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://generativelanguage.googleapis.com/v1beta/models/${MODEL_ID}:generateContent" \
    | jq -r '.candidates[0].content.parts[0].text // empty'
}

echo "[3/4] 업로드 + 분석 (segments=${#SEGMENTS[@]}, model=${MODEL_ID})" >&2
SEGMENT_RESULTS=()
for seg in "${SEGMENTS[@]}"; do
  echo "  - ${seg} 업로드 중..." >&2
  uri=$(upload_file "$seg")
  echo "  - ${seg} 분석 중..." >&2
  result=$(call_gemini "$uri" "$PROMPT")
  SEGMENT_RESULTS+=("$result")
done

# ---------- 4. 통합 (2-pass) ----------
echo "[4/4] 결과 출력" >&2
if [[ ${#SEGMENT_RESULTS[@]} -eq 1 ]]; then
  echo "${SEGMENT_RESULTS[0]}"
else
  # 각 segment 결과를 이어붙여 통합 요약 (단순 concat — Gemini 재호출로 merge 원하면 여기 확장)
  {
    echo "{\"segments\": ["
    for i in "${!SEGMENT_RESULTS[@]}"; do
      [[ $i -gt 0 ]] && echo ","
      echo "${SEGMENT_RESULTS[$i]}"
    done
    echo "]}"
  }
fi
