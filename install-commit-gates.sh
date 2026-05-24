#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  cc-diary: Commit Gates for Claude Code                            ║
# ║  Enforces CHANGELOG.md and CLAUDE.md on every git commit.          ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# Usage:
#   bash install-commit-gates.sh            # install
#   bash install-commit-gates.sh --remove   # uninstall
#
# How it works:
#   PreToolUse hook blocks git commit until:
#   - CHANGELOG.md is staged (documents changes)
#   - CLAUDE.md is staged (captures workflow)
#   The LLM generates the content — the hook only gates.
#
# Dependencies: python3, git

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
SETTINGS="$CLAUDE_DIR/settings.json"

# ════════════════════════════════════════════════════════════════════════
# REMOVE
# ════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--remove" ]; then
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  cc-diary — removing commit gates                ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  rm -f "$HOOKS_DIR/pre-commit-gate.sh" && echo "[1/2] Hook removed" || echo "[1/2] Hook not found"

  if [ -f "$SETTINGS" ]; then
    python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
h = s.get('hooks',{})
pre = h.get('PreToolUse',[])
h['PreToolUse'] = [x for x in pre if 'pre-commit-gate' not in str(x)]
if not h['PreToolUse']: del h['PreToolUse']
with open('$SETTINGS','w') as f: json.dump(s,f,indent=2); f.write('\n')
" 2>/dev/null && echo "[2/2] PreToolUse hook removed from settings.json" || echo "[2/2] Could not update settings.json"
  else
    echo "[2/2] settings.json not found"
  fi

  echo ""
  echo "Commit gates removed."
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# INSTALL
# ════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════╗"
echo "║  cc-diary — commit gates installer               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

[ -d "$CLAUDE_DIR" ] || { echo "ERROR: $CLAUDE_DIR not found." >&2; exit 1; }
mkdir -p "$HOOKS_DIR"

# ── pre-commit-gate.sh ──────────────────────────────────────────────────
cat > "$HOOKS_DIR/pre-commit-gate.sh" << 'HOOKEOF'
#!/bin/bash
# pre-commit-gate.sh — PreToolUse hook for Bash
#
# Blocks `git commit` until CHANGELOG.md is staged. Reminds about CLAUDE.md
# workflow updates. The LLM agent does the actual content generation —
# this script only checks whether the work has been done.
#
# Compound-aware: handles `git add CHANGELOG.md && git commit ...` correctly
# by parsing all `git add` invocations in the same shell command and treating
# their arguments as "will be staged" alongside currently-staged files.
#
# Exit codes:
#   0 — proceed (all gates pass)
#   2 — block (tells Claude what to do before committing)

INPUT=$(cat)

