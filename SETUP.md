# Lulu Auto-Setup Guide

> Claude Code가 이 파일을 읽으면 아래 단계를 순서대로 실행해서 Lulu 에이전트 환경을 완성합니다.

## Prerequisites (사람이 미리 준비)

1. **Claude Code CLI** 설치 및 로그인 완료
2. **Node.js 22+** 설치
3. **Discord Bot 생성** 완료 — 아래 값 확보:
   - `DISCORD_BOT_TOKEN`
   - `DISCORD_HOME_CHANNEL` (봇이 멘션 없이도 듣는 채널 ID)

---

## Discord Bot 생성 가이드

### 1. Discord Developer Portal에서 Application 생성
1. https://discord.com/developers/applications 접속
2. "New Application" 클릭 → 이름: `Lulu`
3. 좌측 메뉴 "Bot" 클릭
4. "Reset Token" 클릭 → **토큰 복사** (이게 `DISCORD_BOT_TOKEN`)

### 2. Bot 권한 설정
Bot 페이지에서:
- **Privileged Gateway Intents** 3개 모두 활성화:
  - PRESENCE INTENT
  - SERVER MEMBERS INTENT
  - MESSAGE CONTENT INTENT

### 3. Bot을 서버에 초대
1. 좌측 "OAuth2" → "URL Generator"
2. Scopes: `bot`
3. Bot Permissions: `Send Messages`, `Read Message History`, `Add Reactions`, `Attach Files`, `Read Messages/View Channels`
4. 생성된 URL을 복사해서 브라우저에서 열기 → 서버 선택 → 초대

### 4. 채널 ID 확인
1. Discord 설정 → 고급 → "개발자 모드" 활성화
2. 원하는 채널 우클릭 → "채널 ID 복사" → 이게 `DISCORD_HOME_CHANNEL`

---

## Auto-Setup Steps

### Step 1: Dependencies

```bash
cd channels && npm install && cd ..
```

### Step 2: Environment Variables

`.env.example` → `.env` 복사 후 토큰 입력:

```bash
cp .env.example .env
```

`.env` 내용:
```
DISCORD_BOT_TOKEN=실제토큰
DISCORD_HOME_CHANNEL=실제채널ID
```

### Step 3: Claude Code Settings

`.claude/` 디렉토리는 gitignore 되어 있으므로 직접 생성:

```bash
mkdir -p .claude/memory
```

`.claude/settings.local.json` 생성:
```json
{
  "permissions": {
    "allow": [
      "Bash(npm install:*)",
      "WebFetch(domain:github.com)"
    ]
  },
  "dangerouslySkipPermissions": true,
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash hooks/session-start.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash hooks/pre-compact.sh"
          }
        ]
      }
    ],
    "PostCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash hooks/post-compact.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash hooks/stop.sh"
          }
        ]
      }
    ]
  }
}
```

### Step 4: Memory Directory

Lulu 메모리 디렉토리 생성:

```bash
mkdir -p ~/Documents/Lulu_Memory/session_notes/lulu
mkdir -p ~/Documents/Lulu_Memory/inbox
```

### Step 5: Memory Index

`.claude/memory/MEMORY.md` 생성:
```markdown
# Lulu Memory Index

(빈 상태 — 작업 진행하면서 자동으로 채워짐)
```

### Step 6: Verification

모든 설정 완료 후 테스트 실행:

```bash
bash run-lulu.sh
```

정상 작동 확인:
- `[Lulu Session Startup]` 메시지 출력
- Discord 메시지 수신/응답 가능
- 세션 노트 `~/Documents/Lulu_Memory/session_notes/lulu/YYYY-MM-DD.md` 생성

---

## Notion MCP 연동 (선택)

포트폴리오를 Notion에 직접 작성하려면 Notion MCP를 추가 설정합니다.

### 1. Notion Integration 생성
1. https://www.notion.so/profile/integrations 접속
2. "New integration" → 이름: `Lulu`
3. Capabilities: Read content, Update content, Insert content 체크
4. **Internal Integration Secret** 복사

### 2. Notion 페이지에 Integration 연결
포트폴리오를 만들 Notion 페이지/DB에서:
1. 우상단 `...` → "Connections" → `Lulu` 추가

### 3. .env에 추가
```
NOTION_API_KEY=ntn_실제토큰
```

### 4. MCP 설정에 Notion 추가
`.mcp-lulu.json`을 수정:
```json
{
  "mcpServers": {
    "lulu": {
      "command": "node",
      "args": ["channels/lulu-discord.mjs"]
    },
    "notion": {
      "command": "npx",
      "args": ["-y", "@notionhq/notion-mcp-server"],
      "env": {
        "OPENAPI_MCP_HEADERS": "{\"Authorization\": \"Bearer ntn_실제토큰\", \"Notion-Version\": \"2022-06-28\"}"
      }
    }
  }
}
```

---

## 파일 읽기 기능

Lulu는 Claude Code의 내장 Read 도구를 사용하여 다양한 파일을 읽을 수 있습니다:

| 파일 형식 | 지원 | 비고 |
|-----------|------|------|
| 이미지 (PNG, JPG, GIF, WebP) | O | 시각적으로 분석 (multimodal) |
| PDF | O | 텍스트 추출 + 페이지 지정 가능 |
| 텍스트 (TXT, MD, CSV) | O | 직접 읽기 |
| Excel (XLSX) | △ | Bash에서 변환 필요 |
| Word (DOCX) | △ | Bash에서 변환 필요 |

Discord에서 파일을 보내면 자동으로 로컬에 다운로드되고 Read 도구로 분석됩니다.

---

## Troubleshooting

| 증상 | 원인 | 해결 |
|------|------|------|
| `MODULE_NOT_FOUND` | npm install 미완료 | `cd channels && npm install` |
| Discord 연결 안됨 | 토큰 오류 | `.env` 토큰 재확인 |
| 메시지 감지 안됨 | MESSAGE CONTENT Intent 미활성화 | Developer Portal → Bot → Intent 활성화 |
| hooks 실행 안됨 | `.claude/settings.local.json` 미생성 | Step 3 재실행 |
| 세션 노트 에러 | 메모리 디렉토리 없음 | Step 4 재실행 |
