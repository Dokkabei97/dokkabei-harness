#!/usr/bin/env node
/**
 * SessionStart Hook - Load previous context on new session
 *
 * Cross-platform (Windows, macOS, Linux)
 *
 * Runs when a new Claude session starts. Checks for recent session
 * files and notifies Claude of available context to load.
 */

const path = require('path');
const {
  getSessionsDir,
  getLearnedSkillsDir,
  findFiles,
  ensureDir,
  log
} = require('../lib/utils');
const { getPackageManager, getSelectionPrompt } = require('../lib/package-manager');
const { getProjectContext, getProjectSummary } = require('../lib/project-context');

async function main() {
  const sessionsDir = getSessionsDir();
  const learnedDir = getLearnedSkillsDir();

  // Ensure directories exist
  ensureDir(sessionsDir);
  ensureDir(learnedDir);

  // Check for recent session files (last 7 days)
  // Match both old format (YYYY-MM-DD-session.tmp) and new format (YYYY-MM-DD-shortid-session.tmp)
  const recentSessions = findFiles(sessionsDir, '*-session.tmp', { maxAge: 7 });

  if (recentSessions.length > 0) {
    const latest = recentSessions[0];
    log(`[SessionStart] Found ${recentSessions.length} recent session(s)`);
    log(`[SessionStart] Latest: ${latest.path}`);
  }

  // Check for learned skills
  const learnedSkills = findFiles(learnedDir, '*.md');

  if (learnedSkills.length > 0) {
    log(`[SessionStart] ${learnedSkills.length} learned skill(s) available in ${learnedDir}`);
  }

  // Detect project type and context
  const projectContext = getProjectContext();
  if (projectContext.detected) {
    log(`[SessionStart] Project: ${getProjectSummary()}`);

    // Show type-specific guidance
    if (projectContext.type === 'KOTLIN' || projectContext.type === 'JAVA') {
      const buildTool = projectContext.tools.buildTool;
      if (buildTool) {
        log(`[SessionStart] Build: ${buildTool.buildCmd} build | Test: ${buildTool.buildCmd} test`);
        if (projectContext.tools.formatter) {
          log(`[SessionStart] Format: ${buildTool.buildCmd} ktlintFormat`);
        }
      }
    } else if (projectContext.type === 'PYTHON') {
      const pm = projectContext.tools.packageManager;
      if (pm) {
        log(`[SessionStart] Install: ${pm.installCmd} | Test: pytest`);
        if (projectContext.tools.formatter) {
          log(`[SessionStart] Format: ${projectContext.tools.formatter} format .`);
        }
      }
    } else if (projectContext.type === 'NODE') {
      // Use existing package manager detection for Node projects
      const pm = getPackageManager();
      log(`[SessionStart] Package manager: ${pm.name} (${pm.source})`);

      // If package manager was detected via fallback, show selection prompt
      if (pm.source === 'fallback' || pm.source === 'default') {
        log('[SessionStart] No package manager preference found.');
        log(getSelectionPrompt());
      }
    }
  } else {
    // Fallback: try to detect Node.js package manager
    const pm = getPackageManager();
    log(`[SessionStart] Package manager: ${pm.name} (${pm.source})`);

    if (pm.source === 'fallback' || pm.source === 'default') {
      log('[SessionStart] No package manager preference found.');
      log(getSelectionPrompt());
    }
  }

  process.exit(0);
}

main().catch(err => {
  console.error('[SessionStart] Error:', err.message);
  process.exit(0); // Don't block on errors
});
