# 항목 선별 기준과 점검표

## 1. 입력 계약

스택 플러그인 references 의 항목 포맷(이 스킬이 의존하는 유일한 구조):

```
### <PREFIX>-<AREA>-<NN> · <함정 한 줄 제목>
- 적용: <버전/조건>
- 신호: <코드 패턴·메트릭·증상>
- 메커니즘: …
- 처방: …
- 반례: …
- 검증: …
- 근거: …
```

PREFIX·AREA 는 대문자로 시작하고 숫자를 포함할 수 있다(예: `NX-V16-01`).

`scripts/specialist-index.sh` 가 제목·적용을 TSV 로 뽑는다(`file` 열은 절대 경로). 신호 줄은 후보에 한해 `file` 에서
해당 ID 블록만 읽는다:

```bash
awk -v i="JVM-GC-02" '$0 ~ "^### "i" " {p=1; next} p && /^- 신호:/ {print; exit}' "<file>"
```

## 2. 적용 조건 판정

| `적용:` 표현 | 프로필 대조 | 판정 |
|-------------|-------------|------|
| 버전 하한 "JDK 21+", "Go 1.22+", "Next 16+" | 감지 버전 ≥ 하한 | 포함 |
| 버전 상한/범위 "Go < 1.22", "Boot 3.0–3.2", "Python 3.14.0~3.14.4" | 범위 안 | 포함 (범위 밖 패치 버전이면 제외) |
| 구성 조건 "컨테이너 배포", "JPA 사용", "pgx stdlib" | 프로필의 해당 사실이 확인됨 | 포함 |
| 경로 조건 "대량 적재 경로", "핫 루프" | 저장소에서 그 구성이 발견됨 | 포함 |
| 운영 조건 "프로덕션에서 서비스", "레플리카 2+", "롤링 배포" | 배포 매니페스트·CI 로 확인됨 | 포함, 미확인이면 제외 |
| 버전 미확인(BOM 관리 포함)인데 버전 조건이 붙음 | — | 제외(보고서에 "버전 미확인으로 제외 N건" + 확인 방법) |
| 플래그로 이미 해소되는 조건 "Kotlin 2.2+ 에서 X 옵션 미사용" | 옵션이 켜져 있음 | 제외 |
| 조건 없음/범용 | — | 신호가 발견될 때만 |

조건 둘 이상이면 모두 만족해야 한다. 애매하면 제외한다 — 틀린 규칙이 빠진 규칙보다 비싸다.

## 3. 신호 확인

`- 신호:` 줄은 두 종류가 섞여 있다. 종류에 따라 확인 방법이 다르다.

| 신호 종류 | 예 | 확인 |
|-----------|----|------|
| 코드 패턴 | `` `runBlocking { }` ``, `` `"refresh_interval": "1s"` ``, `` `ALTER TYPE … ADD VALUE` `` | Grep 으로 저장소에서 찾는다 → 발견 위치(파일:줄)를 근거 표에 |
| 부재 패턴 | "`response.errors()` 미확인", "타임아웃 미설정" | 해당 호출부를 읽고 확인 코드가 **없음**을 확인 |
| 런타임 증상 | "p99 계단식 증가", "스레드 덤프에 …", "로그에 …" | 정적으로 확인 불가 — 그 증상을 만드는 구성(예: 블로킹 클라이언트를 `Dispatchers.IO` 에서 호출)이 코드에 있는지로 판정 |

판정 결과는 셋 중 하나로 적는다:

- **발견** — 함정이 지금 코드에 있다 → 우선 포함
- **구성만 있음** — 함정이 생길 수 있는 구성은 있으나 지금은 문제 없음 → 조건이 명확하면 포함(회귀 방지)
- **대응됨** — 이미 처방대로 되어 있다(예: 커스텀 nori analyzer 에 `lowercase`·`nori_readingform` 이 있음) → 제외.
  단 그 대응이 블록 밖 AGENTS.md·CLAUDE.md 에도 없고 깨지기 쉬운 것이면 "구성만 있음"으로 낮춰 포함할 수 있다

## 4. 우선순위와 배치

순위(스택당 ≤15):

1. 신호가 **발견**된 항목
2. 운영 장애로 이어지는 것(풀 고갈, GC 정지, OOMKilled, 매핑 폭발, 데이터 유실) > 성능 최적화 > 관용 표현
3. 같은 메커니즘은 하나만 — 플러그인을 가로질러도 적용(예: `SPR-JSON-03` 과 `DTO-S-01` 은 같은 Kotlin 모듈 null 시맨틱 →
   rules 파일이 속한 스택 플러그인 쪽 하나), 블록 밖 AGENTS.md·CLAUDE.md·`@import` 문서에 이미 적힌 함정은 제외
4. 사용자가 이전 rules 파일에 손으로 남긴 항목은 유지

core(AGENTS.md 블록의 `## Specialist core`, 전체 ≤15줄) 지정 순서:

