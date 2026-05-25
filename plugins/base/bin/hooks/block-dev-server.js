// PreToolUse: block dev servers outside tmux so logs are accessible.

console.error('[Hook] BLOCKED: Dev server must run in tmux for log access');
console.error('[Hook] Use: tmux new-session -d -s dev "npm run dev"');
console.error('[Hook] Then: tmux attach -t dev');
process.exit(1);
