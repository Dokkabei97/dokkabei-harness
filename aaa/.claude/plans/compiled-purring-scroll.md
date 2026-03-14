# Plan: application-local.yml 오타 수정

## Context
Helm ConfigMap과 application.yml 파일들의 정합성을 검토한 결과, `application-local.yml`에 환경변수명 오타가 발견되었습니다.
나머지 미사용 환경변수(VALKEY_*, KEYWORD_ANALYSIS_* 등)는 현재 상태 유지합니다.

## 변경 사항

### 파일: `src/main/resources/application-local.yml` (Line 2)

- **변경 전:** `${ELASTICSEARCH_URLSs:http://localhost:9200/}`
- **변경 후:** `${ELASTICSEARCH_URLS:http://localhost:9200/}`
- **이유:** 환경변수명 끝에 소문자 `s`가 중복되어 있어, 환경변수 `ELASTICSEARCH_URLS`를 설정해도 인식되지 않음

## 검증
- `./gradlew build -x test` 로 빌드 정상 확인
