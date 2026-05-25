// PostToolUse: run gradlew compileKotlin after .kt edits, surface compile errors.

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const { readEvent, passthrough } = require('./_lib/hook-stdin');

const GRADLE_MARKERS = ['build.gradle.kts', 'build.gradle', 'settings.gradle.kts', 'settings.gradle'];

const findGradleRoot = (start) => {
  let dir = start;
  while (dir !== path.dirname(dir)) {
    if (GRADLE_MARKERS.some((m) => fs.existsSync(path.join(dir, m)))) return dir;
    dir = path.dirname(dir);
  }
  return null;
};

(async () => {
  const { raw, json } = await readEvent();
  const p = json.tool_input?.file_path;
  if (!p || !fs.existsSync(p)) return passthrough(raw);

  const root = findGradleRoot(path.dirname(p));
  if (!root || !fs.existsSync(path.join(root, 'gradlew'))) return passthrough(raw);

  const filterRelevant = (out) =>
    out.split('\n')
      .filter((l) => l.includes(path.basename(p)) || /error:/i.test(l))
      .slice(0, 10);

  try {
    const r = execSync('./gradlew compileKotlin --quiet 2>&1', {
      cwd: root,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 120000,
    });
    const lines = filterRelevant(r);
    if (lines.length) {
      console.error('[Hook] Kotlin compile issues:');
      console.error(lines.join('\n'));
    }
  } catch (e) {
    const lines = filterRelevant((e.stdout || '') + (e.stderr || ''));
    if (lines.length) {
      console.error('[Hook] Kotlin compile errors:');
      console.error(lines.join('\n'));
    }
  }
  passthrough(raw);
})();
