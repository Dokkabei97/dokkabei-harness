---
name: review-mr
description: "GitLab Merge Request 코드 리뷰. MR diff를 분석하여 버그, 보안 취약점, 로직 오류를 탐지하고 MR에 리뷰 코멘트를 작성합니다."
category: review
complexity: standard
mcp-servers: []
personas: []
---

# /review-mr - GitLab Merge Request Code Review

## Triggers
- GitLab Merge Request에 대한 코드 리뷰가 필요할 때
- MR을 머지하기 전 자동화된 코드 검토가 필요할 때
- 보안 취약점, 로직 오류, 엣지케이스를 사전에 탐지하고 싶을 때
- 팀원의 MR을 리뷰하면서 AI 보조가 필요할 때
- CI/CD 파이프라인의 리뷰 게이트로 활용할 때

## Usage
```
/review-mr [mr_number|mr_url]
```
- `mr_number`: MR 번호 (예: `42`)
- `mr_url`: MR URL (예: `https://gitlab.com/group/project/-/merge_requests/42`)
- 인자 없이 실행하면 현재 브랜치의 MR을 자동 감지합니다

## Behavioral Flow

### Phase 1: MR 정보 수집
1. **MR 식별**: 인자로 전달된 MR 번호/URL 또는 현재 브랜치에서 자동 감지
   ```bash
   # 현재 브랜치의 MR 자동 감지
   glab mr view --web=false

   # 특정 MR 번호로 조회
   glab mr view <mr_number>
   ```

2. **MR 메타데이터 수집**: 제목, 설명, 라벨, 대상 브랜치, 작성자 정보 확인
   ```bash
   glab mr view <mr_number> --output json
   ```

3. **Diff 가져오기**: MR의 전체 변경 사항 수집
   ```bash
   # MR diff 가져오기
   glab mr diff <mr_number>
   ```

4. **MR 코멘트/토론 확인**: 기존 리뷰 컨텍스트 파악
   ```bash
   glab mr note list <mr_number>
   ```

### Phase 2: 변경 파일 분석 및 사전 평가
1. **파일 분류**: 변경된 파일을 유형별로 분류
   - 소스 코드 (비즈니스 로직)
   - 테스트 코드
   - 설정/인프라 파일
   - 빌드 파일 (build.gradle.kts, requirements.txt, package.json)
   - 문서/기타

2. **영향도 평가**: 각 파일의 변경 규모와 중요도 판단
   - 추가/삭제/수정 라인 수
   - 핵심 비즈니스 로직 변경 여부
   - 공개 API 변경 여부

3. **Change Sizing 사전 경고**: MR 크기가 적절한지 판단
   | 변경 규모 | 판정 | 대응 |
   |-----------|------|------|
   | ~100줄 | Good | 한 번에 리뷰 가능 |
   | ~300줄 | Acceptable | 단일 논리적 변경이면 OK |
   | ~1000줄+ | Too Large | 분할 권고 |

   **분할이 필요한 경우 제안할 전략:**
   - **Stack**: 순차적 의존성이 있는 변경 → 의존성 순서대로 분할
   - **By file group**: 횡단 관심사 → 파일 그룹별 분할
   - **Horizontal**: 레이어드 아키텍처 → 계층별 분할
   - **Vertical**: 기능 단위 → 기능별 분할

   > **리팩토링과 기능 추가가 섞여 있으면 반드시 분할을 권고한다.**

4. **Dependency Discipline**: 빌드 파일 변경이 감지되면 다음 5가지를 확인
   - 기존 스택으로 해결 가능한가?
   - 의존성의 크기와 번들 영향은?
   - 활발히 유지보수되고 있는가? (마지막 커밋, 오픈 이슈 수)
   - 알려진 취약점이 있는가?
   - 라이선스가 프로젝트와 호환되는가?

### Phase 3: 코드 분석 (Tests First)

> **테스트를 먼저 리뷰한다.** 테스트는 변경의 의도와 커버리지를 드러낸다. 구현을 읽기 전에 테스트를 먼저 파악해야 "이 변경이 무엇을 하려는 것인지"를 정확히 이해할 수 있다.

#### 3-A. Test (먼저 리뷰)
- 변경된 로직에 대한 테스트가 존재하는가?
- 테스트가 **동작(behavior)**을 검증하는가, 구현 세부사항을 검증하는가?
- 엣지케이스가 커버되는가?
- 버그 수정이라면 재현 테스트(regression test)가 포함되어 있는가?
- 테스트가 회귀를 감지할 수 있는가? (코드가 변경되었을 때 테스트가 깨지는가?)

