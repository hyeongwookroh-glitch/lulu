# Gemini 영상 분석 셋업 가이드 (Windows)

Lulu 가 영상을 분석해서 포트폴리오 정리용 컷리스트·타임코드·태그를 뽑아주는 기능.

> 이 가이드는 **Windows 10/11** 기준. macOS/Linux 는 `scripts/analyze-video.sh` 참고.

---

## TL;DR (친구가 직접 하는 건 하나뿐)

1. **API key 발급**: https://aistudio.google.com/apikey → "Create API key" → 복사
2. Lulu 한테 자연어로 부탁: **"영상 분석 셋업해줘"**
   - Lulu 가 `scripts/setup-video-analysis.ps1` 을 실행해서 ffmpeg/jq/PowerShell 7 설치 + `.claude/settings.local.json` 설정까지 다 해줌.
3. 셋업 도중 `.env` 에 `GEMINI_API_KEY=...` 채우라고 하면 복붙하고 저장.
4. Lulu 재시작 (`run-lulu.bat` 창 닫고 다시 실행).

끝. 이제 `영상 분석해줘 C:\영상.mp4` 같은 자연어 요청으로 사용.

---

## 자동 셋업 스크립트 상세 (`setup-video-analysis.ps1`)

이 스크립트 한 방이면 아래가 다 처리됨 (**멱등** — 이미 된 건 스킵):

1. `winget` 으로 **FFmpeg, jq, PowerShell 7** 설치 — 이미 있으면 건너뜀.
2. `.env` 없으면 `.env.example` 복사, `GEMINI_API_KEY` 비었으면 경고 출력.
3. `.claude/settings.local.json` 없으면 Windows hook override 템플릿 + PreToolUse 블록 함께 생성. 이미 있으면 `PreToolUse` 만 추가.

수동 실행하고 싶으면:
```powershell
pwsh scripts/setup-video-analysis.ps1
# (PowerShell 7 없으면 powershell.exe 로도 동작)
powershell -ExecutionPolicy Bypass -File scripts/setup-video-analysis.ps1
```

### winget 없으면?
Windows 10 1809 이전이거나 App Installer 누락 상태. Microsoft Store → **"앱 설치 관리자(App Installer)"** 설치 후 재실행.

---

## API key 발급 절차 (딱 1번)

1. https://aistudio.google.com/apikey 접속
2. 본인 Google 계정 로그인 (외주 수익 있으면 결제 계정과 동일 계정 권장)
3. **"Create API key"** 클릭 → 새 프로젝트 생성 허용
4. 생성된 key 복사 (한 번만 표시됨)

### 요금
- **Gemini 2.5 Flash**: 무료 티어 (RPM/RPD 제한 有). 영상 분석에 충분.
- **Gemini 2.5 Pro**: 2026-04 기준 free tier 축소 → 사실상 billing 활성 필요.
- 평소엔 Flash 로 충분. Pro 는 `-Model pro` 로 명시할 때만 쓰임.

---

## 일상 사용

### 포트폴리오 정리 (기본)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\포폴\편집본.mp4 > 편집본_분석.json
```

### 색감·표정 디테일용 (해상도 업)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\포폴\색보정본.mp4 -Preset review
```

### 외주 고객 영상 (명시 허용 필요)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\client\고객사A\러프컷.mp4 -ClientFootage
```
> 경로에 `\client\` 포함이면 `-ClientFootage` 없을 시 거부. 업로드 전 고객 동의 확인.

### 커스텀 프롬프트
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\영상.mp4 -Prompt "BGM 비트와 컷 전환 싱크 맞는지 구간별로 평가해줘"
```

### Pro 모델 (billing 활성 후)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\영상.mp4 -Model pro
```

---

## 자주 나오는 에러

| 에러 메시지 | 원인 | 해결 |
|---|---|---|
| `GEMINI_API_KEY 환경변수 미설정` | `.env` 에 key 없거나 Lulu 재시작 안 함 | `.env` 확인 후 `run-lulu.bat` 재실행 |
| `필수 명령어 없음: ffmpeg` | winget 설치 후 PATH 갱신 전 | Lulu 재시작. 그래도 안 되면 새 PowerShell 열고 `ffmpeg -version` 테스트 |
| `업로드 실패 응답` / HTTP 403 | API key 무효 또는 billing 필요한 모델 호출 | Flash 로 재시도, key 재발급 |
| `429 Too Many Requests` | 무료 티어 RPM/RPD 초과 | 몇 분 대기 후 재시도 |
| `Gemini 처리 실패: FAILED` | 영상 포맷 이슈 | ffmpeg 로 mp4 재인코딩 후 재시도 |
| `이 스크립트는 시스템에서 실행되지 않도록 설정` | PS 실행 정책 | `pwsh -ExecutionPolicy Bypass -File scripts/analyze-video.ps1 ...` |
| hook 동작 안 함 | `.claude\settings.local.json` 의 PreToolUse 누락 | `pwsh scripts/setup-video-analysis.ps1` 재실행 |

---

## 주의사항

- **원본 업로드 절대 안 함**: wrapper 가 항상 ffmpeg 프록시(저해상도 사본) 만 업로드. 원본은 로컬에만.
- **48시간 TTL**: Gemini 에 올린 파일은 48시간 후 자동 삭제 (wrapper 는 즉시 cleanup).
- **고객 영상**: Google 서버로 올라감. 사전 동의 확보 후 `-ClientFootage` 사용.
- **생성 파일**: `lulu-proxy\<영상명>\`, `lulu-segment\<영상명>\` (전부 `.gitignore` 됨). 디스크 여유 없으면 작업 후 폴더째 삭제.
