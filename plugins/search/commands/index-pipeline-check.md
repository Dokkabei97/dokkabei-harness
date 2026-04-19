---
name: index-pipeline-check
description: "Indexing pipeline health check — Kafka consumer configuration validation, ES bulk indexing pattern review, pipeline monitoring setup audit"
category: utility
complexity: basic
mcp-servers: []
personas: []
---

# /index-pipeline-check - Indexing Pipeline Health Check

## Triggers
- 배포 전 인덱싱 파이프라인 설정 검증 (pre-deployment validation)
- Consumer lag 증가 또는 인덱싱 지연 원인 조사
- 신규 파이프라인 코드 리뷰 시 설정 적합성 검토
- 정기 감사 — 파이프라인 설정 드리프트 및 모니터링 누락 점검

## Usage
```
/index-pipeline-check [target] [options]

Options:
  --config-only         Kafka consumer 및 ES bulk 설정 검증만 수행 (모니터링 감사 생략)
  --monitoring-audit    모니터링/알림 설정만 감사 (파이프라인 설정 검증 생략)
```

## Behavioral Flow

### Phase 1: Discover Pipeline Components
파이프라인 구성 요소를 탐색하여 분석 대상 파일 목록을 수집한다.

- **Glob**: `**/application*.yml`, `**/application*.yaml`, `**/application*.properties` 패턴으로 Spring 설정 파일 탐색
- **Grep**: `spring.kafka` 설정 블록, `@KafkaListener` 어노테이션, `ConsumerConfig`, `ProducerConfig` 패턴 검색
- **Grep**: `BulkRequest`, `BulkProcessor`, `RestHighLevelClient`, `ElasticsearchClient` 패턴으로 ES bulk 인덱싱 코드 탐색
- **Grep**: Spark 기반 파이프라인의 경우 `SparkConf`, `KafkaUtils`, `foreachBatch`, `writeStream` 패턴 검색
- **Read**: 발견된 설정 파일과 소스 코드를 읽어 전체 파이프라인 구조를 파악

### Phase 2: Validate Kafka Consumer Configuration
Kafka consumer 설정값을 검증하고 위험도를 판정한다.

| 항목 | Good | Warning | Critical |
|---|---|---|---|
| `enable.auto.commit` | `false` (수동 커밋) | 설정 누락 (기본값 `true` 적용) | `true`로 명시 — 메시지 유실 또는 중복 처리 위험 |
| `max.poll.records` | 100-500 사이 명시 설정 | 500 초과 설정 — 처리 시간 초과 가능성 | 설정 누락 (기본값 500) 또는 1000 초과 — poll timeout 위험 |
| `max.poll.interval.ms` | 인덱싱 부하 대비 충분한 값 (300000-600000) | 기본값 300000 사용 중이나 bulk 처리 시간이 길 경우 | 60000 미만 — 대량 처리 시 리밸런싱 빈발 |
| `session.timeout.ms` | 10000-30000 범위 명시 설정 | 기본값 10000 사용 — heartbeat 누락 시 빠른 퇴출 | 60000 초과 — 장애 감지 지연 |
| `auto.offset.reset` | `earliest` (데이터 파이프라인) 또는 `latest` (실시간 스트림) | 설정 누락 — 기본값 `latest`로 메시지 누락 가능 | 용도와 불일치 (데이터 파이프라인에 `latest` 설정) |
| Deserializer | `JsonDeserializer` 또는 `AvroDeserializer` 명시, 에러 핸들러 설정 | Deserializer 설정되었으나 `ErrorHandlingDeserializer` 미적용 | Deserializer 미설정 또는 `StringDeserializer`로 JSON 수동 파싱 |
| Consumer group naming | `{서비스명}-{도메인}-{환경}` 형식 준수 | 네이밍 규칙 부분 준수 (환경 구분 누락 등) | 하드코딩된 그룹명 또는 의미 없는 이름 (예: `group1`, `test`) |
| Concurrency vs partitions | `concurrency` 값이 토픽 파티션 수 이하 | `concurrency`가 파티션 수와 동일 (여유 없음) | `concurrency`가 파티션 수 초과 — 유휴 consumer 발생 |

### Phase 3: Validate ES Bulk Indexing Pattern
ES bulk 인덱싱 코드의 패턴을 검증한다.