1. **새 파일을 만들 때 걸리는 함정** — 마이그레이션·라우트·Server Action·DTO 처럼 heredoc 으로 새로 생성되면 paths rules 가
   로드되지 않는 위치(§ SKILL "로드 방식이 배치를 정한다")
2. **버전 습관 함정** — 모델이 학습된 구버전 관용구로 쓰는 것(Jackson 2 패키지, 동기 `params`, `middleware.ts`)
3. 신호가 **발견**된 운영 장애급 항목

core 에 올린 ID 는 paths rules 에 반복하지 않는다. 스택 rules 에 남는 것이 없으면 그 파일은 만들지 않는다.

선별 근거 표(승인 게이트에 그대로 제시):

| ID | 적용 조건 | 프로필 근거 | 신호(판정 · 위치) | 배치 |
|----|----------|-------------|-------------------|------|
| JVM-GC-02 | `-Xmx` 미지정 + 컨테이너 | toolchain 21, Dockerfile·k8s limits | 발견 · `JAVA_TOOL_OPTIONS` 에 `-Xmx`/`MaxRAMPercentage` 없음 | core |

근거 표 아래에 제외 요약을 붙인다: "버전 미확인 N건(확인 방법) · 구성 없음 N건 · 대응됨 N건 · 기존 AGENTS.md·CLAUDE.md 중복 N건".

## 5. --check 점검표

1. **블록 위치**: AGENTS.md 에 `project-rules:start/end` 가 정확히 한 쌍인가(0쌍이면 "미생성", 2쌍 이상이면 오류).
   CLAUDE.md 에 블록이 있으면 미러 모드가 아닌 한 "이전 필요(SKILL (f))". 미러 모드면 두 사본의 마커 사이가 같은가
   (`diff <(awk '/project-rules:start/,/project-rules:end/' AGENTS.md) <(awk '/project-rules:start/,/project-rules:end/' CLAUDE.md)`).
   `.claude/rules/specialist-core.md` 가 남아 있으면 "이전 필요"
2. **Claude 연결**: CLAUDE.md(루트 또는 `.claude/CLAUDE.md`)가 있으면 코드 스팬·펜스 밖에 `@AGENTS.md` 가 있는가(미러 모드 제외).
   없으면 Claude Code 는 AGENTS.md 를 읽지 않는다. CLAUDE.md 없이 `CLAUDE.local.md` 만 있어도 같다
3. **가림**: 블록이 든 디렉터리에 `AGENTS.override.md` 가 있으면 Codex 는 AGENTS.md 대신 그것을 읽는다
4. **버전 드리프트**: 블록과 rules 메타 주석의 버전 ↔ 현재 감지 버전. 블록 밖에 적힌 버전이 다르면 "블록 밖 불일치"로 보고만
5. **없는 도구 참조**: 블록·rules 에 적힌 도구/명령(Flyway, Alembic, `./gradlew`, `pnpm` 등)이 현재 빌드 파일·디렉터리에 근거가 있는가
6. **사라진 ID**: core·rules 의 각 ID 가 현재 색인에 존재하는가(설치본이 구버전이면 "업데이트 필요"로 구분)
7. **조건 이탈**: 각 ID 의 현재 `적용:` 이 프로필과 여전히 맞는가
8. **core 형식**: `## Specialist core` 항목 ≤15줄인가, path rules 와 ID 가 겹치지 않는가. 선택 (e) `.agents/rules/*` 가
   있으면 대응하는 `.claude/rules/*` 와 본문(frontmatter 제외)이 같은가
9. **크기**: 블록 50줄·6,000바이트 초과(스택 사실 30줄, core 15줄), `wc -c AGENTS.md` 24,000 초과(Antigravity 파일 한도),
   git 루트→하위 프로젝트 AGENTS.md 합계 32,768 초과(Codex `project_doc_max_bytes`), CLAUDE.md(+`@import` 대상) 200줄 초과,
   rules 파일당 항목 15개 초과
10. **paths 유효성**: rules `paths` 글롭이 실제 파일을 하나라도 매칭하는가(`git ls-files` 로 확인)

출력 형식:

```
## project-rules --check
| # | 점검 | 상태 | 상세 |
|---|------|------|------|
| 1 | 블록 위치 | MIGRATE | 블록이 CLAUDE.md 에만 있음, specialist-core.md 잔존 — 이전 제안 (f) |
| 2 | Claude 연결 | WARN | CLAUDE.md 에 `@AGENTS.md` 없음 |
| 4 | 버전 드리프트 | DRIFT | Spring Boot 3.3.5 → 3.4.1 (build.gradle.kts:5) |
| 6 | 사라진 ID | MISSING | JVM-GC-07 |
| 8 | core 형식 | WARN | SPR-TX-02 가 core 와 kotlin-specialist.md 에 중복 |
| 9 | 크기 | WARN | AGENTS.md 25,310B (>24,000 — Antigravity 에서 뒤쪽이 잘림) |
→ 재생성 제안을 볼까요?
```
