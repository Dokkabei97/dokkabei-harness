---
name: release-notes
description: |
  GitLab 릴리즈 노트·체인지로그 자동 생성. 직전 릴리즈 태그 이후 머지된 MR을 glab으로 수집하고, conventional commit/MR 제목으로 변경 유형을 분류해 한국어 체인지로그 초안을 만든다. semver 다음 버전을 제안하고, 태그·GitLab Release 생성 명령을 안내한다(원격 반영은 사용자 승인 후).
  Generates GitLab release notes and changelogs: collects MRs merged since the last release tag via glab, classifies change types from conventional commit/MR titles into a changelog draft, proposes the next semver version, and guides tag/GitLab Release creation (remote push only after user approval). Use when: writing release notes, generating a changelog, cutting a release, bumping the version.
category: workflow
complexity: standard
mcp-servers: []
personas: []
---

# /release-notes - GitLab 릴리즈 노트·체인지로그 생성

직전 릴리즈 태그 이후 머지된 Merge Request를 수집·분류해 한국어 체인지로그와
릴리즈 노트 초안을 만들고, 다음 semver 버전과 태그·Release 생성 명령을 제안한다.
`glab`(GitLab CLI)과 로컬 git 이력을 사용하며, 원격에 반영하는 작업은 항상 사용자 승인 후 실행한다.

## Triggers
- 스프린트/릴리즈 마감 시 변경 이력을 정리해 체인지로그를 만들 때
- GitLab Release 게시를 위한 릴리즈 노트 초안이 필요할 때
- 다음 버전(semver) 범프 수준(major/minor/patch)을 판단해야 할 때
- 직전 태그 이후 무엇이 머지됐는지 한눈에 요약이 필요할 때

## Usage
```
/release-notes [since-tag] [options]

Arguments:
  since-tag        기준 태그(생략 시 직전 태그 자동 탐지: git describe --tags --abbrev=0)

Options:
  --to <ref>       종료 지점(기본 HEAD)
  --write          CHANGELOG.md 상단에 이번 릴리즈 섹션을 삽입(승인 후)
  --version <ver>  제안 버전을 수동 지정(생략 시 변경 유형으로 자동 산정)
  --no-tag         태그/Release 생성 안내 단계 생략(체인지로그만)
```

## Behavioral Flow

### Phase 1: Discovery
기준 태그와 종료 지점 사이에 머지된 MR을 수집한다.

**Steps:**
1. **Scan**: `git describe --tags --abbrev=0`로 직전 태그를 찾고(없으면 최초 커밋),
   `git log <since-tag>..<to> --merges --first-parent`로 머지 커밋을 나열한다.
2. **Analyze**: 각 머지 커밋의 MR 번호를 파싱해 `glab mr view <iid>`로 제목·라벨·작성자를 수집한다
   (glab 미인증/부재 시 git 머지 메시지만으로 폴백하고 그 사실을 명시한다).
3. **Classify**: MR 제목의 conventional 접두어(feat/fix/refactor/perf/docs/test/chore/build/ci)와
   `!`/`BREAKING CHANGE`(파괴적 변경) 여부로 변경 유형을 분류한다.

### Phase 2: Execution
분류 결과로 버전과 체인지로그를 산정한다.

**Steps:**
1. **Process**: 유형별로 그룹핑한다 — ✨ 기능(feat) · 🐛 버그 수정(fix) · ♻️ 리팩터링/성능(refactor,perf) ·
   📝 문서(docs) · 🔧 기타(chore,build,ci,test).
2. **Evaluate**: semver 다음 버전을 산정한다 — 파괴적 변경 ≥1 → **major**, feat ≥1 → **minor**,
   그 외 → **patch**. `--version` 지정 시 그 값을 우선한다.
3. **Generate**: 한국어 체인지로그와 릴리즈 노트 초안을 만든다. 각 항목은
   `- <요약> (!<MR iid>, @<작성자>)` 형식으로, 파괴적 변경은 별도 **⚠️ Breaking Changes** 절에 앞세운다.

### Phase 3: Output
초안을 제시하고 반영 명령을 안내한다.

**Steps:**
1. **Format**: 제안 버전 + 그룹핑된 체인지로그를 마크다운으로 출력한다.
   `--write` 지정 시 `CHANGELOG.md` 최상단(제목 아래)에 이번 릴리즈 섹션을 삽입한다(기존 내용 보존).
2. **Present**: 태그·Release 생성 명령을 **실행하지 않고 제안**한다
   (`git tag -a v<ver> -m ...` / `glab release create v<ver> --notes-file ...`).
   사용자가 승인하면 실행하고, 후속으로 `/post-merge`(이슈 종료·위키 문서) 연계를 안내한다.

## Tool Coordination
- **Bash**: `git describe`/`git log`로 태그·머지 이력 수집, `glab mr view`/`glab release create`/`git tag` 실행
- **Read**: 기존 `CHANGELOG.md`를 읽어 중복 방지·삽입 위치 결정
- **Grep**: 머지 메시지에서 MR iid(`!\d+`)·conventional 접두어 추출
- **Write**: `--write` 시 `CHANGELOG.md` 갱신(base block-md-creation 허용목록에 포함됨)

## Examples

### Basic Usage
```
/release-notes
# 직전 태그~HEAD 사이 머지 MR을 수집해 체인지로그 초안과 제안 버전을 출력(파일 미변경)
```

### With Options
```
/release-notes v1.2.0 --write
# v1.2.0 이후 변경을 정리해 CHANGELOG.md 상단에 이번 릴리즈 섹션 삽입(승인 후)
```

### Advanced Usage
```
/release-notes v1.2.0 --to release/1.3 --version 1.3.0 --write
# 특정 브랜치까지의 변경을 버전 1.3.0으로 고정해 체인지로그 작성 + 태그/Release 명령 안내
```

## Boundaries

**Will:**
- 직전 릴리즈 태그 이후 머지된 MR을 glab/git으로 수집하고 conventional 접두어로 분류
- 파괴적 변경/feat/fix 구성으로 semver 다음 버전(major/minor/patch)을 제안
- 한국어 체인지로그·릴리즈 노트 초안을 유형별로 그룹핑해 생성
- `--write` 시 기존 내용을 보존하며 `CHANGELOG.md` 상단에 이번 릴리즈 섹션 삽입
- 태그·GitLab Release 생성 명령을 제안하고, 승인 시에만 실행

**Will Not:**
- 사용자 승인 없이 태그를 push하거나 GitLab Release를 게시(되돌리기 어려운 원격 작업)
- Plane 이슈 종료·Outline 위키 문서 갱신(그건 `/post-merge`가 담당)
- 코드 리뷰·머지 가부 판단(그건 `/review-mr`가 담당)
- glab 미인증 상태에서 추측으로 MR 메타데이터를 지어내기(폴백 사실을 명시)