| 항목 | Good | Warning | Critical |
|---|---|---|---|
| Bulk API 사용 | `BulkRequest`/`BulkProcessor` 사용, 배치 크기 1000-5000 | Bulk API 사용하나 배치 크기 미설정 또는 100 미만 | 건별 `IndexRequest` — 대량 인덱싱 시 성능 병목 |
| Bulk response 에러 체크 | `hasFailures()` 체크 후 개별 아이템 에러 로깅 | `hasFailures()`만 체크하고 개별 아이템 에러 미확인 | Bulk response 에러 체크 없음 — 부분 실패 감지 불가 |
| Dead Letter Queue (DLQ) | 실패 문서를 DLQ 토픽/테이블로 전송, 재처리 로직 존재 | 실패 문서 로깅만 수행, 수동 재처리 필요 | DLQ 미구현 — 실패 문서 유실 |
| Document ID 전략 | 비즈니스 키 기반 ID 명시 설정 (멱등성 보장) | auto-generated ID 사용 — 재처리 시 중복 문서 생성 가능 | ID 설정 없이 랜덤 생성 — 중복 및 데이터 정합성 위험 |
| Offset commit 타이밍 | ES bulk 성공 확인 후 수동 커밋 (`Acknowledgment.acknowledge()`) | 배치 단위 커밋이나 부분 실패 시 전체 재처리 | Auto commit 또는 ES 응답 무관하게 커밋 — 데이터 유실 위험 |
| `refresh_interval` 설정 | 벌크 인덱싱 중 `refresh_interval: -1` 또는 `30s` 이상 설정 | 기본값 `1s` 사용 — 대량 인덱싱 시 성능 저하 | refresh 설정 고려 없음 + 인덱싱 후 명시적 refresh 미호출 |
| Retry 전략 | Exponential backoff + 최대 재시도 횟수 설정 + circuit breaker | 고정 간격 재시도 또는 최대 횟수 미제한 | 재시도 로직 없음 — 일시적 ES 장애 시 전체 실패 |

### Phase 4: Check Monitoring Setup
파이프라인 모니터링 및 알림 설정의 완성도를 감사한다.

| 항목 | Good | Warning | Critical |
|---|---|---|---|
| Consumer lag metric | Consumer lag 메트릭 수집 (Burrow, kafka_consumer_lag) + 대시보드 존재 | 메트릭 수집되나 대시보드 미구성 | Consumer lag 모니터링 없음 |
| Indexing rate metric | 초당 인덱싱 문서 수 메트릭 (indexing_rate, bulk_docs_count) 수집 | ES 클러스터 레벨 메트릭만 존재, 파이프라인별 분리 안됨 | 인덱싱 처리량 메트릭 없음 |
| Error rate metric | 실패율 메트릭 (bulk_failures, deserialization_errors) + 분류별 집계 | 전체 에러 카운트만 수집, 유형별 분류 없음 | 에러 메트릭 없음 — 장애 감지 불가 |
| Pipeline latency | E2E 지연시간 측정 (Kafka produce ~ ES 검색 가능 시점) | 구간별 지연만 측정 (consume 지연 또는 indexing 지연만) | 지연시간 측정 없음 |
| Alert rules | Consumer lag, 에러율, 지연시간 기준 알림 규칙 + 에스컬레이션 정책 | 알림 규칙 존재하나 임계값 미조정 또는 에스컬레이션 없음 | 알림 규칙 미설정 |

### Phase 5: Generate Report
Phase 2-4 결과를 종합하여 전체 파이프라인 건강 상태 보고서를 생성한다.

1. 각 항목별 Good/Warning/Critical 판정 결과를 집계
2. Critical 항목이 1개 이상이면 전체 상태를 **Critical**로 판정
3. Warning 항목이 3개 이상이면 전체 상태를 **Warning**로 판정
4. 우선순위별 개선 액션을 정리하여 즉시 조치 / 단기 개선 / 장기 개선으로 분류

## Tool Coordination
- **Glob**: `**/application*.yml`, `**/application*.properties`, `**/*Consumer*.kt`, `**/*Indexer*.kt`, `**/*Pipeline*.kt`, `**/docker-compose*.yml`, `**/prometheus*.yml` 패턴으로 파이프라인 관련 파일 탐색
- **Grep**: `spring.kafka`, `@KafkaListener`, `BulkRequest`, `BulkProcessor`, `consumer.group-id`, `max.poll.records`, `enable.auto.commit`, `refresh_interval`, `kafka_consumer_lag`, `micrometer`, `prometheus` 패턴 검색
- **Read**: 설정 파일, consumer/indexer 소스 코드, 모니터링 설정 파일 전체 내용 분석
- **Bash**: YAML/JSON 설정 파일 문법 검증, Gradle/Maven 의존성에서 Kafka/ES 클라이언트 버전 확인

## Examples

### 배포 전 전체 파이프라인 검증
```
/index-pipeline-check src/main/kotlin/com/example/search/pipeline/
# Kafka consumer 설정, ES bulk 패턴, 모니터링 설정을 일괄 검증
# Critical/Warning 항목이 있으면 배포 전 수정 권고
```

