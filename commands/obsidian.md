---
name: obsidian
description: "Obsidian 기반 기술 학습 노트 생성. 7종 템플릿(개념, 실습, 비교, 트러블슈팅, 패턴, TIL, MOC)을 활용한 체계적 학습 기록."
category: documentation
complexity: basic
mcp-servers: []
personas: []
---

# /obsidian - 기술 학습 노트 생성

## Triggers
- 기술 개념 학습 노트 작성
- 코드 실습/튜토리얼 기록
- 라이브러리/프레임워크 비교 분석
- 에러 해결/트러블슈팅 기록
- 아키텍처/설계 패턴 학습
- TIL(Today I Learned) 작성
- MOC(Map of Content) 인덱스 생성

## Usage
```
/obsidian [type] [topic]

Types:
  concept        기술 개념 학습 노트
  lab            코드 실습/튜토리얼 기록
  comparison     라이브러리/프레임워크 비교 분석
  troubleshoot   에러 해결/트러블슈팅 기록
  pattern        아키텍처/설계 패턴 학습
  til            TIL (Today I Learned) 작성
  moc            MOC (Map of Content) 인덱스 생성
```

## Behavioral Flow

### 1. 문서 유형 결정
사용자가 type을 지정하지 않은 경우, topic 키워드로 자동 감지:

| 키워드 | 추론 유형 |
|--------|----------|
| vs, 비교, 차이, 대안 | comparison |
| 에러, error, 오류, 해결, fix, bug | troubleshoot |
| 패턴, pattern, 아키텍처, architecture, 설계 | pattern |
| 실습, lab, 튜토리얼, tutorial, hands-on | lab |
| TIL, 오늘, today | til |
| MOC, 인덱스, 목록, 로드맵 | moc |
| 그 외 | concept (기본값) |

### 2. 템플릿 기반 노트 생성
1. `skills/obsidian-tech-note/` 스킬 참조
2. 해당 type의 템플릿 로드
3. 사용자 topic을 반영하여 노트 내용 작성
4. Obsidian YAML 프론트매터 형식 준수
5. Templater 구문(`<% %>`)은 그대로 유지하여 Obsidian에서 실행되도록 함

### 3. 출력
- Obsidian Vault에 직접 파일 생성 또는
- 마크다운 내용을 출력하여 사용자가 복사/저장

## Examples

### 기술 개념 학습
```
/obsidian concept React Hooks
# React Hooks 개념 학습 노트 생성
# 정의, 핵심 원리, 코드 예제, 학습 체크리스트 포함
```

### 코드 실습 기록
```
/obsidian lab Spring Boot REST API
# Spring Boot REST API 실습 노트 생성
# 환경 설정, 단계별 실습 코드, 실행 결과, 트러블슈팅 메모 포함
```

### 비교 분석
```
/obsidian comparison React vs Vue
# React와 Vue 비교 분석 노트 생성
# 비교 테이블, 장단점, 코드 비교, 의사결정 매트릭스 포함
```

### 트러블슈팅
```
/obsidian troubleshoot OOM Kubernetes
# Kubernetes OOM 에러 트러블슈팅 노트 생성
# 에러 메시지, 원인 분석, 해결 방법, 예방 조치 포함
```

### 아키텍처 패턴
```
/obsidian pattern CQRS
# CQRS 패턴 학습 노트 생성
# 패턴 개요, Mermaid 다이어그램, 구현 예제, 트레이드오프 포함
```

### TIL
```
/obsidian til
# 오늘 날짜 TIL 노트 생성
# 배운 것, 핵심 코드, 문제 해결 기록, 내일 할 일 포함
```

### MOC 인덱스
```
/obsidian moc Frontend
# Frontend MOC 인덱스 생성
# DataView 쿼리 기반 자동 노트 목록, 학습 진행 통계 포함
```

## Tool Coordination
- **Read**: 기존 노트/템플릿 참조
- **Write**: 노트 파일 생성
- **WebSearch**: 기술 주제 조사 (필요시)
- **Bash**: 파일 시스템 조작 (Vault 경로 확인 등)

## Boundaries

**Will:**
- 7종 템플릿에 맞는 Obsidian 마크다운 노트 생성
- YAML 프론트매터, 태그, 위키링크 등 Obsidian 규칙 준수
- Templater/DataView/Tasks 플러그인 구문 포함
- 사용자 topic에 맞는 내용 조사 및 정리

**Will Not:**
- Obsidian 앱 자체를 제어하거나 플러그인 설치
- 사용자 Vault 설정 변경
- 학습 내용의 정확성 보장 (사용자 검증 필요)

## Related

- `skills/obsidian-tech-note/SKILL.md` - 템플릿 시스템 가이드
- `skills/obsidian-tech-note/templates/` - 7종 템플릿 파일
- `skills/document/SKILL.md` - 범용 문서 작성 스킬