# Use Python for robust command parsing — we need to split on shell separators
# and detect `git commit` invocations vs. mere substring occurrences.
# NB: pass INPUT via env var; a heredoc would shadow stdin and break json.load.
PARSE=$(GATE_INPUT="$INPUT" python3 - <<'PYEOF'
import os, sys, json, re, shlex

raw = os.environ.get('GATE_INPUT', '')
try:
    d = json.loads(raw) if raw else {}
except Exception:
    print("SKIP"); sys.exit(0)

cmd = d.get('tool_input', {}).get('command', '') or ''
session_cwd = d.get('cwd', '') or ''

# Split the compound command into segments on shell separators that imply
# sequencing or fan-out. Keep it simple: split on &&, ||, ;, | and newlines.
# (Pipes between processes don't typically chain `git add | git commit`, so
# treating | as a separator is fine for our purposes.)
parts = re.split(r'(?:\&\&|\|\||;|\||\n)', cmd)

# A segment is a "git commit" invocation if, after stripping leading
# whitespace and any `sudo`/`env VAR=…` noise, the next two tokens are
# `git` and `commit` (with optional `-C <dir>` between).
def is_git_commit(seg):
    seg = seg.strip()
    # Strip leading "sudo ", "env VAR=val ", etc.
    seg = re.sub(r'^(sudo\s+|env\s+\S+=\S+\s+)+', '', seg)
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        toks = seg.split()
    if not toks or toks[0] != 'git':
        return False
    # Skip git global flags (-C <dir>, -c key=val, --git-dir=…, --work-tree=…)
    i = 1
    while i < len(toks):
        t = toks[i]
        if t == '-C' and i + 1 < len(toks):
            i += 2; continue
        if t == '-c' and i + 1 < len(toks):
            i += 2; continue
        if t.startswith('--git-dir') or t.startswith('--work-tree'):
            i += 1; continue
        break
    return i < len(toks) and toks[i] == 'commit'

# Find the -C target (if any) in a git invocation, returns absolute path or empty.
def git_C_target(seg):
    seg = seg.strip()
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        return ''
    for i, t in enumerate(toks[:-1]):
        if t == 'git':
            j = i + 1
            while j < len(toks):
                if toks[j] == '-C' and j + 1 < len(toks):
                    return toks[j + 1]
                if toks[j].startswith('-'):
                    j += 1; continue
                break
    return ''

# Find a leading `cd <dir>` in the segment chain (affects cwd for subsequent
# segments). We track cwd as it would evolve through the compound.
def cd_target(seg):
    m = re.match(r'\s*cd\s+([^\s&;|]+)', seg)
    return m.group(1) if m else ''

# Collect files staged by `git add <files>` in any segment up to and including
# the first `git commit`. Returns a list of file patterns (relative to that
# segment's cwd) and the inferred repo root for the commit.
def parse_add_targets(seg):
    seg = seg.strip()
    try:
        toks = shlex.split(seg, posix=True)
    except ValueError:
        return []
    # Find `git [-C dir] add ...`
    if not toks or toks[0] != 'git':
        return []
    i = 1
    while i < len(toks):
        if toks[i] == '-C' and i + 1 < len(toks):
            i += 2; continue
        if toks[i] == '-c' and i + 1 < len(toks):
            i += 2; continue
        if toks[i].startswith('--git-dir') or toks[i].startswith('--work-tree'):
            i += 1; continue
        break
    if i >= len(toks) or toks[i] != 'add':
        return []
    # Args after `add`; skip flags
    files = []
    for t in toks[i+1:]:
        if t.startswith('-'):
            continue
        files.append(t)
    return files

# Walk parts in order. Maintain a running cwd. Stop at the first `git commit`.
import os
cwd = session_cwd
commit_repo_root = ''
will_stage = []  # raw paths from `git add` (relative to the cwd at that point)

for seg in parts:
    # Apply cd if this segment is a cd
    cd_t = cd_target(seg)
    if cd_t:
        cwd = cd_t if os.path.isabs(cd_t) else os.path.normpath(os.path.join(cwd or '.', cd_t))
        continue
    # Collect git add targets
    adds = parse_add_targets(seg)
    if adds:
        c = git_C_target(seg) or cwd
        c_abs = c if os.path.isabs(c) else os.path.normpath(os.path.join(cwd or '.', c))
        for f in adds:
            f_abs = f if os.path.isabs(f) else os.path.normpath(os.path.join(c_abs, f))
            will_stage.append(f_abs)
    # Detect commit
    if is_git_commit(seg):
        c = git_C_target(seg) or cwd
        commit_repo_root = c if os.path.isabs(c) else os.path.normpath(os.path.join(cwd or '.', c))
        break

if not commit_repo_root:
    print("SKIP")
    sys.exit(0)

# Output: REPO_ROOT_HINT and WILL_STAGE list (newline-separated)
print(f"REPO_ROOT_HINT={commit_repo_root}")
print(f"SESSION_CWD={session_cwd}")
for f in will_stage:
    print(f"WILL_STAGE={f}")
PYEOF
)

# If parser said SKIP, this isn't a real `git commit` invocation.
if [ "$PARSE" = "SKIP" ] || [ -z "$PARSE" ]; then
  exit 0
fi

REPO_ROOT_HINT=$(echo "$PARSE" | grep -E '^REPO_ROOT_HINT=' | head -1 | cut -d= -f2-)
SESSION_CWD=$(echo "$PARSE" | grep -E '^SESSION_CWD=' | head -1 | cut -d= -f2-)
WILL_STAGE=$(echo "$PARSE" | grep -E '^WILL_STAGE=' | cut -d= -f2-)

