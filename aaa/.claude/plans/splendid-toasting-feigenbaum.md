# Git Detached HEAD 복구

## Context
`feature/reserve-sync` 브랜치에서 롤백 작업 중 detached HEAD 상태가 되었음. 현재 HEAD는 `a9ac249`(원하는 커밋)에 있지만 브랜치는 `a027bda`를 가리키고 있음.

## 실행 계획
1. `git branch -f feature/reserve-sync a9ac249` — 브랜치 포인터를 현재 HEAD로 이동
2. `git checkout feature/reserve-sync` — 브랜치로 전환하여 detached 상태 해소
3. `git status` + `git log` — 복구 확인

## 검증
- `git status`에서 `On branch feature/reserve-sync` 출력 확인
- `git log --oneline -1`에서 `a9ac249` 확인