#### 3-B. Security
- SQL Injection, XSS, CSRF 등 OWASP Top 10 취약점
- 하드코딩된 비밀키/토큰/비밀번호
- 안전하지 않은 역직렬화
- 인증/인가 우회 가능성

#### 3-C. Logic
- 잠재적 버그 (null 참조, 범위 오류, off-by-one)
- 엣지케이스 미처리
- 레이스 컨디션, 리소스 누수
- 에러 핸들링 누락 또는 부적절한 처리

#### 3-D. Style
- 코딩 컨벤션 위반, 네이밍 일관성
- 중복 코드, 과도한 복잡도
- 매직 넘버/스트링
- 추상화가 복잡도를 정당화하는가? (단 하나의 구현만 있는 인터페이스 등)
- Dead code 아티팩트: no-op 변수, 하위호환 shim, `// removed` 주석

### Phase 4: 심각도 분류
각 발견 사항을 심각도별로 분류:

| 심각도 | 설명 | 머지 차단 |
|--------|------|-----------|
| **Critical** | 프로덕션 장애 또는 보안 사고 가능성 | Yes |
| **High** | 기능 오동작 또는 데이터 무결성 위험 | Yes |
| **Medium** | 유지보수성 저하 또는 잠재적 문제 | No |
| **Optional** | 선택적 개선 제안 — 적용 여부는 작성자 판단 | No |
| **Nit** | 스타일, 사소한 사항 | No |
| **FYI** | 참고 정보 — 변경 불필요, 관련 맥락 공유 | No |

> **접두사로 의도를 명확히 한다.** `Optional:` 또는 `FYI:`를 코멘트 앞에 붙여서 작성자가 모든 피드백을 의무 사항으로 오해하지 않도록 한다.

### Phase 5: Verify the Verification (검증의 검증)
리포트 작성 전에 다음을 확인:
- [ ] 테스트가 실행되었는가? (CI 통과 여부)
- [ ] 빌드가 성공했는가?
- [ ] UI 변경이 있다면 스크린샷/before-after 비교가 있는가?
- [ ] 버그 수정 MR에 재현 테스트(regression test)가 포함되어 있는가?

누락된 항목이 있으면 리뷰 리포트에 명시적으로 포함한다.

### Phase 6: 리뷰 결과 작성 및 게시
1. **리포트 생성**: 구조화된 리뷰 리포트 작성
2. **MR 코멘트 작성**:
   ```bash
   # MR에 전체 리뷰 코멘트 작성
   glab mr note create <mr_number> --message "<review_comment>"
   ```
3. **터미널 출력**: 리뷰 결과를 터미널에도 표시

## Tool Coordination
- **Bash**: `glab` CLI 실행 (MR 조회, diff 가져오기, 코멘트 작성)
- **Read**: 변경된 파일의 전체 컨텍스트 읽기 (diff만으로 부족한 경우)
- **Grep**: 패턴 기반 취약점/안티패턴 스캔
- **Glob**: 변경된 파일의 테스트 파일 매칭 및 관련 파일 탐색

## Examples

### 현재 브랜치의 MR 리뷰
```
/review-mr
# 현재 브랜치에 연결된 MR을 자동 감지하여 전체 리뷰
# 결과를 MR에 코멘트로 작성
```

### 특정 MR 번호로 리뷰
```
/review-mr 42
# MR !42를 대상으로 전체 코드 리뷰
```

### MR URL로 리뷰
```
/review-mr https://gitlab.com/group/project/-/merge_requests/42
# URL에서 MR 번호를 추출하여 리뷰
```

## Output Format

### 터미널 출력
```
## GitLab MR Review Report

### MR: !42 - [MR 제목]
### Author: @username
### Target: feature-branch → main
### Files Changed: 12 (+340, -89)

---

### Critical (2 issues)

#### [SEC-01] SQL Injection in user query
- **File**: `src/repository/UserRepository.kt:45`
- **Severity**: 🔴 Critical
- **Description**: 사용자 입력이 직접 SQL 쿼리에 포함되어 SQL Injection 공격에 취약합니다.
- **Bad**:
  ```kotlin
  fun findByName(name: String) =
      jdbcTemplate.query("SELECT * FROM users WHERE name = '$name'")
  ```
- **Good**:
  ```kotlin
  fun findByName(name: String) =
      jdbcTemplate.query("SELECT * FROM users WHERE name = ?", name)
  ```

### High (3 issues)
...

### Medium (5 issues)
...

### Nit (2 issues)
...

---

### Summary
- Total issues: 12
- Blocking issues (Critical + High): 5
- Recommendation: 🚫 Changes Requested
- Top 3 actions:
  1. Fix SQL Injection in UserRepository (Critical)
  2. Add null check for response.body (High)
  3. Close database connection in finally block (High)
```

