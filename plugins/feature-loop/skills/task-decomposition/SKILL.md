---
name: task-decomposition
description: "feature-loop 작업 분해 표준 — 자연어 기능 요청을 코드베이스 분석 기반 tasks.json으로 분해하는 규약. 수직 슬라이스(독립 테스트·커밋 가능 최소 단위) 사이징, Given-When-Then 검증형 AC 작성법(feature-verifier가 반증 가능한 문장), 회귀 보존 AC(기존 동작 유지 명시) 의무, tasks.json 스키마와 jq 검증식, gate-tasks.sh 통과 기준(id ^T-[0-9]{2}$·개수 2~10·전건 passes:false), 1 task=1 루프 반복 크기 가이드. task-planner가 Stage B에서 tasks.json을 작성·수정할 때, feature-verifier가 분해를 반증할 때, gate-tasks.sh 실패를 진단할 때 참조."
---

# Task Decomposition Standard (브라운필드)

feature-loop 하네스 Stage B의 작업 분해 표준. 자연어 기능 요청을 **기존 코드베이스 위에 정착하는** `tasks.json`으로 변환하는 규약을 정의한다. MVP의 prd-authoring이 "빈 화면에서 스토리 생성"이라면, 이 표준은 **"기존 코드의 컨벤션·구조·테스트를 분석한 뒤 그 위에 task를 얹는 것"**이다.

## When to Apply

- task-planner가 Stage B에서 `tasks.json`을 작성·수정할 때
- feature-verifier가 분해를 반증할 때(범위 비대·검증 불가 AC·회귀 보존 AC 누락)
- `gate-tasks.sh` 실패를 진단할 때
- 루프 중 BLOCKED task의 재분해가 필요할 때

## 분해 전: 코드베이스 분석 (필수)

분해는 탐색 위에서만 한다. 다음을 먼저 답한다:

1. **정착 지점** — 이 요청이 기존 코드의 어디에 얹히는가? (진입점·도메인 모델·관련 모듈)
2. **재사용 자산** — 어떤 기존 함수·패턴·픽스처를 재사용하는가?
3. **컨벤션** — 따라야 할 네이밍·레이어·에러 처리 패턴은?
4. **회귀 위험** — 어떤 기존 동작을 건드리면 회귀가 나는가? (이게 회귀 보존 AC의 근거)

## 수직 슬라이스 사이징 — 1 task = 1 반복

각 task는 **독립적으로 테스트 작성→구현→게이트 그린→커밋**이 가능해야 한다.

```text
BAD (1반복 초과 — 루프가 한 번에 못 끝냄):
{ "id": "T-01", "title": "회원 관리 전체 — 가입+로그인+프로필+탈퇴" }

GOOD (1 task = 1 반복으로 분해, 선행 의존을 연번에 반영):
{ "id": "T-01", "title": "회원가입 이메일 형식 검증" }
{ "id": "T-02", "title": "회원가입 비밀번호 강도 검증" }
{ "id": "T-03", "title": "중복 이메일 가입 거부" }
```

- 한 task에 동사가 3개 이상 묶이면 분할
- 선행 의존이 있으면 id 연번에 반영(T-01 모델 → T-02 그 위 API)
- 횡단 범위가 넓은 task(여러 모듈 동시 수정)는 회귀 위험이 크므로 더 잘게

## AC 작성 — Given-When-Then (반증 가능 + 회귀 보존)

각 AC는 feature-verifier가 Bash로 반증 시도할 수 있는 **관찰 가능한 조건-행위-결과**여야 한다.

```text
BAD (반증 불가):
- 검증 로직이 잘 동작한다              ← 측정 기준 없음
- 성능에 문제 없다                     ← "문제"가 모호
- 기존 기능에 영향 없다                ← "영향"이 모호 (회귀 게이트가 별도로 잡지만, AC로도 명시)

GOOD (Given-When-Then, 반증 가능):
- Given 이메일이 빈 문자열일 때 When 회원가입을 요청하면
  Then 400과 "이메일은 필수입니다" 메시지를 반환한다
- Given 이메일 형식이 잘못됐을 때 When 가입을 요청하면
  Then 422와 형식 오류 메시지를 반환한다
```

### 회귀 보존 AC (브라운필드 필수)

