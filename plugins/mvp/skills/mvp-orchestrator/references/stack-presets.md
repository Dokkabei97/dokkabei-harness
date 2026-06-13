# Stack Presets — 표준 4스택 스캐폴딩 프리셋

Stage 3에서 TA(tech-architect)가 사용하는 프리셋. 각 프리셋은 **골격 레이아웃 · smoke 테스트 패턴 · gate-cmd** 3요소로 구성된다. TA는 후보 2~3개를 비교 추천하되 강제하지 않으며, 4스택 밖의 제안에는 근거가 필수다.

## 공통 규칙 (전 스택)

1. **gate-cmd는 정확히 1줄**로 `.planning/gate-cmd`에 기록한다. 비대화형이어야 하며(watch 모드 금지), exit code로 성패를 표현해야 한다 — Stop훅과 headless 루프가 이 명령을 그대로 실행한다.
2. **smoke 테스트는 "실제로 뜨는가"를 검증**한다(앱 기동/렌더 + 최소 응답). MB가 만든 테스트를 MB 코드가 통과하는 자기참조성을 외부 검증으로 보강하는 장치다.
3. **빈 골격에서 게이트 그린 확인 후 초기 커밋**(`chore(mvp): scaffold {스택} 골격 + smoke 테스트`). gate-scaffold.sh가 이 커밋과 그린 상태를 검사한다.
4. 골격은 **걷는 골격(walking skeleton)** 까지만 — 도메인 코드는 Stage 4 루프의 몫이다.
5. **E2E 수용 게이트는 선택**이다. UI/유저플로우가 핵심인 스택(특히 Next.js)은 `.planning/e2e-gate-cmd`에 E2E 명령 1줄을 기록해 루프 정지조건(②ᴱ)에 합류시킨다. gate-cmd와 동일 규약(비대화형·exit code·1줄)이며, all-passes 도달 시에만 1회 실행되어 단위 루프 속도에 영향이 없다. 파일을 만들지 않으면 미적용(기존 동작과 100% 동일).

## 선택 기준 결정 트리

```
사용자 인터페이스(웹 화면)가 MVP의 핵심인가?
├─ 예 → React/Next.js
│       └─ 서버 로직이 가벼우면(CRUD·외부 API 프록시 수준)
│          Next.js Route Handlers로 풀스택 단일 레포 권장
└─ 아니오(API/백엔드 가치가 핵심) → 도메인 복잡도·트랜잭션 무게는?
    ├─ 높음(정합성·동시성·결제류 정밀 트랜잭션·JVM 자산 연계) → Kotlin/Spring
    ├─ 낮음(빠른 가설 검증·외부 API/AI 연동 중심·스크립트성 파이프라인) → Python/FastAPI
    └─ 경량·고성능 HTTP API(외부 의존 최소·단일 바이너리·빠른 기동) → Go/stdlib mux
```

**G2 비교표 작성 축**: 개발 속도 / 팀 숙련도 / 운영 부담 / MVP 이후 확장 경로. 추천 1순위에 별표를 달고, `--auto`·`--stack` 모드가 아니면 반드시 사용자 선택을 받는다.

---

## Preset 1: Kotlin/Spring

**선택 신호**: 도메인 트랜잭션이 무겁다, 조직 백엔드 표준(JVM)과의 연계가 예정돼 있다, MVP 이후 정식 서비스 승격 가능성이 높다.

### 골격 레이아웃

```
.
├── settings.gradle.kts
├── build.gradle.kts            # Spring Boot + kotlin("jvm") + actuator + 테스트 의존성
├── gradlew / gradle/wrapper/
├── src/main/kotlin/mvp/
│   ├── Application.kt          # @SpringBootApplication + main()
│   └── presentation/
│       └── HealthController.kt # GET /health → {"status":"ok"} (actuator 보조)
├── src/main/resources/
│   └── application.yml         # 포트·앱 이름 최소 설정
└── src/test/kotlin/mvp/
    └── SmokeTest.kt
```

> 패키지 `mvp`는 기본값 — TA가 서비스명으로 치환한다. DB가 필요한 스토리가 PRD에 있으면 골격 단계에서는 인메모리(H2) 또는 Testcontainers 준비까지만 하고, 실제 스키마는 해당 스토리의 루프 반복에서 만든다.

### smoke 테스트 패턴

```kotlin
package mvp

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.test.context.SpringBootTest
import org.springframework.boot.test.web.client.TestRestTemplate

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SmokeTest(@Autowired val rest: TestRestTemplate) {

    @Test
    fun `애플리케이션 컨텍스트가 뜨고 health가 200을 반환한다`() {
        val res = rest.getForEntity("/health", String::class.java)
        assertThat(res.statusCode.value()).isEqualTo(200)
    }
}
```

### gate-cmd

```
./gradlew test
```

**비고**: 본격 테스트 전략(Kotest/MockK/슬라이스)은 kotlin-spring 플러그인 설치 시 그 표준을 따른다. smoke는 의도적으로 JUnit 최소 구성 — 골격의 의존성을 가볍게 유지한다.

---

## Preset 2: Python/FastAPI

**선택 신호**: 가설 검증 속도가 최우선이다, 외부 API/AI 모델 연동이 핵심이다, 데이터 가공·파이프라인성 로직이 많다.

### 골격 레이아웃

```
.
├── pyproject.toml              # fastapi + uvicorn + pytest + httpx
├── app/
│   ├── __init__.py
│   └── main.py                 # FastAPI() + GET /health
└── tests/
    ├── __init__.py
    └── test_smoke.py
```

`app/main.py` 최소형:

