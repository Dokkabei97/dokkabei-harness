# 통제 매핑표 — git 네이티브 증적 → 감사 통제

eng-gov 산출물을 SOC 2 Type II·ISO 27001:2022 감사 통제에 매핑한다. `/gov-audit`가 이 표를 근거로 `audit-log.jsonl`과 게이트 결과를 **감사 증적 문서**로 변환한다. 법 해석·인증 취득 판단은 legal 위임 — 이 표는 "어떤 산출물이 어떤 통제의 증거가 되는가"의 매핑일 뿐이다.

## 매핑표

| eng-gov 산출물 / 게이트 | SOC 2 (2017 TSC) | ISO 27001:2022 Annex A | 증적 성격 |
|------------------------|------------------|------------------------|-----------|
| `evidence.json` + `gate-change-evidence` (변경 승인·4-eyes) | **CC8.1** 변경 관리 | **A.8.32** Change management | 변경별 SHA·승인자·게이트 결과 |
| `gate-secrets` (신규 시크릿 차단) | CC6.1 논리적 접근 | **A.8.24** Use of cryptography | 시크릿 노출 방지 기록 |
| `gate-supply-chain` (SBOM·CVE·라이선스) | CC7.1 취약점 관리 | **A.8.8** Technical vulnerabilities / A.8.30 Outsourced development | SBOM·취약점 스캔 증적 |
| `gate-policy` (IaC 정책) | CC7.1 / CC8.1 | **A.8.9** Configuration management | 인프라 구성 정책 준수 |
| ADR + `gate-adr` (결정 이력) | CC2.2 내부 커뮤니케이션 | **A.8.27** Secure system architecture & engineering principles / A.5.1 Policies | 아키텍처 결정 append-only 이력 |
| SLO·에러버짓 + `gate-error-budget` | A1.1 가용성 목표 | **A.8.6** Capacity management / A.8.14 Redundancy | 가용성 목표·버짓 판정 |
| 포스트모템 | CC7.3/CC7.4 사고 대응 | **A.5.27** Learning from information security incidents | 블레임리스 사후분석·재발방지 액션 |
| `audit-log.jsonl` (append-only) | CC4.1 모니터링 | **A.8.15** Logging / A.5.28 Collection of evidence | 게이트 실행 감사 로그 |

## 핵심 증적 흐름

1. **변경통제(가장 중요)**: 커밋 → `/gov-change`가 위험 등급 + evidence.json → `gate-change-evidence`가 4-eyes·게이트 그린 검증 → SOC 2 CC8.1 / ISO 27001 A.8.32의 결정론 증거.
2. **공급망**: `gate-secrets` + `gate-supply-chain` 실행 기록이 high 변경 evidence에 강제 포함 → ISO 27001 A.8.8/A.8.24.
3. **감사 추적**: `/gov-audit`가 `run-registered.sh` 결과를 `audit-log.jsonl`에 append + 감사 증적 문서로 변환 → SOC 2 CC4.1 / ISO 27001 A.8.15·A.5.28.

## 주의

- 통제 번호는 SOC 2 2017 TSC / ISO 27001:2022 Annex A 기준. 프레임워크 개정 시 매핑을 재확인한다(**갱신 필요** 스탬프).
- 이 매핑은 **인증 취득을 보장하지 않는다**. 통제의 "결정론 반쪽"(문서·게이트 존재)일 뿐, 운영 실효성 판단과 인증심사는 별개다.
- 지역·업권 특화 통제(전자금융·개인정보 등)는 v2 백로그 — 법·규제 해석은 legal 위임.
