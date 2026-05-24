#!/bin/bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  cc-diary: Activity Diary for Claude Code                          ║
# ║  Installs activity logging, Qdrant embeddings, diary generation,   ║
# ║  PostToolUse hook, and /diary skill.                               ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# Usage:
#   bash install-diary.sh            # install
#   bash install-diary.sh --remove   # uninstall
#
# Dependencies: python3, curl, jq (recommended)
# Optional: Qdrant (localhost:6333), embedding service (localhost:1234)

set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks"
LOG_DIR="$CLAUDE_DIR/activity-log"
DIARY_DIR="$LOG_DIR/diary"
SKILL_DIR="$CLAUDE_DIR/skills/cc-diary"
SETTINGS="$CLAUDE_DIR/settings.json"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

EMBED_URL="${CC_DIARY_EMBED_URL:-http://localhost:1234/v1/embeddings}"
EMBED_MODEL="${CC_DIARY_EMBED_MODEL:-text-embedding-bge-m3}"
EMBED_DIMS="${CC_DIARY_EMBED_DIMS:-1024}"
QDRANT_URL="${CC_DIARY_QDRANT_URL:-http://localhost:6333}"
QDRANT_COLLECTION="${CC_DIARY_COLLECTION:-claude_activity}"

# ════════════════════════════════════════════════════════════════════════
# REMOVE
# ════════════════════════════════════════════════════════════════════════
if [ "${1:-}" = "--remove" ]; then
  echo "╔══════════════════════════════════════════════════╗"
  echo "║  cc-diary — removing activity diary              ║"
  echo "╚══════════════════════════════════════════════════╝"
  echo ""

  # Remove hooks
  rm -f "$HOOKS_DIR/post-commit-activity.sh" "$HOOKS_DIR/session-start-activity.sh" \
    && echo "[1/5] Hook scripts removed" || echo "[1/5] Hook scripts not found"

  # Remove skill
  rm -rf "$SKILL_DIR" && echo "[2/5] Skill removed" || echo "[2/5] Skill not found"

  # Remove hooks from settings.json
  if [ -f "$SETTINGS" ]; then
    python3 -c "
import json
with open('$SETTINGS') as f:
    s = json.load(f)
hooks = s.get('hooks', {})
for key, marker in (('PostToolUse','post-commit-activity'), ('SessionStart','session-start-activity')):
    arr = hooks.get(key, [])
    hooks[key] = [h for h in arr if marker not in str(h)]
    if not hooks[key]:
        hooks.pop(key, None)
with open('$SETTINGS', 'w') as f:
    json.dump(s, f, indent=2)
    f.write('\n')
" 2>/dev/null && echo "[3/5] PostToolUse + SessionStart hooks removed from settings.json" || echo "[3/5] Could not update settings.json"
  else
    echo "[3/5] settings.json not found"
  fi

  # Remove Activity Log section from CLAUDE.md
  if [ -f "$CLAUDE_MD" ] && grep -q "## Activity Log" "$CLAUDE_MD" 2>/dev/null; then
    python3 -c "
from pathlib import Path
p = Path('$CLAUDE_MD')
lines = p.read_text().splitlines()
start = next((i for i, l in enumerate(lines) if l.strip() == '## Activity Log (Always Active)'), None)
if start is not None:
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ') or lines[i].startswith('---')), len(lines))
    # Remove blank lines before section too
    while start > 0 and not lines[start - 1].strip():
        start -= 1
    del lines[start:end]
    p.write_text('\n'.join(lines) + '\n')