### MR 코멘트 형식
```
## 🤖 AI Code Review

**MR !42** | Files: 12

| Severity | Count |
|----------|-------|
| 🔴 Critical | 2 |
| 🟠 High | 3 |
| 🟡 Medium | 5 |
| 💬 Nit | 2 |

### 🔴 Critical Issues

**[SEC-01] SQL Injection in user query** (`src/repository/UserRepository.kt:45`)
> 사용자 입력이 직접 SQL 쿼리에 포함됩니다. Parameterized query를 사용하세요.

**[BUG-01] NPE on null response** (`src/service/ApiClient.kt:78`)
> response.body가 null일 때 NullPointerException이 발생합니다.

### 🟠 High Issues
...

---

**Recommendation**: 🚫 Changes Requested (5 blocking issues)

<details>
<summary>📊 Full Report</summary>

[전체 상세 리포트]

</details>

---
*Generated by Claude Code `/review-mr` | [Learn more](https://claude.com/claude-code)*
```

## Review Discipline

### 리뷰어 행동규범
- **Rubber-stamp 금지**: 증거 없이 "LGTM"은 리뷰가 아니다
- **문제를 완화하지 마라**: "사소한 문제일 수 있는데…"라고 쓰면서 실제로는 버그인 것을 숨기지 마라
- **정량화하라**: "느릴 수 있다" 대신 "이 N+1 쿼리는 항목당 ~50ms를 추가한다"
- **Sycophancy 금지**: 문제가 명확한 접근법에 동의하지 마라. 아첨은 리뷰의 실패 모드다
- **변명을 수용하지 마라**: "나중에 고치겠다"는 약속을 받아들이지 마라

### Common Rationalizations (리뷰 시 주의할 합리화)

| Rationalization | Reality |
|----------------|---------|
| "동작하니까 충분하다" | 읽기 어렵고, 안전하지 않고, 구조적으로 잘못된 코드는 부채를 복리로 늘린다 |
| "내가 작성했으니 맞을 것이다" | 작성자는 자신의 가정에 대해 눈이 멀어 있다 |
| "나중에 정리하겠다" | "나중"은 오지 않는다 |
| "AI가 생성한 코드니까 괜찮겠지" | AI 코드는 더 엄격한 검토가 필요하다 — 자신감 있고 그럴듯하지만 틀릴 수 있다 |
| "테스트가 통과하니까 괜찮다" | 테스트는 필요조건이지 충분조건이 아니다 — 아키텍처/보안 문제는 잡지 못한다 |

## Boundaries

**Will:**
- `glab` CLI를 사용하여 GitLab MR 정보와 diff를 가져옴
- 변경된 코드의 보안, 로직, 스타일, 테스트 측면을 분석
- 심각도별로 분류된 구조화된 리뷰 리포트 생성
- `glab mr note`로 MR에 리뷰 코멘트 직접 작성
- diff 컨텍스트 부족 시 원본 파일을 Read하여 전체 맥락 파악

**Will Not:**
- 소스 코드를 직접 수정 (리뷰 의견만 제공)
- MR을 승인(approve)하거나 머지(merge) 실행
- CI/CD 파이프라인을 실행하거나 중단
- GitLab API 토큰을 직접 관리 (`glab auth`에 위임)
- GitHub PR을 처리 (GitHub는 내장 `/review` 사용)

## Prerequisites

`glab` CLI가 설치되고 인증이 완료되어 있어야 합니다:
```bash
# 설치 확인
glab --version

# 인증 상태 확인
glab auth status

# 인증이 안 되어 있다면
glab auth login
```

## Related

- `/arch-review` - 아키텍처 관점의 코드 리뷰 (로컬 코드 대상)
- `/perf-review` - 성능 관점의 코드 리뷰 (로컬 코드 대상)
- `/review-mr` - GitLab MR 대상 종합 코드 리뷰 (이 커맨드)
- Claude Code 내장 `/review` - GitHub PR 대상 리뷰 (관리형 서비스)
