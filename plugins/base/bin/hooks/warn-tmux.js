// PreToolUse: warn when long-running commands run outside tmux.

if (!process.env.TMUX) {
  console.error('[Hook] Consider running in tmux for session persistence');
  console.error('[Hook] tmux new -s dev  |  tmux attach -t dev');
}