" 2>/dev/null && echo "[4/5] Activity Log section removed from CLAUDE.md" || echo "[4/5] Could not update CLAUDE.md"
  else
    echo "[4/5] No Activity Log section in CLAUDE.md"
  fi

  # Activity data — ask before deleting
  if [ -d "$LOG_DIR" ]; then
    ENTRY_COUNT=$(wc -l < "$LOG_DIR/entries.jsonl" 2>/dev/null || echo "0")
    echo ""
    echo "Activity data ($ENTRY_COUNT entries) at: $LOG_DIR"
    echo "  To delete: rm -rf $LOG_DIR"
    echo "  To delete Qdrant collection: curl -X DELETE $QDRANT_URL/collections/$QDRANT_COLLECTION"
    echo "[5/5] Activity data preserved (delete manually if desired)"
  else
    echo "[5/5] No activity data found"
  fi

  echo ""
  echo "cc-diary removed. Activity data preserved."
  exit 0
fi

# ════════════════════════════════════════════════════════════════════════
# INSTALL
# ════════════════════════════════════════════════════════════════════════
echo "╔══════════════════════════════════════════════════╗"
echo "║  cc-diary installer                              ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

[ -d "$CLAUDE_DIR" ] || { echo "ERROR: $CLAUDE_DIR not found. Is Claude Code installed?" >&2; exit 1; }
command -v python3 &>/dev/null || { echo "ERROR: python3 required" >&2; exit 1; }

mkdir -p "$HOOKS_DIR" "$LOG_DIR" "$DIARY_DIR" "$SKILL_DIR"
echo "[1/9] Directories created"

# ── embed-entry.py ──────────────────────────────────────────────────────
cat > "$LOG_DIR/embed-entry.py" << 'PYEOF'
#!/usr/bin/env python3
"""Embed an activity entry and upsert to Qdrant.

Usage: echo '{"summary":"..."}' | python3 embed-entry.py

Env vars: CC_DIARY_EMBED_URL, CC_DIARY_EMBED_MODEL, CC_DIARY_QDRANT_URL, CC_DIARY_COLLECTION
"""
import hashlib, json, os, sys, urllib.request

EMBED_URL = os.environ.get("CC_DIARY_EMBED_URL", "http://localhost:1234/v1/embeddings")
EMBED_MODEL = os.environ.get("CC_DIARY_EMBED_MODEL", "text-embedding-bge-m3")
QDRANT_URL = os.environ.get("CC_DIARY_QDRANT_URL", "http://localhost:6333")
COLLECTION = os.environ.get("CC_DIARY_COLLECTION", "claude_activity")

