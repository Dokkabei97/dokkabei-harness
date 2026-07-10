---
name: supply-chain-guide
description: |
  eng-gov 하네스의 공급망 보안 가이드 — gitleaks baseline 운영(신규 시크릿만 차단), syft SBOM 생성·grype 취약점 스캔(--fail-on high), 라이선스 denylist 정책(references/license-denylist.json 기본값)의 레시피를 제공한다. gate-secrets·gate-supply-chain·gate-policy가 이 스킬의 규약대로 도구를 실행하며, 등록된 게이트의 도구 부재는 fail-closed(skip green은 SOC 2/ISO 27001 허위 증적이라 금지)다. baseline 재생성·오탐 처리·프로젝트별 denylist 오버라이드(.planning/gov/license-denylist.json) 방법을 담는다. CVE DB만 네트워크 의존, 나머지는 로컬. Use when 시크릿·SBOM·취약점·라이선스·IaC 정책 게이트를 설정·운영하거나 baseline/denylist를 조정할 때.
  Supply-chain security guide for eng-gov: recipes for gitleaks baseline operation (block only new secrets), syft SBOM + grype scanning (--fail-on high), and license denylist policy (default in references/license-denylist.json). gate-secrets/supply-chain/policy run tools per this skill; a registered gate's missing tool is fail-closed (skip-green would be false audit evidence). Only the CVE DB needs network. Use when: configuring or operating secret/SBOM/vuln/license/IaC gates, or tuning baseline/denylist.
metadata:
  version: 1.0.0
  category: governance
---

# Supply Chain Guide

공급망 보안 게이트 3종(`gate-secrets`·`gate-supply-chain`·`gate-policy`)의 운영 규약. 전부 로컬 CLI 기반이며 CVE DB 갱신(grype db)만 네트워크에 의존한다.

## 핵심 정책: 등록 시 skip, 런타임 fail-closed

- **게이트 그린 = "검사했고 통과했다"** 의미론을 보존한다. 도구 미설치를 skip green으로 통과시키면 SOC 2/ISO 27001 감사에서 **허위 증적**이 된다.
- 따라서 등록된 게이트의 도구 부재는 **fail-closed(exit 1 + 설치 안내)**. "이 게이트를 안 돌리겠다"는 판단은 `/gov-init`의 `gates.json` 등록 시점(`enabled:false` + `reason`)으로 명시적으로 옮긴다.
- 도구 경로는 `GITLEAKS_BIN`·`SYFT_BIN`·`GRYPE_BIN`·`CONFTEST_BIN` env로 오버라이드(기본값 = 도구명).

## 1. 시크릿 — gitleaks (gate-secrets.sh)

```bash
# 전수 스캔
gitleaks git --no-banner --exit-code 1
# 신규만 차단 (baseline 적용)
gitleaks git --no-banner --exit-code 1 --baseline-path .planning/gov/gitleaks-baseline.json
```

**baseline 운영**: 레거시 레포는 기존 시크릿(이미 로테이션됐거나 오탐)이 많다. baseline을 한 번 생성해 그것을 무시하고 **신규 시크릿만** 차단한다:
```bash
gitleaks git --no-banner --report-format json --report-path .planning/gov/gitleaks-baseline.json
```
- baseline 파일이 존재하면 gate-secrets가 자동으로 `--baseline-path`를 붙인다.
- **오탐 처리**: 진짜 시크릿이 아니면 코드에 `gitleaks:allow` 주석 또는 `.gitleaks.toml` allowlist. 진짜 시크릿이면 **로테이션 먼저**(제거만으로 git 히스토리에 남음).
- baseline은 "기존을 봐준다"일 뿐 — 정기적으로 축소(기존 시크릿 실제 로테이션)하는 게 목표.

## 2. SBOM·취약점 — syft + grype (gate-supply-chain.sh)

```bash
# SBOM 생성 (syft-json)
syft scan dir:. -o syft-json > sbom.json
# 취약점 스캔 (high 이상 발견 시 비정상 exit)
grype sbom:sbom.json --fail-on high
```

- gate-supply-chain은 SBOM을 임시 파일로 생성 → grype `--fail-on high` exit 캡처 → SBOM 라이선스를 denylist와 대조 → 종합 판정.
- **CVE DB**: grype는 첫 실행/주기적으로 취약점 DB를 내려받는다(유일한 네트워크 의존). 오프라인 환경은 `grype db import`로 사전 적재.
- `--fail-on` 임계는 high 기본 — critical만 막으려면 게이트 수정이 아니라 조직 정책으로 조정(문서화).

## 3. 라이선스 denylist (gate-supply-chain.sh ④)

- **기본 목록**: `references/license-denylist.json` — 독점 배포 소프트웨어에서 통상 차단하는 카피레프트(GPL·AGPL·SSPL·BUSL 등). SPDX 식별자를 syft-json의 `.artifacts[].licenses[].value`와 정확 매칭.
- **프로젝트 오버라이드**: `.planning/gov/license-denylist.json`에 동일 스키마로 배치하면 우선 적용(내부 정책 반영).
- 스키마: `{"denied":[...], "review":[...]}`. `denied` = 차단, `review` = 사람 검토 권고(게이트 비차단).
- **법적 판단은 legal 위임** — 이 목록은 관례일 뿐, 특정 라이선스의 자사 사용 가부는 legal이 판단한다.

## 4. IaC 정책 — conftest/Rego (gate-policy.sh)

```bash
conftest test -p .planning/gov/policy/ Dockerfile k8s/*.yaml compose.yml
```
- 대상: `Dockerfile*`, `k8s/*.yaml|yml`, `compose*.y*ml`. 대상 0건이면 공허 통과(도구 요구 없음).
- Rego 정책은 `.planning/gov/policy/`에 배치(`/gov-init`이 스캐폴딩). 예: root 사용자 금지, latest 태그 금지, 리소스 limit 필수.
- 순수 로컬(네트워크 무의존).

## Won't (설계 반면교사)

- **cosign/in-toto SLSA provenance** — CI 서명 인프라 의존이라 문서화 수준으로만(런타임 게이트 미도입).
- **SaaS 취약점 스캐너 API 연동** — CSV/JSON export 입력만. 이 게이트들은 로컬 CLI 전용.
- **보안 코드 리뷰**(injection·authz 로직) → 기존 security-review 스킬·backend-shared:security-check 위임. 이 스킬은 **공급망**(시크릿·의존성·라이선스·IaC)만.

## References

| 문서 | 내용 |
|------|------|
| `references/license-denylist.json` | gate-supply-chain 기본 라이선스 denylist(SPDX). 프로젝트 오버라이드는 `.planning/gov/license-denylist.json` |
