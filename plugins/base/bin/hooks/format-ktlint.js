// PostToolUse: run ktlintFormat after Kotlin edits (searches for nearest gradle root).

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

  try {
    execSync('./gradlew ktlintFormat 2>&1', {
      cwd: root,
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      timeout: 60000,
    });
    console.error('[Hook] ktlintFormat applied to Kotlin files');
  } catch (e) {
    const out = (e.stdout || '') + (e.stderr || '');
    const lines = out.split('\n').filter((l) => l.includes(p) || l.includes('FAILED')).slice(0, 10);
    if (lines.length) console.error('[Hook] ktlintFormat issues:\n' + lines.join('\n'));
  }
  passthrough(raw);
})();
