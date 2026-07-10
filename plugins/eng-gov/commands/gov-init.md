---
name: gov-init
description: |
  eng-gov 하네스 진입점 — 스택을 감지(command -v로 도구, 설정/빌드 파일로 언어)하고 .planning/gov/ 상태 디렉토리와 docs/decisions/ ADR 베이스라인을 스캐폴딩한 뒤, 적용 가능한 결정론 게이트를 gates.json에 등록한다(미설치 도구는 enabled:false+reason으로 명시적 skip). 등록 후 게이트를 1회 시운전해 red를 허용 보고한다. gates.json의 plugin_root 절대경로는 플러그인 캐시 갱신 시 stale이 되므로, stale 감지 시 /gov-init 재실행이 규약이다. Use when 레포에 개발 거버넌스 하네스를 처음 도입하거나, 도구 설치 후 게이트를 재등록하거나, gates.json이 stale일 때.
  Entry point of the eng-gov harness: detects the stack (tools via command -v, language via config/build files), scaffolds the .planning/gov/ state dir and docs/decisions/ ADR baseline, registers applicable deterministic gates in gates.json (missing tools become enabled:false+reason), then trial-runs the gates once (red allowed, reported). gates.json's absolute plugin_root goes stale on plugin-cache refresh, so re-running /gov-init is the fix. Use when: first adopting the harness, re-registering gates after installing tools, or when gates.json is stale.
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /gov-init — 개발 거버넌스 하네스 초기화

레포의 스택·도구를 감지해 `.planning/gov/` + `docs/decisions/` 베이스라인을 스캐폴딩하고, 적용 게이트를 `gates.json`에 등록한다. 도메인 형식·게이트 계약은 `governance-templates`·`supply-chain-guide`·`fitness-function-guide` 스킬이 정본이며, 이 커맨드는 감지·스캐폴딩·등록만 수행한다.

## Triggers
- 기존/신규 레포에 ADR·변경증적·위협모델·공급망 게이트를 처음 도입할 때
- gitleaks·syft·grype·conftest 등을 설치한 뒤 게이트를 재등록할 때
- 플러그인 캐시 갱신으로 `gates.json`의 `plugin_root`가 stale일 때(게이트 실행 실패 → 재초기화)

## Usage
```
/gov-init [옵션]
Options:
  --with <gate,...>   특정 게이트만 등록 (기본: 감지 결과 전부)
  --adr-only          ADR 베이스라인만 스캐폴딩(게이트 등록 생략)
```

## Behavioral Flow

### Phase 1: 스택·도구 감지
1. **언어/설정 감지**: `.dependency-cruiser.*`(JS/TS), `.importlinter`/`pyproject.toml`(Python), `build.gradle*`/`pom.xml`(JVM), `Dockerfile*`·`k8s/`·`compose*`(IaC) 존재 여부를 Glob으로 확인.
2. **도구 감지**: `command -v` 로 gitleaks·syft·grype·conftest·threagile·depcruise·lint-imports 가용성 판정. 미설치 도구는 등록 시 `enabled:false`.

### Phase 2: 베이스라인 스캐폴딩
1. `docs/decisions/` 생성 + `0000-record-architecture-decisions.md`(MADR 템플릿 — governance-templates 참조, status: accepted)로 첫 ADR을 심는다.
2. `.planning/gov/` 하위 생성: `gov-master.json`(스택·초기화 시각·adr_dir), `slo/`·`threat/`·`policy/`·`change/` 디렉토리, 빈 `audit-log.jsonl`.
3. `gov-master.json` 스키마: `{"version":1,"status":"active","initialized_at":<epoch>,"stack":{...},"adr_dir":"docs/decisions","last_audit_at":0}`.

### Phase 3: 게이트 등록 (gates.json)
1. `plugin_root`를 `${CLAUDE_PLUGIN_ROOT}` **절대경로**로 기록한다.
2. 감지 결과로 각 게이트 항목을 등록: `{"id","cmd":"bash <root>/hooks/gates/gate-x.sh","enabled":<bool>,"reason":"..."}`.
   - 도구 불요 게이트(gate-adr)는 항상 `enabled:true, reason:"always"`.
   - 도구 필요 게이트는 도구 존재 시 `enabled:true`, 부재 시 `enabled:false, reason:"<도구> 미설치 — 설치 후 /gov-init 재실행"`.
3. gate-fitness는 설정 파일이 있을 때만 `enabled:true`(공허 통과 회피).

### Phase 4: 시운전
1. `run-registered.sh`를 1회 실행 — 신규 레포는 red가 정상(증적 미작성). red를 **차단이 아니라 현황 보고**로 제시한다.
2. 요약 보고: 등록 게이트 n종(enabled/disabled)·미설치 도구·다음 단계(`/gov-adr`·`/gov-slo`·`/gov-threat`).

## Tool Coordination
- **Bash**: `command -v` 도구 감지, `.planning/gov/`·`docs/decisions/` 생성, `run-registered.sh` 시운전
- **Glob/Read**: 스택 설정·빌드 파일 감지, 기존 `.planning/gov/` 존재 확인(있으면 재등록 모드)
- **Skill**: `governance-templates`(ADR 템플릿·경로 계약), `supply-chain-guide`(도구 규약)

## Boundaries

**Will:** 스택·도구 감지, `.planning/gov/`+`docs/decisions/` 스캐폴딩, gates.json 등록(미설치=enabled:false), 시운전 현황 보고.
**Will Not:**
- 도구 미설치를 skip green으로 처리(등록 게이트 부재는 fail-closed — enabled:false로 명시적 skip만 허용)
- 게이트 red를 이유로 초기화 중단(신규 레포 red는 정상)
- ADR 내용 작성(→ `/gov-adr`)·SLO/위협모델 작성(→ `/gov-slo`·`/gov-threat`)