### Kafka consumer 설정만 빠르게 점검
```
/index-pipeline-check src/main/kotlin/com/example/search/ --config-only
# Kafka consumer 및 ES bulk 설정만 검증
# 모니터링 감사는 생략하여 빠른 피드백 제공
```

### 모니터링 누락 감사
```
/index-pipeline-check infra/monitoring/ --monitoring-audit
# Prometheus 규칙, Grafana 대시보드, 알림 설정만 감사
# Consumer lag, 에러율, 지연시간 모니터링 존재 여부 확인
```

## Output Format

### Configuration Audit

#### Kafka Consumer Configuration
```
| 항목 | 현재 값 | 판정 | 비고 |
|---|---|---|---|
| enable.auto.commit | false | Good | 수동 커밋 사용 중 |
| max.poll.records | 200 | Good | 적정 범위 |
| max.poll.interval.ms | 300000 (기본값) | Warning | Bulk 처리 시간 대비 검토 필요 |
| session.timeout.ms | 10000 | Good | 적정 범위 |
| auto.offset.reset | latest | Critical | 데이터 파이프라인에 earliest 권장 |
| Deserializer | JsonDeserializer | Warning | ErrorHandlingDeserializer 미적용 |
| Consumer group naming | search-product-indexer | Good | 네이밍 규칙 준수 |
| Concurrency vs partitions | 3 / 6 | Good | 파티션 수 이하 |
```

#### ES Bulk Indexing Pattern
```
| 항목 | 현재 상태 | 판정 | 비고 |
|---|---|---|---|
| Bulk API 사용 | BulkRequest, 배치 크기 2000 | Good | 적정 범위 |
| Bulk response 에러 체크 | hasFailures() + 개별 로깅 | Good | - |
| DLQ | 로깅만 수행 | Warning | DLQ 토픽 도입 권장 |
| Document ID 전략 | 비즈니스 키 (productId) | Good | 멱등성 보장 |
| Offset commit 타이밍 | Bulk 성공 후 수동 커밋 | Good | - |
| refresh_interval | 기본값 1s | Warning | 대량 인덱싱 시 30s 권장 |
| Retry 전략 | Exponential backoff, 최대 3회 | Good | - |
```

#### Monitoring Setup
```
| 항목 | 현재 상태 | 판정 | 비고 |
|---|---|---|---|
| Consumer lag metric | Burrow + Grafana 대시보드 | Good | - |
| Indexing rate metric | 미수집 | Critical | 처리량 메트릭 추가 필요 |
| Error rate metric | 전체 카운트만 수집 | Warning | 유형별 분류 추가 권장 |
| Pipeline latency | 미측정 | Critical | E2E 지연 측정 필요 |
| Alert rules | Consumer lag 알림만 존재 | Warning | 에러율, 지연시간 알림 추가 필요 |
```

### Summary
```
## Pipeline Health Summary
- 전체 상태: [Critical|Warning|Good]
- 검사 항목: [총 항목 수]
- Critical: [count] | Warning: [count] | Good: [count]
```

### Priority Actions
```
## Priority Actions

### 즉시 조치 (Critical)
1. [항목] — [현재 문제] → [권장 조치]
2. [항목] — [현재 문제] → [권장 조치]

### 단기 개선 (Warning, 1-2 스프린트)
1. [항목] — [현재 문제] → [권장 조치]
2. [항목] — [현재 문제] → [권장 조치]

### 장기 개선 (Good → Better)
1. [항목] — [현재 상태에서 더 개선할 수 있는 방향]
```

## Boundaries

**Will:**
- Kafka consumer 설정값을 코드/설정 파일에서 추출하여 권장 범위와 비교 검증
- ES bulk 인덱싱 패턴의 안전성 및 성능 관련 코드 패턴 검토
- 파이프라인 모니터링 설정의 완성도 감사 (메트릭 수집, 대시보드, 알림 규칙)
- 항목별 Good/Warning/Critical 판정과 우선순위 기반 개선 액션 제시
- Spring Kafka, Kafka Streams, Spark Structured Streaming 기반 파이프라인 분석

**Will Not:**
- 실제 Kafka 클러스터나 ES 클러스터에 접속하여 설정 조회 또는 변경
- Consumer lag, 인덱싱 처리량 등 런타임 메트릭 수집 또는 실시간 모니터링
- 파이프라인 소스 코드를 사용자 동의 없이 수정
- Kafka 토픽 생성/삭제, ES 인덱스 생성/삭제 등 인프라 변경 작업 수행
- 비즈니스 로직 검증 (데이터 변환 정확성, 도메인 규칙 적합성)