def embed(text):
    req = urllib.request.Request(EMBED_URL, data=json.dumps({"input": text, "model": EMBED_MODEL}).encode(), headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r: return json.loads(r.read())["data"][0]["embedding"]

def upsert(pid, vec, payload):
    iid = int(hashlib.sha256(pid.encode()).hexdigest()[:15], 16)
    req = urllib.request.Request(f"{QDRANT_URL}/collections/{COLLECTION}/points", data=json.dumps({"points":[{"id":iid,"vector":vec,"payload":payload}]}).encode(), headers={"Content-Type":"application/json"}, method="PUT")
    with urllib.request.urlopen(req, timeout=10) as r: return json.loads(r.read())

def main():
    entry = json.loads(sys.stdin.read())
    parts = [entry.get("summary", "")]
    ns = entry.get("next_steps", [])
    if ns: parts.append("Next: " + "; ".join(ns))
    text = " ".join(parts)
    if not text.strip(): print("No text to embed, skipping", file=sys.stderr); sys.exit(0)
    try:
        vec = embed(text)
        pid = f"{entry.get('project','unknown')}-{entry.get('commit', entry.get('ts','unknown'))}"
        upsert(pid, vec, entry); print(f"Embedded: {pid} ({len(vec)}d)")
    except Exception as e: print(f"Embed skipped (service unavailable): {e}", file=sys.stderr)

if __name__ == "__main__": main()
PYEOF
chmod +x "$LOG_DIR/embed-entry.py"
echo "[2/9] embed-entry.py installed"

# ── generate-diary.py ───────────────────────────────────────────────────
cat > "$LOG_DIR/generate-diary.py" << 'PYEOF'
#!/usr/bin/env python3
"""Generate daily diary from activity log.

Usage: python3 generate-diary.py [YYYY-MM-DD | --week | --stale N]
"""
import json, sys
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path

LOG_DIR = Path.home() / ".claude" / "activity-log"
ENTRIES = LOG_DIR / "entries.jsonl"
DIARY = LOG_DIR / "diary"

def load():
    if not ENTRIES.exists(): return []
    out = []
    for l in ENTRIES.read_text().splitlines():
        l = l.strip()
        if l:
            try: out.append(json.loads(l))
            except: pass
    return out

def for_date(entries, d): return [e for e in entries if e.get("date") == d]

def diary_md(date, entries):
    lines = [f"# Activity Diary — {date}", ""]
    if not entries: lines.append("*No activity recorded.*"); return "\n".join(lines)
    by_proj = defaultdict(list)
    for e in entries: by_proj[e.get("project","unknown")].append(e)
    lines += [f"**Projects**: {', '.join(by_proj.keys())}", f"**Commits**: {sum(1 for e in entries if e.get('type')=='commit')}  |  **Sessions**: {sum(1 for e in entries if e.get('type')=='session_start')}", ""]
    for proj, pe in sorted(by_proj.items()):
        lines += [f"## {proj}", ""]
        for e in sorted(pe, key=lambda x: x.get("ts","")):
            t, ts = e.get("type","?"), e.get("ts","")
            try: tm = datetime.fromisoformat(ts.replace("Z","+00:00")).astimezone().strftime("%H:%M")
            except Exception: tm = ts[11:16] if len(ts) >= 16 else ts
            if t == "session_start":
                lines.append(f"- **{tm}** Session started")
                if e.get("intent"): lines.append(f"  - Intent: {e['intent']}")
            elif t == "session_end":
                lines.append(f"- **{tm}** Session ended")
                if e.get("summary"): lines.append(f"  - {e['summary']}")
            elif t == "commit":
                ic = {"completed":"+","in-progress":"~","blocked":"!"}.get(e.get("status",""),"?")
                lines.append(f"- **{tm}** [{ic}] `{e.get('commit','?')}` {e.get('message','')}")
                if e.get("summary"): lines.append(f"  - {e['summary']}")
                for s in e.get("next_steps",[]): lines.append(f"  - [ ] {s}")
        lines.append("")
    att = [e for e in entries if e.get("status") in ("blocked","in-progress")]
    if att:
        lines += ["## Needs Attention", ""]
        for e in att:
            ic = "!!!" if e.get("status") == "blocked" else "..."
            lines.append(f"- {ic} **{e.get('project')}**: {e.get('summary', e.get('message','?'))}")
            if e.get("blocked_by"): lines.append(f"  - Blocked by: {e['blocked_by']}")
        lines.append("")
    return "\n".join(lines)

def stale(entries, days):
    cutoff = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d")
    latest = {}
    for e in entries:
        p, d = e.get("project","?"), e.get("date","")
        if d > latest.get(p,""): latest[p] = d
    lines = [f"# Stale Projects (>{days} days)", ""]
    s = {p:d for p,d in latest.items() if d < cutoff}
    if not s: lines.append("*No stale projects.*")
    else:
        for p,d in sorted(s.items(), key=lambda x:x[1]):
            lines.append(f"- **{p}** — last activity {d} ({(datetime.now()-datetime.strptime(d,'%Y-%m-%d')).days} days ago)")
    return "\n".join(lines)

def main():
    args, entries = sys.argv[1:], load()
    if "--stale" in args:
        d = int(args[args.index("--stale")+1]) if len(args)>args.index("--stale")+1 else 7
        print(stale(entries, d)); return
    if "--week" in args:
        today = datetime.now(); start = today - timedelta(days=today.weekday())
        for i in range(7):
            d = (start+timedelta(days=i)).strftime("%Y-%m-%d"); de = for_date(entries,d)
            if de: (DIARY/f"{d}.md").write_text(diary_md(d,de)); print(f"  {d}: {len(de)} entries")
        return
    d = args[0] if args else datetime.now().strftime("%Y-%m-%d")
    de = for_date(entries,d); md = diary_md(d,de)
    (DIARY/f"{d}.md").write_text(md); print(md); print(f"\n→ {DIARY/f'{d}.md'}")

if __name__ == "__main__": main()
PYEOF
chmod +x "$LOG_DIR/generate-diary.py"
echo "[3/9] generate-diary.py installed"

# ── post-commit-activity.sh hook ────────────────────────────────────────
cat > "$HOOKS_DIR/post-commit-activity.sh" << 'HOOKEOF'
#!/bin/bash
# post-commit-activity.sh — PostToolUse hook for Bash
#
# Writes a commit entry to entries.jsonl DIRECTLY (no Claude-in-the-loop).
# Rationale (2026-05-14): PostToolUse hook stdout does not reliably surface
# in the Bash tool result, so the prior "print instructions and trust Claude
# to follow them" design captured 0 of ~25 real commits over 13 days. Now
# the hook does the work: parses commit metadata from the tool output,
# appends a minimal JSON entry with `auto:true` and `source:"hook"`,
# embeds it via embed-entry.py, and regenerates today's diary. Summary is
# the commit subject (no LLM enrichment) — trades richness for reliability.
#
# Detects commits from tool OUTPUT, not the command string, so it handles:
#   - cd <dir> && git commit (CWD mismatch)
#   - bash script.sh (indirect commits)
#   - git -C <dir> commit (cross-repo commits)

INPUT=$(cat)
LOG_DIR="$HOME/.claude/activity-log"
ENTRIES="$LOG_DIR/entries.jsonl"

# Parse the entire input + emit one JSON entry line, OR exit silently.
# Doing this in one Python block avoids a chain of shell pipelines.
ENTRY=$(INPUT="$INPUT" python3 - <<'PYEOF'
import os, sys, json, re, subprocess
from datetime import datetime, timezone

try:
    d = json.loads(os.environ.get('INPUT', '') or '{}')
except Exception:
    sys.exit(0)

out = (d.get('tool_response', {}) or {}).get('stdout') \
   or (d.get('tool_result', {}) or {}).get('stdout', '') \
   or ''

# Quick filter: must look like a git commit output
if not re.search(r'^\[.+ [a-f0-9]{7,}\]|files? changed.*insertion|create mode', out, re.M):
    sys.exit(0)

# Parse "[branch hash] subject" — first such line wins (skip merge headers etc.)
m = re.search(r'^\[([^ ]+) ([a-f0-9]{7,})\] (.+)$', out, re.M)
if not m:
    sys.exit(0)
branch, commit_hash, subject = m.group(1), m.group(2), m.group(3).strip()

# diff_stat line, if present
stat_m = re.search(r'(\d+ files? changed[^\n]*)', out)
diff_stat = stat_m.group(1) if stat_m else ''

# Resolve repo root: prefer session cwd from payload, then cd <dir> in the
# command, then the hook's own CWD as last resort.
session_cwd = d.get('cwd', '') or ''
cmd = (d.get('tool_input', {}) or {}).get('command', '') or ''

def repo_root_of(path):
    """Return the working-tree root for `path` (worktree root for worktrees)."""
    try:
        r = subprocess.run(['git', '-C', path, 'rev-parse', '--show-toplevel'],
                           capture_output=True, text=True, timeout=2)
        return r.stdout.strip() if r.returncode == 0 else ''
    except Exception:
        return ''

def real_repo_root_of(path):
    """Return the *main* repo root, unwrapping worktrees.

    Uses `git rev-parse --git-common-dir`, which returns the path to the
    shared `.git` directory (the main repo's .git) regardless of whether
    `path` is in a worktree or the main checkout. The repo root is its
    parent.
    """
    try:
        r = subprocess.run(['git', '-C', path, 'rev-parse', '--git-common-dir'],
                           capture_output=True, text=True, timeout=2)
        if r.returncode != 0:
            return ''
        common = r.stdout.strip()
        if not common:
            return ''
        # `--git-common-dir` may return a path relative to `path`; resolve it.
        if not os.path.isabs(common):
            common = os.path.normpath(os.path.join(path, common))
        return os.path.normpath(os.path.join(common, os.pardir))
    except Exception:
        return ''

# First find any git-aware directory we can ask, then unwrap worktree → repo.
candidate = session_cwd if session_cwd and os.path.isdir(session_cwd) else ''
if not candidate:
    gc = re.search(r'git\s+-C\s+(\S+)', cmd)
    if gc and os.path.isdir(gc.group(1)):
        candidate = gc.group(1)
if not candidate:
    cds = re.findall(r'\bcd\s+([^\s&;|]+)', cmd)
    for cd in reversed(cds):
        if os.path.isdir(cd):
            candidate = cd
            break
if not candidate:
    candidate = os.getcwd()

# Worktree-aware: unwrap to the main repo root. Fall back to the worktree
# root if the unwrap fails for any reason.
repo_root = real_repo_root_of(candidate) or repo_root_of(candidate) or candidate
project = os.path.basename(repo_root) or 'unknown'
now = datetime.now(timezone.utc)

# Dedup: skip if (project, commit, type=commit) already exists. The hook
# may fire on amends, rebases, or accidental re-invocations; we want one
# entry per logical commit.
entries_path = os.path.expanduser('~/.claude/activity-log/entries.jsonl')
if os.path.exists(entries_path):
    needle_proj = f'"project": "{project}"'
    needle_commit = f'"commit": "{commit_hash}"'
    needle_type = '"type": "commit"'
    with open(entries_path, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if needle_proj in line and needle_commit in line and needle_type in line:
                # Already logged — exit without printing (caller skips append).
                sys.exit(0)

entry = {
    'ts': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'date': now.astimezone().strftime('%Y-%m-%d'),  # local date for diary grouping
    'type': 'commit',
    'project': project,
    'cwd': repo_root,
    'branch': branch,
    'commit': commit_hash,
    'message': subject,
    'diff_stat': diff_stat,
    'summary': subject,  # commit subject IS the summary (no LLM)
    'status': 'completed',
    'tags': [],
    'next_steps': [],
    'blocked_by': None,
    'source': 'hook',
    'auto': True,
}
print(json.dumps(entry, ensure_ascii=False))
PYEOF
)

# If Python printed nothing, this wasn't a commit — exit silently.
[ -z "$ENTRY" ] && exit 0

# Append + embed + regenerate. Best-effort; any failure is logged but
# does not propagate (a hook should never make the user's tool call fail).
mkdir -p "$LOG_DIR"
{
  echo "$ENTRY" >> "$ENTRIES"
  echo "$ENTRY" | python3 "$LOG_DIR/embed-entry.py" 2>/dev/null || true
  python3 "$LOG_DIR/generate-diary.py" >/dev/null 2>&1 || true
} 2>>"$LOG_DIR/hook.log"

# Informational note on stdout — Claude may or may not see it, but it's a
# useful trail when manually inspecting hook behaviour.
PROJ=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('project',''))" 2>/dev/null)
HASH=$(echo "$ENTRY" | python3 -c "import json,sys; print(json.load(sys.stdin).get('commit',''))" 2>/dev/null)
echo "[cc-diary] captured commit $HASH in $PROJ"
exit 0
HOOKEOF
chmod +x "$HOOKS_DIR/post-commit-activity.sh"
echo "[4/9] post-commit-activity.sh installed"

# ── session-start-activity.sh hook ──────────────────────────────────────
cat > "$HOOKS_DIR/session-start-activity.sh" << 'HOOKEOF'
#!/bin/bash
# session-start-activity.sh — SessionStart hook
# Auto-appends a stub session_start entry. Skips embedding (stub has no
# substantive content). Filters by hook source: only logs genuine new
# work sessions (startup, clear). Subagents do not trigger SessionStart,
# but resume/compact are continuations and should be skipped.
INPUT=$(cat)
SOURCE=$(echo "$INPUT" | python3 -c "import sys,json
try: print(json.load(sys.stdin).get('source',''))
except: print('')" 2>/dev/null)
case "$SOURCE" in startup|clear) ;; *) exit 0 ;; esac
CWD=$(pwd)
LOG="$HOME/.claude/activity-log/entries.jsonl"
[ -d "$(dirname "$LOG")" ] || exit 0
# Resolve real repo root (unwrap worktrees) and dedup against same-day entries.
SOURCE="$SOURCE" CWD="$CWD" LOG="$LOG" python3 - <<'PYEOF' 2>/dev/null
import json, os, subprocess
from datetime import datetime, timezone

