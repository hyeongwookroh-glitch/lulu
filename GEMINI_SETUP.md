# Gemini 영상 분석 셋업 가이드 (Windows)

Lulu 가 영상을 분석해서 포트폴리오 정리용 컷리스트·타임코드·태그를 뽑아주는 기능.
Google 의 Gemini API 를 쓰기 때문에 **본인 Google 계정으로 API key 를 발급**해야 한다.

> 이 가이드는 **Windows 10/11** 기준. macOS/Linux 는 `scripts/analyze-video.sh` (bash 버전) 사용.

---

## 1. 사전 설치 (처음 한 번만)

### 1-1. FFmpeg 설치
1. https://www.gyan.dev/ffmpeg/builds/ 접속
2. **release essentials** zip 다운로드 (예: `ffmpeg-release-essentials.zip`)
3. 압축 해제 → 예: `C:\ffmpeg\`
4. **환경 변수 PATH 에 추가**:
   - Windows 검색 → "환경 변수 편집"
   - 사용자 변수 `Path` 편집 → 새로 만들기 → `C:\ffmpeg\bin` 추가
5. 새 PowerShell 열어서 확인:
   ```powershell
   ffmpeg -version
   ffprobe -version
   ```

### 1-2. jq 설치
1. https://jqlang.github.io/jq/download/ → Windows 64-bit 링크 클릭
2. `jq-win64.exe` 다운로드 후 `jq.exe` 로 이름 변경
3. `C:\Windows\` 같은 PATH 폴더에 복사 (또는 `C:\ffmpeg\bin\` 같이 이미 PATH 에 있는 곳)
4. 확인:
   ```powershell
   jq --version
   ```

### 1-3. curl 확인 (보통 이미 설치됨)
Windows 10 1803+ 부터 `curl.exe` 기본 포함. 확인:
```powershell
curl.exe --version
```
없다면 https://curl.se/windows/ 에서 받아 PATH 에 추가.

### 1-4. PowerShell 7 권장
wrapper 스크립트는 PowerShell 7 (pwsh) 에서 가장 잘 돌아감.
- https://github.com/PowerShell/PowerShell/releases/latest 에서 MSI 설치
- 확인: `pwsh --version`

> Windows 기본 PowerShell 5.1 로도 동작은 하지만, 한글 인코딩·JSON 처리에서 7 이상이 안정적.

---

## 2. Gemini API key 발급

1. **Google AI Studio 접속**: https://aistudio.google.com/apikey
2. 본인 Google 계정 로그인 (외주 수익이 있으면 결제 계정과 같은 계정 사용).
3. **"Create API key"** 클릭 → 새 프로젝트 생성 허용.
4. 생성된 key 복사 (한 번만 표시됨. 안전한 곳에 보관).

### 요금
- **Gemini 2.5 Flash**: 무료 티어 존재 (RPM/RPD 제한 있음). 영상 분석에 충분.
- **Gemini 2.5 Pro**: 2026-04 기준 free tier 제한 강화 중 → 사실상 billing 활성 후 사용 가능.
- 평소엔 Flash 로만 돌려도 포폴 컷리스트 품질에 문제 없음.

---

## 3. `.env` 파일에 key 등록

`lulu` 폴더의 `.env` 파일을 메모장 또는 VS Code 로 열어서 아래 줄 추가:

```
GEMINI_API_KEY=발급받은_key_여기에_붙여넣기
```

`.env` 가 아직 없으면 `.env.example` 을 복사:
```powershell
Copy-Item .env.example .env
```

> `.env` 는 `.gitignore` 되어 있어서 git 에 올라가지 않음. 안심하고 저장.

저장 후 **Lulu 재시작** (`run-lulu.bat` 을 닫고 다시 실행) — 환경 변수는 재시작해야 반영됨.

---

## 4. PreToolUse hook 등록

`hooks\pre-tool-use.ps1` 이 원본 영상 업로드·wrapper 우회를 차단한다. `.claude\settings.local.json` 에 아래 `PreToolUse` 블록이 있어야 동작.

`.claude\settings.local.json` 전체 예시 (기존 Windows 오버라이드에 **PreToolUse 한 블록 추가**):

```json
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
```

이미 다른 항목이 있다면 `PreToolUse` 한 줄만 추가하면 된다.

---

## 5. 동작 테스트

짧은 테스트 영상 하나 준비 (30초~2분 권장). PowerShell 에서:

```powershell
pwsh scripts/analyze-video.ps1 C:\Users\<내이름>\Desktop\테스트영상.mp4
```

정상이면 다음 4단계가 순차적으로 출력됨:
1. `[1/4] 프록시 인코딩` — ffmpeg 가 저해상도 사본 생성 (`lulu-proxy\테스트영상\proxy.mp4`)
2. `[2/4] 분할 불필요` (2시간 미만) 또는 `1800s 단위 분할`
3. `[3/4] 업로드 + 분석` — Gemini 에 업로드 후 분석
4. `[4/4] 결과 출력` — JSON 으로 컷리스트 출력

분석 종료 후 Gemini 에 올린 파일은 자동 삭제됨 (20GB 프로젝트 쿼터 방지).

---

## 6. 일상 사용 패턴

### 포트폴리오 정리
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\포폴\편집본.mp4 > 편집본_분석.json
```

