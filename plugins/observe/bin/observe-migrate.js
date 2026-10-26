#!/usr/bin/env node
// observe-migrate.js — 일회성 이전: 구 .claude/skill-trace.jsonl(.1) v0 → .tracer v1 (의존성 없음).
//
// 사용: node observe-migrate.js [--root <레포 루트>] [--dry-run]
//   --root     기본은 리포트와 같은 탐지(paths.findRoot: CLAUDE_PROJECT_DIR → cwd 에서 위로 .tracer/구 경로가
//              있는 가장 가까운 조상(git toplevel 까지) → git toplevel → cwd)
//   --dry-run  변환 건수만 보고하고 아무것도 쓰지 않는다
//
// 변환은 훅과 같은 writer.write 를 쓴다 — 원문은 레드액션해 raw/ 로, 이벤트는 세션별 파일로.
// 전부 쓴 뒤에야 구 파일을 <파일>.migrated 로 rename 한다(삭제하지 않음 — 확인 후 사용자가 지운다).
// rename 해야 reader 의 구 경로 폴백이 같은 레코드를 두 번 읽지 않는다. 쓰기 도중 실패하면
// 구 파일을 그대로 두고 exit 1 — 이미 쓴 .tracer 파일은 남으므로 보고된 경로를 확인하라.
// 파싱 불가 줄·알 수 없는 type 레코드는 옮기지 않는다(원본은 .migrated 에 보존 — reader 도 구 경로에서
// 같은 레코드를 세지 않으므로 전후 집계는 같다). ts 없는 레코드는 이전 시각으로 채우지 않는다(keepTs).
// 홈 디렉터리는 루트로 받지 않는다 — <홈>/.tracer 는 전역 층(원문 금지).
// 이 스크립트는 사용자가 명시 실행하는 CLI 다 — 훅이 아니므로 결과를 stdout 으로 보고한다.
"use strict";
const fs = require("fs");
const P = require("./hooks/_lib/paths");
const { write } = require("./hooks/_lib/writer");

function main() {
  const argv = process.argv.slice(2);
  let root = null;
  let dry = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--root") root = argv[++i];
    else if (argv[i] === "--dry-run") dry = true;
  }
  root = root || P.findRoot(process.cwd());
  if (P.isHome(root)) {
    console.error(`observe-migrate: 홈 디렉터리(${root})는 레포 루트로 이전하지 않음 — ~/.tracer 는 전역 층(원문 금지)`);
    process.exit(1);
  }
  const base = P.legacyTrace(root);
  const files = [base + ".1", base].filter((f) => fs.existsSync(f));
  if (!files.length) {
    console.log(`observe-migrate: 구 경로 트레이스 없음 (${base}) — 할 일 없음`);
    return;
  }

  const recs = [];
  let bad = 0;
  for (const f of files) {
    for (const line of fs.readFileSync(f, "utf8").split("\n")) {
      if (!line.trim()) continue;
      try {
        const v = JSON.parse(line);
        if (v && typeof v === "object" && !Array.isArray(v)) recs.push(v);
        else bad++;
      } catch (_) {
        bad++;
      }
    }
  }

  let written = 0;
  let skipped = 0;
  if (!dry) {
    try {
      for (const r of recs) (write(root, r, undefined, { keepTs: true }) ? written++ : skipped++);
    } catch (e) {
      console.error(`observe-migrate: 쓰기 실패 — 구 파일은 그대로 둠 (${written}건 기록 후 중단): ${e.message}`);
      console.error(`  이미 기록된 이벤트: ${P.tracerDir(root)} — 재실행 전 확인하라(중복 방지)`);
      process.exit(1);
    }
    for (const f of files) fs.renameSync(f, f + ".migrated");
  }
  console.log(
    `observe-migrate${dry ? " (dry-run)" : ""}: ${files.length}개 파일, 레코드 ${recs.length}건` +
      (dry ? "" : ` → 이벤트 ${written}건 기록(알 수 없는 type ${skipped}건 제외)`) +
      `, 파싱 실패 ${bad}줄 미이전`,
  );
  if (!dry) {
    console.log(`  대상: ${P.tracerDir(root)}`);
    console.log(`  원본: ${files.map((f) => f + ".migrated").join(", ")} (확인 후 직접 삭제)`);
  }
}

main();
