---
name: monorepo-init
description: "모노레포 프로젝트 초기화 및 계층적 CLAUDE.md 생성"
metadata:
  version: 1.0.0
  category: utility
  domain: project-setup
triggers:
  - "monorepo init"
  - "모노레포 초기화"
  - "워크스페이스 컨텍스트 생성"
  - "서비스별 CLAUDE.md"
---

# Monorepo Init - 계층적 프로젝트 컨텍스트 생성

## Overview
모노레포 프로젝트를 감지하고, 루트와 각 서비스에 계층적 CLAUDE.md를 생성합니다.
AGENTS.md가 필요한 경우 `agents-md-copy` 스킬을 실행하여 복사합니다.

## Monorepo Detection Criteria

다음 조건 중 하나라도 충족 시 모노레포로 판단:

| 파일/설정 | 도구 | 설명 |
|-----------|------|------|
| `pnpm-workspace.yaml` | pnpm | pnpm 워크스페이스 설정 |
| `package.json` → `workspaces` | npm/yarn | 워크스페이스 필드 존재 |
| `lerna.json` | Lerna | Lerna 모노레포 설정 |
| `nx.json` | Nx | Nx 워크스페이스 설정 |
| `turbo.json` | Turborepo | Turborepo 설정 |
| 복수의 `package.json`/`go.mod`/`pom.xml` | - | 서브디렉토리에 독립 프로젝트 |

## Behavioral Flow

### Phase 1: Workspace Tool Detection
```
1. pnpm-workspace.yaml 확인 → pnpm workspaces
2. package.json workspaces 필드 확인 → npm/yarn workspaces
3. lerna.json 확인 → Lerna
4. nx.json 확인 → Nx
5. turbo.json 확인 → Turborepo
6. 복수 설정 파일 감지 → Generic monorepo
```

### Phase 2: Service Discovery
워크스페이스 설정에서 글로브 패턴 파싱:

```yaml
# pnpm-workspace.yaml 예시
packages:
  - 'packages/*'
  - 'apps/*'
  - 'libs/*'
```

```json
// package.json 예시
{
  "workspaces": ["packages/*", "apps/*"]
}
```

각 서비스 디렉토리에서:
- `package.json` → name, description 추출
- `README.md` → 설명 참고
- 기술 스택 감지 (기존 init 로직 활용)

### Phase 3: Root CLAUDE.md Generation

루트 디렉토리에 생성할 템플릿:

```markdown
# Project: {{project-name}} (Monorepo)

## Overview
- **Type**: Monorepo
- **Workspace Tool**: {{pnpm|yarn|lerna|nx|turbo}}
- **Services Count**: {{count}}

## Services

| Service | Path | Description |
|---------|------|-------------|
{{#each services}}
| {{name}} | [{{path}}](./{{path}}/CLAUDE.md) | {{description}} |
{{/each}}

## Service Selection Guide
작업 유형에 따른 서비스 선택 가이드:

{{#each service-guides}}
- **{{work-type}}**: `{{service-path}}` 참고
{{/each}}

## Global Commands
```bash
{{#if pnpm}}
pnpm install          # 전체 의존성 설치
pnpm build            # 전체 빌드
pnpm test             # 전체 테스트
pnpm lint             # 전체 린트
{{/if}}
{{#if yarn}}
yarn install          # 전체 의존성 설치
yarn build            # 전체 빌드
yarn test             # 전체 테스트
{{/if}}
{{#if npm}}
npm install           # 전체 의존성 설치
npm run build         # 전체 빌드
npm test              # 전체 테스트
{{/if}}
{{#if nx}}
nx run-many --target=build    # 전체 빌드
nx run-many --target=test     # 전체 테스트
nx affected --target=build    # 변경된 프로젝트만 빌드
{{/if}}
{{#if turbo}}
turbo build           # 전체 빌드
turbo test            # 전체 테스트
turbo lint            # 전체 린트
{{/if}}
```

## Workspace Structure
```
{{directory-tree}}
```

## Cross-Service Dependencies
{{dependency-graph-or-description}}

## Development Workflow
1. 루트에서 `{{install-command}}` 실행
2. 작업할 서비스 디렉토리의 CLAUDE.md 참고
3. 서비스별 명령어로 개발/테스트
4. 루트에서 전체 빌드/테스트로 통합 검증
```

### Phase 4: Service CLAUDE.md Generation

각 서비스 디렉토리에 개별 CLAUDE.md 생성:
- 기존 `/init` 명령의 단일 프로젝트 로직 재사용
- 해당 서비스의 기술 스택, 명령어, 아키텍처 포함
- 루트로의 네비게이션 링크 추가

서비스 CLAUDE.md 헤더:
```markdown
# Service: {{service-name}}
> Part of [{{monorepo-name}}](../../CLAUDE.md) monorepo

## Overview
...
```

### Phase 5: Summary Output

```markdown
## 모노레포 초기화 완료

### 감지된 워크스페이스
- **Tool**: {{workspace-tool}}
- **Services**: {{count}}개

### 생성된 파일
- `/CLAUDE.md` (루트)
{{#each services}}
- `/{{path}}/CLAUDE.md`
{{/each}}

### 루트 컨텍스트
- {{count}}개 서비스 링크 포함
- 서비스 선택 가이드 작성

### 다음 단계
1. 생성된 CLAUDE.md 파일들 검토
2. 필요시 서비스별 설명 보완
3. AGENTS.md 필요시 `agents-md-copy` 스킬 실행
```

## Tool Coordination

- **Glob**: 워크스페이스 패턴 매칭, 서비스 디렉토리 탐색
- **Grep**: 설정 파일 패턴 검색 (workspaces 필드 등)
- **Read**: 설정 파일 내용 분석 (pnpm-workspace.yaml, package.json 등)
- **Bash**: 패키지 매니저 쿼리, 디렉토리 트리 생성
- **Write**: CLAUDE.md 파일 생성

## Examples

### pnpm Workspace 프로젝트
```
/init
```
감지: `pnpm-workspace.yaml` 존재

결과:
```
monorepo-root/
├── CLAUDE.md              ← 4개 서비스 링크, 글로벌 명령어
├── packages/
│   ├── api/CLAUDE.md      ← Express + TypeScript
│   ├── web/CLAUDE.md      ← Next.js
│   └── shared/CLAUDE.md   ← TypeScript 유틸리티
└── apps/
    └── admin/CLAUDE.md    ← React + Vite
```

### Turborepo 프로젝트
```
/init
```
감지: `turbo.json` + `package.json` workspaces

결과: 루트에 turbo 명령어 포함, 각 앱/패키지에 개별 컨텍스트

### Nx 프로젝트
```
/init
```
감지: `nx.json`

결과: nx 명령어 및 affected 빌드 가이드 포함

## Boundaries

**Will:**
- 워크스페이스 설정 파일 자동 감지
- 루트 및 각 서비스에 CLAUDE.md 생성
- 서비스 간 네비게이션 링크 제공
- 글로벌/서비스별 명령어 분리

**Will Not:**
- AGENTS.md 직접 생성 (agents-md-copy 스킬 사용)
- 기존 CLAUDE.md 무단 덮어쓰기 (확인 프롬프트 표시)
- 소스 코드 또는 설정 파일 수정
- 의존성 설치 또는 빌드 실행

## Integration with init Command

이 스킬은 `/init` 커맨드의 모노레포 분기로 동작:
1. `/init` 실행 시 모노레포 감지 조건 확인
2. 모노레포 → 이 스킬 로직 실행
3. 단일 프로젝트 → 기존 init 로직 실행
