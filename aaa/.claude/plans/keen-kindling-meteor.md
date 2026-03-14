# 사내 전용 Claude Code 플러그인 생성 계획

## Context

현재 `agetns-utils` 레포에는 공개용 컴포넌트와 회사 전용 컴포넌트가 혼재되어 있다.
공개용은 `hardened-claude-code`(GitHub)에서 배포하고, 회사 전용 컴포넌트(Plane, Outline, Grafana 연동)는
사내 GitLab에서 Claude Code 플러그인 형태로 팀에 배포하려 한다.

**목표**: 사내 개발자들이 `claude plugin add` 또는 setup 스크립트로 간편하게 설치할 수 있는 단일 플러그인 패키지 생성

---

## 플러그인 구조 설계

### 대상 컴포넌트 (회사 전용)

| 타입 | 이름 | 설명 |
|------|------|------|
| MCP Server | `plane` | Plane 이슈 트래커 (danawa workspace) |
| MCP Server | `outline` | Outline 위키 (cowave.wiki) |
| MCP Server | `grafana` | Grafana 모니터링 (danuricorp) |
| Skill | `issue-tracker` | Plane 연동 워크플로우 |
| Skill | `document-lastest` | Outline 자동 문서화 |

### 디렉토리 구조

```
cowave-claude-plugin/
├── .claude-plugin/
│   └── plugin.json              # 플러그인 메타데이터
├── .mcp.json                    # MCP 서버 설정 (3개 번들)
├── skills/
│   ├── issue-tracker/
│   │   ├── SKILL.md             # 기존 issue-tracker 스킬 복사
│   │   ├── guide/
│   │   └── templates/
│   └── document-lastest/
│       ├── SKILL.md             # 기존 document-lastest 스킬 복사
│       ├── guide/
│       └── templates/
├── setup.sh                     # 설치 스크립트
├── README.md                    # 설치/설정 가이드
└── .env.example                 # 필요한 환경변수 템플릿
```

---

## 상세 구현 단계

### Step 1: 플러그인 디렉토리 생성

`/Users/admin/project/agetns-utils` 내에 `cowave-claude-plugin/` 디렉토리 생성

### Step 2: plugin.json 작성

```json
{
  "name": "cowave-devtools",
  "description": "Cowave 사내 개발 도구 플러그인. Plane 이슈 트래커, Outline 위키, Grafana 모니터링 연동을 제공합니다.",
  "author": {
    "name": "Cowave",
    "email": "dev@cowave.kr"
  }
}
```

### Step 3: .mcp.json 작성

3개 MCP 서버를 번들링. API Key는 환경변수로 분리.

- 기존 `mcp/plane.json`, `mcp/outline.json`, `mcp/grafana.json` 내용을 하나의 `.mcp.json`으로 통합
- API Key 필드는 `${ENV_VAR}` 형태로 참조
- URL은 사내 인프라 주소 하드코딩 (사내 전용이므로)

### Step 4: 기존 스킬 복사 및 조정

- `skills/issue-tracker/` → 플러그인 내 `skills/issue-tracker/`로 복사
- `skills/document-lastest/` → 플러그인 내 `skills/document-lastest/`로 복사
- SKILL.md의 `requires_mcp` 참조가 플러그인 내 MCP와 일치하는지 확인

### Step 5: setup.sh 설치 스크립트 작성

사내 GitLab에서 직접 설치하는 스크립트:

```bash
#!/bin/bash
# 1. GitLab에서 플러그인 클론
# 2. ~/.claude/plugins/marketplaces/cowave-plugins/ 에 배치
# 3. known_marketplaces.json에 등록
# 4. installed_plugins.json에 플러그인 등록
# 5. 환경변수 설정 안내
```

Claude Code의 마켓플레이스는 기본적으로 GitHub 소스를 지원하나,
사내 GitLab의 경우 수동 클론 + JSON 등록 방식으로 동일하게 동작시킬 수 있다.

### Step 6: .env.example 및 README.md

- 필요한 환경변수 목록 (PLANE_API_KEY, OUTLINE_API_TOKEN, GRAFANA_TOKEN 등)
- 설치 방법, 활성화 방법, 팀원 온보딩 가이드

---

## 수정 대상 파일 요약

| 파일 | 작업 |
|------|------|
| `cowave-claude-plugin/.claude-plugin/plugin.json` | 신규 생성 |
| `cowave-claude-plugin/.mcp.json` | 신규 생성 (기존 mcp/*.json 3개 통합) |
| `cowave-claude-plugin/skills/issue-tracker/` | 기존 스킬 복사 |
| `cowave-claude-plugin/skills/document-lastest/` | 기존 스킬 복사 |
| `cowave-claude-plugin/setup.sh` | 신규 생성 |
| `cowave-claude-plugin/.env.example` | 신규 생성 |
| `cowave-claude-plugin/README.md` | 신규 생성 |

---

## 참조할 기존 파일

- `mcp/plane.json` — Plane MCP 설정
- `mcp/outline.json` — Outline MCP 설정
- `mcp/grafana.json` — Grafana MCP 설정
- `skills/issue-tracker/SKILL.md` — 이슈 트래커 스킬 정의
- `skills/document-lastest/SKILL.md` — 문서 최신화 스킬 정의
- `~/.claude/plugins/known_marketplaces.json` — 마켓플레이스 등록 형식
- `~/.claude/plugins/installed_plugins.json` — 플러그인 설치 레지스트리 형식
- `~/.claude/plugins/cache/claude-plugins-official/serena/` — MCP 번들 플러그인 참조 구조

---

## 검증 방법

1. **구조 검증**: `cowave-claude-plugin/` 디렉토리가 표준 플러그인 형식을 따르는지 확인
2. **setup.sh 실행**: 로컬에서 스크립트 실행하여 플러그인이 `~/.claude/plugins/`에 올바르게 등록되는지 확인
3. **활성화 확인**: `settings.json`에 `"cowave-devtools@cowave-plugins": true` 추가 후 Claude Code 재시작
4. **MCP 연결 확인**: Claude Code에서 Plane/Outline/Grafana MCP 도구가 노출되는지 확인
5. **스킬/커맨드 확인**: `/issue-tracker`, `/document-lastest` 커맨드가 인식되는지 확인