### 색감·표정 디테일 판단용 (더 높은 해상도)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\포폴\색보정본.mp4 -Preset review
```

### 외주 고객 영상 (명시 허용 필요)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\client\고객사A\러프컷.mp4 -ClientFootage
```
> 경로에 `\client\` 포함된 영상은 `-ClientFootage` 플래그 없으면 거부됨. 업로드 전 고객 동의 확인.

### 커스텀 프롬프트
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\영상.mp4 -Prompt "BGM 비트와 컷 전환 싱크 맞는지 구간별로 평가해줘"
```

### Pro 모델 (billing 활성 후)
```powershell
pwsh scripts/analyze-video.ps1 C:\Videos\영상.mp4 -Model pro
```

---

## 7. 자주 나오는 에러

| 에러 메시지 | 원인 | 해결 |
|---|---|---|
| `GEMINI_API_KEY 환경변수 미설정` | `.env` 에 key 없거나 Lulu 재시작 안 함 | `.env` 확인 후 `run-lulu.bat` 재실행 |
| `필수 명령어 없음: ffmpeg` | ffmpeg PATH 미등록 | 1-1 재확인, 새 PowerShell 창에서 `ffmpeg -version` 테스트 |
| `필수 명령어 없음: jq` | jq PATH 미등록 | 1-2 참고 |
| `업로드 실패 응답` / HTTP 403 | API key 무효 또는 billing 필요한 모델 호출 | Flash 로 재시도, key 재발급 |
| `429 Too Many Requests` | 무료 티어 RPM/RPD 초과 | 몇 분 대기 후 재시도. 자주 나면 billing 활성 검토 |
| `Gemini 처리 실패: FAILED` | 영상 포맷 이슈 | ffmpeg 로 mp4 재인코딩 후 재시도 |
| `이 스크립트는 시스템에서 실행되지 않도록 설정` | PS 실행 정책 | `pwsh -ExecutionPolicy Bypass -File scripts/analyze-video.ps1 ...` 로 우회 |
| hook 이 동작 안 함 | `.claude\settings.local.json` 의 PreToolUse 누락 | 4번 섹션 재확인 |

---

## 8. 주의사항

- **원본 업로드 절대 안 함**: wrapper 가 항상 ffmpeg 프록시(저해상도 사본) 만 업로드. 원본은 로컬에만 유지.
- **48시간 TTL**: Gemini 에 올린 파일은 48시간 지나면 자동 삭제됨 (wrapper 는 즉시 cleanup).
- **고객 영상**: Google 서버로 올라감. 외주 고객 영상은 반드시 사전 동의 확보 후 `-ClientFootage` 사용.
- **생성 파일 위치**: 프록시는 `lulu-proxy\<영상명>\`, 분할본은 `lulu-segment\<영상명>\`, 모두 `.gitignore` 됨. 디스크 용량 신경 쓰이면 작업 완료 후 폴더째 삭제.
