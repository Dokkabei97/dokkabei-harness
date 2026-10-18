---
name: gov-change
description: |
  변경 증적 번들링 커맨드 — git diff 통계를 bash로 선계산해 change-risk-classifier(maker)에 입력하고, 변경을 standard/normal/high로 등급화한 뒤 change/<sha>/evidence.json(SHA·author≠approver·게이트 결과)을 조립하고 gate-change-evidence.sh로 결정론 판정한다. 개인정보·인증·결제·인프라 터치나 500+ 라인은 high 트리거이며 high는 gate-secrets·gate-supply-chain 실행 기록을 요구한다. floop/mvp 루프 완료 시점이면 loop_artifacts를 tasks.json·baseline.json에서 채워 '루프 산출물=감사 증적'을 연결한다. 법 진단은 legal 위임. Use when 릴리즈/머지 전 변경 증적을 만들거나 루프 완료 산출물을 감사 증적으로 물화할 때.
  Change-evidence bundling command: bash-precomputes git diff stats, feeds change-risk-classifier (maker) to grade the change standard/normal/high, assembles change/<sha>/evidence.json (SHA, author≠approver, gate results), and judges it via gate-change-evidence.sh. PII/auth/payment/infra touches or 500+ lines force high, which requires gate-secrets·gate-supply-chain records; at loop completion it fills loop_artifacts from tasks.json/baseline.json to link "loop output = audit evidence." Legal judgment is delegated to legal. Use when: producing change evidence before a release/merge or materializing loop output as audit evidence.
category: workflow
complexity: advanced
mcp-servers: []
personas: []
---

# /gov-change — 변경 증적 번들링

변경을 위험 등급화하고 감사 증적(`evidence.json`)으로 물화한다. 스키마·정책은 `governance-templates`(`references/change-policy-template.md`)가 정본. 등급 분류는 `change-risk-classifier` maker가 수행한다.

## Triggers
- 릴리즈·머지 전 SOC 2 CC8.1 / ISO 27001:2022 A.8.32 변경 증적이 필요할 때
- floop/mvp 루프 완료 시점에 산출물을 감사 증적으로 남길 때
- "변경 증적 만들어줘", "이 변경 위험 등급", "릴리즈 증빙" 요청

## Usage
```
/gov-change [옵션]
Options:
  --base <ref>        diff 기준(기본 origin/main 또는 직전 태그)
  --approver <name>   승인자 지정(author와 상이해야 함 — 4-eyes)
```

## Behavioral Flow

### Phase 0: 사전 점검
- `.planning/gov/` 존재(없으면 `/gov-init`). git HEAD 확보. `author`는 git 커밋 작성자, `approver`는 옵션/사용자 입력.

### Phase 1: diff 통계 선계산 (bash)
1. `git diff --numstat <base>..HEAD`로 `files/insertions/deletions` 집계, 변경 파일 목록 수집.
2. 이 통계를 **classifier 입력으로 전달**한다(classifier는 diff를 다시 세지 않음).

### Phase 2: change-risk-classifier 등급화
1. `change-risk-classifier` 디스패치 — 선계산 통계 + 파일 경로로 standard/normal/high 판정.
2. 개인정보 신호(email·phone·ssn·resident·card 등) Grep 확인 → 터치 시 무조건 high. 인증·결제·인프라·500+라인도 high.
3. **법적 판단은 legal 위임** — risk_reasons에 "legal 확인 필요" 플래그만.

### Phase 3: 필수 게이트 실행 (high)
- high면 `gate-secrets.sh`·`gate-supply-chain.sh`를 실행하고 실제 exit를 evidence.gates[]에 기록(허위 0 금지). normal/standard는 등록된 코어 게이트 기록.

### Phase 4: evidence.json 조립
1. `.planning/gov/change/<HEAD-sha>/evidence.json` 작성(change-policy-template 스키마). `author != approver` 강제.
2. 루프 완료 시점이면 `loop_artifacts`를 `.planning/tasks.json`(또는 prd.json)·`.planning/baseline.json`에서 채운다.

### Phase 5: gate-change-evidence 판정
`bash ${CLAUDE_PLUGIN_ROOT}/hooks/gates/gate-change-evidence.sh` — sha 매칭·4-eyes·risk_tier enum·gates 전건 그린·high 필수 게이트 기록을 검사. 통과/실패 보고.

## Tool Coordination
- **Bash**: `git diff --numstat` 선계산, `gate-secrets`/`gate-supply-chain`/`gate-change-evidence` 실행
- **Task**: `change-risk-classifier` 디스패치
- **Grep**: 개인정보 신호 확인
- **Write**: `evidence.json` 조립

## Boundaries

**Will:** diff 통계 선계산, 위험 등급화, evidence.json 조립(4-eyes·high 필수 게이트), 루프 산출물 조인, gate 판정.
**Will Not:**
- 개인정보 영향평가·규제 신고 의무 판단(→ legal 위임, 플래그만)
- 미실행 게이트를 evidence에 그린으로 위조(실측만 기록)
- author==approver 자기 승인 통과