기존 동작을 **바꾸거나 그 경로를 지나는** task는 "기존이 동일하게 동작한다"를 AC로 명시한다. 이것이 단위 수준의 회귀 방어선이며, baseline 회귀 게이트(②ᴿ)의 task 대응물이다.

```text
GOOD (회귀 보존 AC 포함):
- Given 기존 유효한 회원가입 요청일 때 When 검증 로직 추가 후 동일 요청하면
  Then 기존과 동일하게 201로 생성된다
```

> 회귀 보존 AC가 이미 **기존 테스트로 커버**되는 경우(예: 기존 SignupTest가 정상 경로를 검증), 신규 테스트를 중복 작성하지 않는다 — 그 기존 테스트가 baseline에 포함되어 회귀를 잡는다. AC에는 "기존 테스트 X가 green 유지"로 명시한다.

## tasks.json 스키마

```json
{
  "tasks": [
    {
      "id": "T-01",
      "title": "회원가입 이메일 형식 검증 추가",
      "acceptance": [
        "Given 이메일이 빈 문자열일 때 When 가입을 요청하면 Then 400과 오류 메시지를 반환한다",
        "Given 기존 유효 요청일 때 When 검증 추가 후 요청하면 Then 기존과 동일하게 201로 생성된다"
      ],
      "passes": false,
      "notes": "영향: UserController.signup, UserService.validate / 재사용: 기존 ValidationException"
    }
  ]
}
```

| 필드 | 규칙 |
|------|------|
| `id` | `^T-[0-9]{2}$` (T-01부터 2자리 연번), 중복 금지 |
| `title` | 비어있지 않은 문자열 |
| `acceptance` | 비어있지 않은 문자열 1개 이상의 배열, Given-When-Then |
| `passes` | 초기 전건 `false`. **true 마킹은 feature-verifier 마커 선행 후 메인 세션만**(tasks-guard 차단) |
| `notes` | (선택, 게이트 비검사) 영향 파일·재사용 지점 — builder 인계용 |

## gate-tasks.sh 검증식 (jq)

`hooks/gates/gate-tasks.sh`가 검사하는 항목:

```bash
# tasks 배열 존재
jq -e '.tasks | type == "array"' tasks.json
# 필수 필드
jq -e '[.tasks[] | has("id") and has("title") and has("acceptance") and has("passes")] | all' tasks.json
# id 형식
jq -e '[.tasks[].id | test("^T-[0-9]{2}$")] | all' tasks.json
# id 중복 금지
jq -e '(.tasks | map(.id) | length) == (.tasks | map(.id) | unique | length)' tasks.json
# acceptance 비어있지 않은 문자열 배열
jq -e '[.tasks[] | (.acceptance // []) | (type=="array") and (length>0) and (all(.[]?; (type=="string") and (length>0)))] | all' tasks.json
# task 수 2~FLOOP_TASKS_MAX(기본 10)
# --initial 시 passes 전건 false
jq -e '[.tasks[].passes == false] | all' tasks.json
```

## 스코프 가이드

- **task 수 2~10**: 1개면 루프가 불필요(직접 수행), 10 초과면 한 세션 컨텍스트 비대 — 요청을 더 작은 단위로 나누거나 여러 `/floop-new`로 분리
- **2주 룰 대신 "한 세션 룰"**: 브라운필드는 보통 한 기능 요청이므로, 전체 task가 한두 세션 루프에 끝날 분량인지 본다. 초과 시 가장 의존성 낮은 task를 후속으로 분리
- **건드리지 않을 것 명시**: 분해 리포트의 "영향 범위" 표에 횡단하지 않는 경계를 적어 회귀 표면을 줄인다

## BAD / GOOD 요약

```text
BAD 분해:
- T-01 "전체 기능 구현"        ← 1반복 초과, 회귀 표면 거대
- AC "잘 동작한다"              ← 반증 불가
- 회귀 보존 AC 없음            ← 기존 깨져도 단위 수준에서 못 잡음

GOOD 분해:
- 수직 슬라이스 3~5개, 각 1반복 크기
- 각 AC Given-When-Then, 변경 task에 회귀 보존 AC 포함
- notes에 영향 파일·재사용 지점 명시
```