```python
from fastapi import FastAPI

app = FastAPI(title="mvp")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
```

### smoke 테스트 패턴

```python
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_app_boots_and_health_returns_200():
    res = client.get("/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}
```

### gate-cmd

```
pytest -q
```

**비고**: async 설계·Pydantic 스키마·SQLAlchemy 심화는 python-fastapi 플러그인 설치 시 그 표준을 따른다. Alembic은 DB 스토리가 처음 등장하는 루프 반복에서 도입한다.

---

## Preset 3: React/Next.js

**선택 신호**: 웹 UI가 곧 제품이다, SEO/공유 가능한 URL이 필요하다, 서버 로직이 가벼워 Route Handlers로 풀스택 단일 레포가 가능하다.

### 골격 레이아웃

```
.
├── package.json                # scripts.test = "vitest run"  (watch 금지 — 게이트 호환)
├── next.config.mjs
├── tsconfig.json
├── vitest.config.mts           # environment: jsdom + @testing-library 설정
├── app/
│   ├── layout.tsx
│   └── page.tsx                # <h1> 포함 첫 화면
└── tests/
    └── smoke.test.tsx
```

### smoke 테스트 패턴

```tsx
import { render, screen } from "@testing-library/react";
import { expect, test } from "vitest";

import Page from "../app/page";

test("홈 페이지가 크래시 없이 렌더되고 제목이 보인다", () => {
  render(<Page />);
  expect(screen.getByRole("heading", { level: 1 })).toBeDefined();
});
```

### gate-cmd

```
pnpm test
```

**비고**: `package.json`의 `test` 스크립트는 반드시 `vitest run`(1회 실행)으로 고정한다 — `vitest`(watch)면 게이트가 영원히 끝나지 않는다. App Router 심화 패턴(라우팅·페칭·테스트)은 nextjs 플러그인의 가이드를 따른다.

**E2E 수용 게이트(권장)**: 웹 UI가 곧 제품인 스택이므로 E2E를 루프 정지조건에 합류시킨다. Playwright를 설치하고 `playwright.config.ts`의 `webServer`로 dev 서버를 자동 기동/종료하도록 설정한 뒤, **`.planning/e2e-gate-cmd`에 `npx playwright test` 한 줄을 기록**한다. Stop훅이 all-passes 도달 시점에만 이 명령을 1회 실행해 전체 유저플로우 그린을 종료 조건으로 강제한다(②ᴱ). 골격 단계에선 최소 1개 스모크 플로우(홈 진입→핵심 화면 1개)만 두고, 화면별 플로우는 해당 스토리 루프에서 확장한다. E2E가 불필요하면 파일을 만들지 않으면 미적용(회귀 0).

---

## Preset 4: Go/stdlib mux

**선택 신호**: 경량·고성능 HTTP API가 곧 제품이다, 외부 의존을 최소화하고 단일 바이너리로 배포하고 싶다, 빠른 기동·낮은 메모리 풋프린트가 중요하다, 라우팅 중심의 단순한 백엔드다.

### 골격 레이아웃

```
.
├── go.mod                      # module {서비스명} / go 1.22+ (net/http.ServeMux 메서드 라우팅)
├── main.go                     # ServeMux 구성 + http.Server 기동
├── internal/
│   ├── handler/
│   │   └── health.go           # GET /health 핸들러
│   ├── service/                # (Stage 4 도메인 로직 자리)
│   └── repository/             # (Stage 4 영속화 자리)
└── internal/handler/health_test.go
```

`main.go` 최소형:

```go
package main

import (
	"log"
	"net/http"

	"{서비스명}/internal/handler"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handler.Health)

	log.Fatal(http.ListenAndServe(":8080", mux))
}
```

`internal/handler/health.go`:

```go
package handler

import "net/http"

func Health(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok"}`))
}
```

### smoke 테스트 패턴

```go
package handler

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealth(t *testing.T) {
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()

	Health(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("기대 200, 실제 %d", rec.Code)
	}
}
```

> `go.mod`의 module 경로(`{서비스명}`)와 import 경로가 일치해야 한다 — TA가 서비스명으로 함께 치환한다. 라우팅·계층 구조 심화 패턴은 go-mux 플러그인의 가이드를 따른다.

### gate-cmd

```
go build ./... && go test ./...
```

**비고**: `net/http.ServeMux`는 Go 1.22+의 메서드·경로 패턴(`"GET /path/{id}"`)을 전제한다 — 외부 라우터 의존 없이 stdlib만으로 골격을 유지한다. 웹 UI가 함께 필요한 MVP면 Go API 레포와 별도로 프런트(Preset 3)를 추가 제안할 수 있으나, `.planning/` 메모리는 그린필드 레포당 MVP 1개 전제이므로 **루프는 단일 레포에서만 가동**한다. 프런트 동반이 필수면 G2에서 "어느 레포를 MVP 루프 대상으로 할지"를 함께 확정한다.

---

## TA 산출 체크 (gate-scaffold.sh 대응)

| 항목 | 확인 방법 |
|------|----------|
| gate-cmd 기록 | `.planning/gate-cmd`가 존재하고 비어 있지 않은 1줄 |
| 빈 골격 그린 | gate-cmd 실행 exit 0 (smoke 통과) |
| 초기 커밋 | `git rev-parse HEAD` 성공 + 골격 파일이 커밋에 포함 |
| stack-decision.md | 후보·트레이드오프·선택·근거 + G2 승인 기록 |
| prd.json 확정 | 스토리 id·acceptance가 디자인 스펙과 정합, 전 스토리 `passes:false` |
