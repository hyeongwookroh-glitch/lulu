# Lulu

개인 AI 비서 에이전트. Discord로 통신, 로컬 파일 읽기/분석, Notion 포트폴리오 작성 지원.

---

## 요구사항
- macOS
- [Claude Code CLI](https://claude.ai/code) 설치 및 로그인
- Node.js 22+

## 초기 설치

```bash
git clone https://github.com/hyeongwookroh-glitch/lulu.git
cd lulu

# 의존성 설치
cd channels && npm install && cd ..

# 환경변수 설정
cp .env.example .env
# .env 편집: Discord 토큰 입력
```

## 실행

```bash
bash run-lulu.sh
```

## 디렉토리 구조

```
lulu/
├── CLAUDE.md               # 페르소나 (Lulu)
├── README.md               # 이 파일
├── SETUP.md                # 자동 셋업 가이드 (Discord Bot + Notion MCP)
├── run-lulu.sh             # 자동 재시작 래퍼
├── .mcp-lulu.json          # MCP 서버 설정
├── .env                    # Discord 토큰 (gitignored)
├── channels/
│   ├── discord-channel.mjs # Discord MCP 서버 코어
│   └── lulu-discord.mjs    # Lulu 설정
├── hooks/
│   ├── session-start.sh    # SessionStart
│   ├── pre-compact.sh      # PreCompact
│   ├── post-compact.sh     # PostCompact
│   └── stop.sh             # Stop
└── .claude/
    └── memory/             # 도메인 지식
```

## 메모리 구조

```
~/Documents/Lulu_Memory/
├── session_notes/lulu/     # 세션 노트 (YYYY-MM-DD.md)
├── inbox/                  # Discord 첨부파일 다운로드
└── checkpoint.md           # 컴팩션 복구용
```

## 주요 기능

- **파일 분석**: 로컬 이미지(PNG/JPG), PDF, Excel, CSV 등 읽기 및 요약
- **Discord 통신**: DM 또는 지정 채널에서 대화
- **포트폴리오 지원**: 스펙 정리, Notion 페이지 작성 (Notion MCP 연동 시)
- **커리어 지원**: 은행/금융, 관광기획 분야 지식 기반 조언
