#!/usr/bin/env bash
# End-to-end suite for sidekick-zen.nvim.
#
# These tests need a REAL terminal, not `nvim --headless`: neovim sizes a
# terminal's PTY to the smallest window showing its buffer, and that sizing is
# the invariant the plugin exists to protect. So we run neovim inside tmux at a
# fixed size and drive it over its RPC socket.
#
# Usage:  tests/run.sh [spec-name-substring]
# Needs:  nvim, tmux, git

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="zenspec-$$"
# macOS caps unix socket paths near 104 chars, so keep this short.
SOCK="$(mktemp -u /tmp/zs-XXXXXX).sock"
FIXTURES="$(mktemp -d /tmp/zsfix-XXXXXX)"
COLS=200
ROWS=50
FILTER="${1:-}"

for bin in nvim tmux git; do
  command -v "$bin" >/dev/null || { echo "missing dependency: $bin" >&2; exit 2; }
done

cleanup() {
  tmux kill-session -t "$SESSION" 2>/dev/null
  rm -rf "$SOCK" "$FIXTURES"
}
trap cleanup EXIT

for name in alpha beta; do
  awk -v n="$name" 'BEGIN { for (i = 1; i <= 300; i++) print n " line " i }' > "$FIXTURES/$name.txt"
done

# Pre-clone dependencies before the timed run so the first spec isn't racing a
# network fetch.
nvim --headless -u "$ROOT/tests/minimal_init.lua" -c "qa!" >/dev/null 2>&1

tmux new-session -d -s "$SESSION" -x "$COLS" -y "$ROWS" \
  "cd $FIXTURES && ZEN_FIXTURES=$FIXTURES nvim --listen $SOCK -u $ROOT/tests/minimal_init.lua alpha.txt"

for _ in $(seq 1 60); do
  [ -S "$SOCK" ] && nvim --server "$SOCK" --remote-expr "1" >/dev/null 2>&1 && break
  sleep 0.5
done
[ -S "$SOCK" ] || { echo "neovim did not start" >&2; exit 2; }

rpc() { timeout 120 nvim --server "$SOCK" --remote-expr "$1" 2>&1; }
run_lua() { rpc "luaeval('dofile(_A)', '$1')"; }
resize() { tmux resize-window -t "$SESSION" -x "$1" -y "$2"; sleep 1.5; }

run_lua "$ROOT/tests/helpers.lua" >/dev/null

failed=0
total=0
for spec in "$ROOT"/tests/specs/*.lua; do
  name="$(basename "$spec" .lua)"
  [ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue

  # 07 asserts the narrow-editor clamp and deliberately leaves zen open so 08
  # can assert what VimResized did to it.
  case "$name" in
    07_narrow) resize 84 40 ;;
    08_resized) resize "$COLS" "$ROWS" ;;
  esac

  out="$(run_lua "$spec")"
  total=$((total + 1))
  if [ "${out%%$'\n'*}" = "ALL PASS" ]; then
    echo "ok   $name"
  else
    failed=$((failed + 1))
    echo "FAIL $name"
    echo "$out" | sed 's/^/     /'
  fi
done

# One pass with real keystrokes: RPC cannot reproduce terminal-mode entry, so
# only tmux can prove <C-l> lands you typing in the CLI.
if [ -z "$FILTER" ]; then
  total=$((total + 1))
  run_lua "$ROOT/tests/keys_setup.lua" >/dev/null
  tmux send-keys -t "$SESSION" Escape; sleep 0.4
  tmux send-keys -t "$SESSION" C-l; sleep 1.5
  mode_cli="$(rpc 'mode(1)')"
  tmux send-keys -t "$SESSION" C-h; sleep 1.5
  mode_code="$(rpc 'mode(1)')"
  on_code="$(rpc "luaeval('tostring(_G.H.cur() == _G.H.code_win())')")"
  tmux send-keys -t "$SESSION" q; sleep 1.5
  left="$(rpc "luaeval('#_G.H.zen_floats()')")"
  if [ "$mode_cli" = "t" ] && [ "$mode_code" = "n" ] && [ "$on_code" = "true" ] && [ "$left" = "0" ]; then
    echo "ok   real_keystrokes"
  else
    failed=$((failed + 1))
    echo "FAIL real_keystrokes"
    echo "     <C-l> mode=$mode_cli (want t)   <C-h> mode=$mode_code (want n) on_code=$on_code   after q floats=$left (want 0)"
  fi
fi

echo
if [ "$failed" -eq 0 ]; then
  echo "all $total spec(s) passed"
else
  echo "$failed of $total spec(s) failed"
fi
exit $([ "$failed" -eq 0 ] && echo 0 || echo 1)