# Resolve repo root: try the parser's hint first, then session cwd, then runtime cwd.
REPO_ROOT=""
if [ -n "$REPO_ROOT_HINT" ] && [ -d "$REPO_ROOT_HINT" ]; then
  REPO_ROOT=$(cd "$REPO_ROOT_HINT" && git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [ -z "$REPO_ROOT" ] && [ -n "$SESSION_CWD" ] && [ -d "$SESSION_CWD" ]; then
  REPO_ROOT=$(cd "$SESSION_CWD" && git rev-parse --show-toplevel 2>/dev/null || echo "")
fi
if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
fi
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

# Helper: is `<name>.md` either staged OR about to be staged by an upcoming `git add` in the compound?
file_covered() {
  local needle="$1"
  # Currently staged
  if git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null | grep -q "$needle"; then
    return 0
  fi
  # Will be staged by `git add` in this compound. WILL_STAGE entries are
  # absolute paths; check basename match within REPO_ROOT.
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$(basename "$f")" = "$needle" ]; then
      return 0
    fi
    # Also handle `git add .` / `git add -A` / `git add <dir>` — if the path
    # is the repo root or a parent of the file, consider it covered when
    # that file would be picked up by the add (tracked-modified OR untracked).
    if [ -d "$f" ] || [ "$f" = "$REPO_ROOT" ] || [ "$f" = "." ]; then
      # Tracked-modified
      if git -C "$REPO_ROOT" diff --name-only 2>/dev/null | grep -q "$needle"; then
        return 0
      fi
      # Untracked
      if git -C "$REPO_ROOT" ls-files --others --exclude-standard 2>/dev/null | grep -q "$needle"; then
        return 0
      fi
    fi
  done <<< "$WILL_STAGE"
  return 1
}

ISSUES=""

# ── Gate 1: CHANGELOG.md must be staged (or will be) ─────────────────────
if file_covered "CHANGELOG.md"; then
  :
elif [ ! -f "$REPO_ROOT/CHANGELOG.md" ]; then
  ISSUES="${ISSUES}
CHANGELOG: No CHANGELOG.md exists. Create one at the project root with an entry for this change set."
else
  ISSUES="${ISSUES}
CHANGELOG: CHANGELOG.md exists but is not staged. Append an entry for this commit's changes, then 'git add CHANGELOG.md'."
fi

# ── Gate 2: CLAUDE.md workflow consideration ─────────────────────────────
if file_covered "CLAUDE.md"; then
  :
elif [ ! -f "$REPO_ROOT/CLAUDE.md" ]; then
  ISSUES="${ISSUES}
WORKFLOW: No CLAUDE.md exists. Compile the workflow observed in this session into CLAUDE.md (phases, steps, commands, directory structure), then 'git add CLAUDE.md'."
else
  LAST_COMMIT_TS=$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || echo "0")
  CLAUDE_MD_TS=$(stat -f %m "$REPO_ROOT/CLAUDE.md" 2>/dev/null || stat -c %Y "$REPO_ROOT/CLAUDE.md" 2>/dev/null || echo "0")
  if [ "$CLAUDE_MD_TS" -le "$LAST_COMMIT_TS" ] 2>/dev/null; then
    ISSUES="${ISSUES}
WORKFLOW: CLAUDE.md has not been updated since the last commit. Review if this session introduced new workflow steps, commands, or conventions that should be captured. If yes, update and 'git add CLAUDE.md'. If no new patterns, stage it as-is with a no-op touch or skip by staging a comment update."
  fi
fi

# ── Verdict ──────────────────────────────────────────────────────────────
if [ -n "$ISSUES" ]; then
  # Claude Code PreToolUse: when the hook exits 2 (block), the surfaced error
  # comes from stderr; stdout is ignored. Writing the block reason to stdout
  # caused "No stderr output" in the displayed error and lost the message.
  echo "PRE-COMMIT GATE: The following must be addressed before committing:" >&2
  echo "$ISSUES" >&2
  echo "" >&2
  echo "After addressing these, re-run the git commit command." >&2
  exit 2
fi

# Soft reminder (non-blocking): DECISIONS.md
if ! file_covered "DECISIONS.md"; then
  if [ ! -f "$REPO_ROOT/DECISIONS.md" ]; then
    echo "REMINDER (non-blocking): DECISIONS.md does not exist. If this commit involves a non-trivial design choice (architecture, rejected alternatives, threshold tuning), create one with an entry: change/why/rejected/branch. Skip if mechanical/chore/docs."
  else
    LAST_TS_D=$(git -C "$REPO_ROOT" log -1 --format=%ct 2>/dev/null || echo "0")
    DEC_TS=$(stat -f %m "$REPO_ROOT/DECISIONS.md" 2>/dev/null || stat -c %Y "$REPO_ROOT/DECISIONS.md" 2>/dev/null || echo "0")
    if [ "$DEC_TS" -le "$LAST_TS_D" ] 2>/dev/null; then
      echo "REMINDER (non-blocking): DECISIONS.md not updated since last commit. If this commit involves a non-trivial design choice, append an entry. Skip if mechanical/chore."
    fi
  fi
fi

exit 0

HOOKEOF
chmod +x "$HOOKS_DIR/pre-commit-gate.sh"
echo "[1/2] pre-commit-gate.sh installed"

# ── settings.json ───────────────────────────────────────────────────────
if [ -f "$SETTINGS" ]; then
  if grep -q "pre-commit-gate" "$SETTINGS" 2>/dev/null; then
    echo "[2/2] PreToolUse hook already in settings.json"
  else
    python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
h = s.setdefault('hooks',{}).setdefault('PreToolUse',[])
if not any('pre-commit-gate' in str(x) for x in h):
    h.append({'matcher':'Bash','hooks':[{'type':'command','command':'bash ~/.claude/hooks/pre-commit-gate.sh'}]})
with open('$SETTINGS','w') as f: json.dump(s,f,indent=2); f.write('\n')
print('[2/2] PreToolUse hook added to settings.json')
" 2>/dev/null || echo "[2/2] WARNING: Could not update settings.json"
  fi
else
  echo "[2/2] WARNING: $SETTINGS not found"
fi

echo ""
echo "Commit gates installed."
echo "Before every git commit, Claude must stage CHANGELOG.md + CLAUDE.md."
