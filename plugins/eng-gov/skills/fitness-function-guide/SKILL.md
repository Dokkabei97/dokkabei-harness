---
name: fitness-function-guide
description: |
  eng-gov 하네스의 아키텍처 피트니스 함수 가이드 — 스택별 도구 선택(dependency-cruiser=JS/TS, import-linter=Python, ArchUnit=JVM)과 ADR의 결정을 강제 가능한 자동 검사로 변환하는 패턴집을 제공한다. gate-fitness.sh는 설정 파일(.dependency-cruiser.*·.importlinter)의 존재를 감지해 도구를 실행하고 exit를 전파하며, 설정 0건이면 공허 통과한다 — 따라서 '결정을 설정으로 인코딩'하는 것이 게이트를 의미 있게 만든다. "domain은 infra를 import하지 않는다" 같은 ADR 결정을 forbidden 룰/contract로 옮기는 구체 레시피를 담는다. Use when /gov-adr 결정을 자동 검사로 변환하거나, gate-fitness 대상 설정을 스택에 맞게 작성·튜닝할 때.
  Architecture fitness-function guide for eng-gov: stack tool selection (dependency-cruiser for JS/TS, import-linter for Python, ArchUnit for JVM) and a catalog for converting ADR decisions into enforceable automated checks. gate-fitness.sh detects config files, runs the tool, and propagates exit; zero configs void-pass — so encoding decisions as config is what makes the gate meaningful. Use when: converting a /gov-adr decision into an automated check, or authoring/tuning gate-fitness config for a stack.
metadata:
  version: 1.0.0
  category: governance
---

# Fitness Function Guide

**아키텍처 피트니스 함수** = 아키텍처 특성(의존 방향·레이어 경계·모듈 결합)을 지속적으로 검증하는 자동 테스트. eng-gov에서는 ADR이 내린 결정을 이 함수로 인코딩해 `gate-fitness.sh`가 매 루프·릴리즈에 결정론 집행하게 한다.

핵심 명제: **선언된 결정(ADR)은 강제되지 않으면 부식한다.** 강제 가능한 결정은 반드시 설정으로 인코딩한다.

## gate-fitness.sh 계약 (요약)

| 상황 | 동작 |
|------|------|
| 설정 0건 | "검사 대상 없음" 공허 통과 exit 0 |
| 설정 존재 + 도구 부재 | fail-closed exit 1 (설치 안내) |
| 설정 존재 + 도구 실행 | 도구 exit 그대로 전파(위반 시 비정상 exit) |
| ArchUnit 참조(build 파일) | 안내 경고만 — 판정은 테스트 러너(gate-cmd) 몫 |

도구 경로는 `DEPCRUISE_BIN`·`LINT_IMPORTS_BIN` env로 오버라이드(기본값 `depcruise`·`lint-imports`).

## 스택별 도구 선택

| 스택 | 도구 | 설정 파일 | 실행 |
|------|------|-----------|------|
| JS/TS (Node) | dependency-cruiser | `.dependency-cruiser.{js,cjs,mjs,json}` | `depcruise --validate` |
| Python | import-linter | `.importlinter` (또는 setup.cfg/pyproject) | `lint-imports` |
| JVM (Kotlin/Java) | ArchUnit | 테스트 소스 내 `@ArchTest` | 테스트 러너(gate-cmd) — gate-fitness는 안내만 |

> JVM은 ArchUnit이 JUnit 테스트로 실행되므로 별도 CLI가 없다. gate-fitness는 build 파일의 archunit 참조를 감지해 "테스트 러너에서 실행하라"고 안내하고 판정하지 않는다 — 아키텍처 규칙은 프로젝트 gate-cmd(`./gradlew test`)에 포함시킨다.

## ADR → 검사 변환 패턴집

### 패턴 1: 레이어 의존 방향 (헥사고날/클린)

ADR: "domain은 어떤 바깥 레이어(infra·web)도 import하지 않는다."

**dependency-cruiser** (`.dependency-cruiser.js`):
```js
module.exports = { forbidden: [{
  name: 'domain-no-outward-deps',
  severity: 'error',
  from: { path: '^src/domain' },
  to:   { path: '^src/(infra|web)' }
}]};
```

**import-linter** (`.importlinter`):
```ini
[importlinter]
root_package = myapp
[importlinter:contract:layers]
name = Clean layers
type = layers
layers =
    web
    application
    domain
```

### 패턴 2: 모듈 간 금지 의존

ADR: "billing 모듈은 auth 내부 구현에 직접 의존하지 않고 공개 API만 사용."
→ dependency-cruiser forbidden 룰로 `from: billing`, `to: auth/internal` 차단.

### 패턴 3: 순환 의존 금지

ADR: "패키지 순환 참조 금지."
→ dependency-cruiser `no-circular` 룰(`to.circular: true`, severity error) / import-linter `type = independence`.

### 패턴 4: 도입 금지 라이브러리

ADR: "새 코드에서 moment.js 대신 date-fns 사용."
→ dependency-cruiser `to.path: 'node_modules/moment'` forbidden. (라이선스 차원이면 gate-supply-chain denylist로.)

## 변환 불가한 결정

사회적 규약(코드 리뷰 문화·네이밍 관습)처럼 정적 분석으로 강제 불가한 결정은 그 사실을 ADR에 명시한다 → `adr-checker`가 "선언뿐(강제 안 됨)"으로 FIX 권고하되 BLOCK하지 않는다. 강제 가능성은 결정의 등급이 아니라 성격의 문제다.

## 경계

- **일반 구조 품질 리뷰**(결합도·복잡도 점수) → `analyze:arch-review` 위임. 이 스킬은 **명시된 결정의 강제**만 다룬다.
- gate-fitness는 도구 exit를 전파할 뿐 룰을 해석하지 않는다 — 룰의 단일 진실 원천은 프로젝트의 설정 파일이다.