cwd = os.environ.get('CWD', os.getcwd())
src = os.environ.get('SOURCE', '')
log = os.environ.get('LOG', '')

def real_repo_root(path):
    try:
        r = subprocess.run(['git', '-C', path, 'rev-parse', '--git-common-dir'],
                           capture_output=True, text=True, timeout=2)
        if r.returncode != 0:
            return ''
        common = r.stdout.strip()
        if not common:
            return ''
        if not os.path.isabs(common):
            common = os.path.normpath(os.path.join(path, common))
        return os.path.normpath(os.path.join(common, os.pardir))
    except Exception:
        return ''

repo_root = real_repo_root(cwd) or cwd
project = os.path.basename(repo_root) or 'unknown'
now = datetime.now(timezone.utc)
date = now.astimezone().strftime('%Y-%m-%d')

# Dedup: one session_start per (project, date). Keeps the first; later
# starts on the same day for the same project are noise.
if os.path.exists(log):
    needle_p = f'"project": "{project}"'
    needle_d = f'"date": "{date}"'
    needle_t = '"type": "session_start"'
    with open(log, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
            if needle_p in line and needle_d in line and needle_t in line:
                raise SystemExit(0)

entry = {
    'ts': now.strftime('%Y-%m-%dT%H:%M:%SZ'),
    'date': date,
    'type': 'session_start',
    'project': project,
    'cwd': repo_root,
    'intent': '',
    'source': src,
    'tags': [],
}
with open(log, 'a', encoding='utf-8') as f:
    f.write(json.dumps(entry) + '\n')
PYEOF
exit 0
HOOKEOF
chmod +x "$HOOKS_DIR/session-start-activity.sh"
echo "[5/9] session-start-activity.sh installed"

# ── /diary skill ────────────────────────────────────────────────────────
cat > "$SKILL_DIR/SKILL.md" << SKILLEOF
---
name: diary
description: >
  View activity diary, search past work, detect stale projects, and get weekly insights.
  Use when: "show diary", "what did I do", "stale projects", "activity log",
  "weekly summary", "search my work", "/diary".
---

# Activity Diary

Query and manage the central activity log at \`~/.claude/activity-log/entries.jsonl\`.

## Commands

Parse the user's input to determine which command to run:

### Today's Diary (default)
Trigger: \`/diary\`, "show diary", "what did I do today"

\`\`\`bash
python3 ~/.claude/activity-log/generate-diary.py
\`\`\`

### Specific Date
Trigger: \`/diary 2026-04-28\`, "diary for Monday", "what did I do on <date>"

Convert relative dates (Monday, yesterday, last Friday) to YYYY-MM-DD format.

\`\`\`bash
python3 ~/.claude/activity-log/generate-diary.py <YYYY-MM-DD>
\`\`\`

### This Week
Trigger: \`/diary week\`, "weekly summary", "this week"

\`\`\`bash
python3 ~/.claude/activity-log/generate-diary.py --week
\`\`\`

Then read each generated diary file and present a combined summary.

### Stale Projects
Trigger: \`/diary stale\`, "stale projects", "what needs attention", "forgotten projects"

\`\`\`bash
python3 ~/.claude/activity-log/generate-diary.py --stale 7
\`\`\`

### Semantic Search
Trigger: \`/diary search <query>\`, "find my work on <topic>", "when did I work on <thing>"

\`\`\`python
python3 -c "
import json, urllib.request

query = '<USER_QUERY>'
# Embed
req = urllib.request.Request(
    '${EMBED_URL}',
    data=json.dumps({'input': query, 'model': '${EMBED_MODEL}'}).encode(),
    headers={'Content-Type': 'application/json'},
)
with urllib.request.urlopen(req) as resp:
    vector = json.loads(resp.read())['data'][0]['embedding']

# Search Qdrant
req = urllib.request.Request(
    '${QDRANT_URL}/collections/${QDRANT_COLLECTION}/points/search',
    data=json.dumps({'vector': vector, 'limit': 10, 'with_payload': True}).encode(),
    headers={'Content-Type': 'application/json'},
)
with urllib.request.urlopen(req) as resp:
    results = json.loads(resp.read())

for r in results.get('result', []):
    p = r['payload']
    print(f'[{r[\"score\"]:.2f}] {p.get(\"date\",\"?\")} {p.get(\"project\",\"?\")} — {p.get(\"summary\",p.get(\"message\",\"?\"))}')
"
\`\`\`

Present results as a table. If Qdrant is unavailable, fall back to grep on the JSONL:

\`\`\`bash
grep -i '<keyword>' ~/.claude/activity-log/entries.jsonl | python3 -c "
import json,sys
for line in sys.stdin:
    e=json.loads(line.strip())
    print(f'{e.get(\"date\",\"?\")} {e.get(\"project\",\"?\")} — {e.get(\"summary\",e.get(\"message\",\"?\"))}')
"
\`\`\`

### Insights
Trigger: \`/diary insights\`, "analyze my activity", "what patterns do you see"

Read the full JSONL, then analyze:

\`\`\`bash
cat ~/.claude/activity-log/entries.jsonl
\`\`\`

Provide analysis covering:
1. **Time allocation** — commits per project this week/month
2. **Stuck work** — entries with \`status=blocked\` or repeated \`next_steps\` across commits
3. **Completion rate** — ratio of completed vs in-progress
4. **Attention needed** — projects with \`next_steps\` that have no follow-up commit
5. **Patterns** — recurring tags, busiest days, session duration estimates

### Stats
Trigger: \`/diary stats\`, "activity stats"

Quick counts from the JSONL:

\`\`\`bash
python3 -c "
import json
from collections import Counter
from pathlib import Path

entries = [json.loads(l) for l in Path.home().joinpath('.claude/activity-log/entries.jsonl').read_text().splitlines() if l.strip()]
print(f'Total entries: {len(entries)}')
print(f'  session_start: {sum(1 for e in entries if e.get(\"type\")==\"session_start\")}')
print(f'  commit:        {sum(1 for e in entries if e.get(\"type\")==\"commit\")}')
print(f'  session_end:   {sum(1 for e in entries if e.get(\"type\")==\"session_end\")}')
print(f'Projects: {len(set(e.get(\"project\",\"?\") for e in entries))}')
dates = sorted(set(e.get('date','') for e in entries))
print(f'Date range: {dates[0] if dates else \"?\"} → {dates[-1] if dates else \"?\"}')
by_proj = Counter(e.get('project','?') for e in entries if e.get('type')=='commit')
print('Top projects:')
for proj,ct in by_proj.most_common(5):
    print(f'  {proj}: {ct} commits')
"
\`\`\`
SKILLEOF
echo "[6/9] /diary skill installed"

# ── settings.json — PostToolUse + SessionStart hooks ────────────────────
if [ -f "$SETTINGS" ]; then
  python3 -c "
import json
with open('$SETTINGS') as f: s = json.load(f)
hooks = s.setdefault('hooks',{})
post = hooks.setdefault('PostToolUse',[])
if not any('post-commit-activity' in str(x) for x in post):
    post.append({'matcher':'Bash','hooks':[{'type':'command','command':'bash ~/.claude/hooks/post-commit-activity.sh'}]})
    print('[7/9] PostToolUse hook added')
else:
    print('[7/9] PostToolUse hook already present')
ss = hooks.setdefault('SessionStart',[])
if not any('session-start-activity' in str(x) for x in ss):
    ss.append({'matcher':'','hooks':[{'type':'command','command':'bash ~/.claude/hooks/session-start-activity.sh'}]})
    print('[8/9] SessionStart hook added')
else:
    print('[8/9] SessionStart hook already present')
with open('$SETTINGS','w') as f: json.dump(s,f,indent=2); f.write('\n')
" 2>/dev/null || echo "[7-8/9] WARNING: Could not update settings.json"
else
  echo "[7-8/9] WARNING: $SETTINGS not found"
fi

# ── CLAUDE.md — Activity Log section ────────────────────────────────────
if [ -f "$CLAUDE_MD" ] && grep -q "Activity Log" "$CLAUDE_MD" 2>/dev/null; then
  echo "[9/9] Activity Log section already in CLAUDE.md"
else
  cat >> "$CLAUDE_MD" << 'MDEOF'

## Activity Log (Always Active)

Central activity diary at `~/.claude/activity-log/entries.jsonl`. JSONL, append-only.

### Session Start
At session start, append a `session_start` entry:
```bash
echo '{"ts":"<ISO>","date":"<YYYY-MM-DD>","type":"session_start","project":"<basename of cwd>","cwd":"<cwd>","intent":"<what user wants>","tags":[]}' >> ~/.claude/activity-log/entries.jsonl
```
Then embed: `echo '<json>' | python3 ~/.claude/activity-log/embed-entry.py`

### On Commit (automated via PostToolUse hook)
The hook fires after `git commit`. Follow its instructions:
1. Append `commit` entry with LLM-generated summary, status, next_steps
2. Embed via `embed-entry.py`
3. Regenerate diary: `python3 ~/.claude/activity-log/generate-diary.py`

### Session End
When user says "done" or ends work, append `session_end` entry:
```bash
echo '{"ts":"<ISO>","date":"<YYYY-MM-DD>","type":"session_end","project":"<proj>","cwd":"<cwd>","summary":"<accomplished>","status":"<completed|in-progress|blocked>","next_steps":[]}' >> ~/.claude/activity-log/entries.jsonl
```

### Diary Commands
| Command | Purpose |
|---------|---------|
| `/diary` | Today's diary |
| `/diary week` | This week |
| `/diary stale` | Projects idle >7 days |
| `/diary search <query>` | Semantic search (Qdrant) |
| `/diary insights` | Pattern analysis |
| `/diary stats` | Quick counts |
MDEOF
  echo "[9/9] Activity Log section appended to CLAUDE.md"
fi

# ── Qdrant collection (optional) ────────────────────────────────────────
if curl -s "$QDRANT_URL/collections/$QDRANT_COLLECTION" 2>/dev/null | python3 -c "import json,sys; sys.exit(0 if json.load(sys.stdin).get('result') else 1)" 2>/dev/null; then
  echo "[ok] Qdrant collection '$QDRANT_COLLECTION' exists"
elif curl -s "$QDRANT_URL/collections" &>/dev/null; then
  curl -s -X PUT "$QDRANT_URL/collections/$QDRANT_COLLECTION" -H "Content-Type: application/json" -d "{\"vectors\":{\"size\":$EMBED_DIMS,\"distance\":\"Cosine\"}}" &>/dev/null
  echo "[ok] Qdrant collection created ($EMBED_DIMS dims)"
else
  echo "[--] Qdrant not running — semantic search unavailable until started"
fi

touch "$LOG_DIR/entries.jsonl"

echo ""
echo "cc-diary installed. Use /diary to query your activity log."
