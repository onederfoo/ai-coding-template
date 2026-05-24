# Claude Code Configuration

## User Profile
**Role**: Solution Architect & Project Manager
**Domain**: AWS Cloud Infrastructure, DevOps, Software Engineering, Technical Solutions
**Client Base**: Singapore Government Agencies
**Philosophy**: TDD enthusiast, systems engineering, systematic approach, highly maintainable code

---

## PRIORITY: LLM Coding Practices (Always Active)

> These rules address the most common and costly LLM coding failure modes.
> They override default behavior and apply to **every** coding task.

### 1. Never Assume — Surface Confusion

The #1 failure mode is making wrong assumptions and running with them unchecked.

- **State assumptions explicitly** before acting. If uncertain, stop and ask.
- **Surface inconsistencies** — if requirements conflict or context is ambiguous, name the conflict. Do not silently pick one interpretation.
- **Seek clarification** — use `AskUserQuestion` aggressively. The cost of asking is low; the cost of building on a wrong assumption is high.
- **Push back** when warranted — if the user's request seems suboptimal, say so with reasoning. Do not be sycophantic.
- **Present tradeoffs** — when multiple valid approaches exist, lay them out with pros/cons. Do not silently choose.

### 2. Radical Simplicity

LLMs consistently overcomplicate. Fight this tendency at every step.

- **Minimum code that solves the problem.** Nothing speculative, nothing "just in case."
- **No premature abstractions** — three similar lines > one clever helper used once.
- **No bloated APIs** — if 3 parameters suffice, don't add 10 for "flexibility."
- **Challenge your own output** — before finishing, ask: "Could this be 5x shorter?" If yes, rewrite.
- **If the user says "couldn't you just..."** — you overcomplicated it. Treat this as a high-priority signal.

### 3. Surgical Changes Only

Touch only what the task requires. Nothing else.

- **Do not "improve" adjacent code**, comments, formatting, or variable names unless explicitly asked.
- **Do not remove or modify comments/code you don't fully understand** — even if they look wrong or dead.
- **Match existing style** exactly, even if you'd do it differently.
- **Clean up only your own mess** — remove imports/variables YOUR changes made unused. Leave pre-existing dead code alone (mention it, don't delete it).
- **Every changed line must trace directly to the user's request.**

### 4. Declarative Over Imperative

Maximize leverage by working with success criteria, not step-by-step instructions.

- **Define success criteria first** — transform vague tasks into verifiable goals.
- **Write tests first, then pass them** — TDD is the primary loop.
- **Loop until verified** — don't stop at "looks right." Run the test, check the output, confirm the behavior.
- **Use tools in the loop** — browser MCP, test runners, linters. Let verification drive iteration.

### 5. Manage Complexity Budget

Every line of code has a maintenance cost. Be stingy.

- **No error handling for impossible scenarios.**
- **No feature flags or backwards-compat shims** when you can just change the code.
- **No speculative "what if" code paths.**
- **If you wrote 200 lines and it could be 50, rewrite it.** This is not optional.
- **Ask yourself**: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 6. Tenacity With Direction

Relentless execution is a strength — but only with clear goals.

- **When stuck, diagnose before switching tactics.** Read the error. Check assumptions. Try a focused fix.
- **Don't retry blindly** — understand why it failed before trying again.
- **Don't abandon a viable approach after one failure** — persist with investigation.
- **Escalate to user only when genuinely stuck** after investigation, not as a first response to friction.

---

## Core Workflow (Always Active)

### Clarifying Questions First
Before any solution/architecture/code, use `AskUserQuestion` to understand:
1. User requirements (who, problem, success criteria)
2. Constraints (timeline, budget, security/compliance, scalability, integrations)
3. Technical context (existing infra or greenfield, team size, deployment frequency)

### Decision-Making
1. Present 2-4 alternatives with trade-offs (pros, cons, costs, complexity)
2. Recommend with rationale; use decision matrix if needed
3. Consider total cost of ownership

---

## Automatic Guideline Loading

Before starting any task, silently read relevant guidelines. Only mention loaded guidelines if user asks.

### Always Load
- `~/.claude/guidelines/diagrams.md` — all diagram work (Mermaid, Draw.io)
- Use `uv` as python package manager when using Claude skills

### Conditionally Load

| Trigger | Guideline |
|---------|-----------|
| AWS services, CDK, CloudFormation, cloud architecture | `~/.claude/guidelines/aws-infrastructure.md` |
| Code files (.js, .py, .go, .vba), "implement", "refactor", "code review" | `~/.claude/guidelines/coding-general.md` |
| Python (.py) or VBA (.vba, .bas, .cls) files | `~/.claude/guidelines/coding-languages.md` |
| Tests, TDD, test coverage, pytest/jest/mocha | `~/.claude/guidelines/tdd-testing.md` |
| "Implement this", full TDD workflow | `~/.claude/guidelines/implementation.md` + `dev-qa-harness` skill |
| ADRs, system design docs, RFCs, "document this", any coding work | `~/.claude/guidelines/documentation.md` |
| PowerPoint, slides, "present this" | `~/.claude/guidelines/presentations.md` |
| Solution design, architecture, "architect this" | `~/.claude/guidelines/architecture-process.md` |

---

## Quick Commands

When I say:
- **"Architect this"** → Load architecture-process.md → full solution design with options
- **"Document this"** → Load documentation.md → System Design Document/ADR
- **"Test this"** → Load tdd-testing.md → generate TDD tests
- **"Implement this"** → Load implementation.md + invoke `dev-qa-harness` skill → multi-agent TDD implementation (dev subagent follows implementation.md TDD patterns)
- **"Present this"** → Load presentations.md → PowerPoint with pptx skill
- **"Deploy this"** → Load aws-infrastructure.md → CDK/CloudFormation code
- **"AWS diagram"** → Load diagrams.md → Mermaid architecture diagram
- **"Review this"** → Load coding-general.md → code review with checklist
- **"Refactor this"** → Load coding-general.md + tdd-testing.md → improve code, keep tests green

---

## Collaboration Style (Always Active)

- **Systematic**: Break down complex problems
- **Options with rationale**: Present alternatives with trade-offs
- **Socratic method**: Guide through questions vs prescribe
- **Iterative**: Start simple, add complexity as needed
- **Assume greenfield** unless told otherwise
- **User sets conventions**: Respect user's role as technical authority
- **Never assume**: Use `AskUserQuestion` to clarify; flag assumptions

### Red Flags to Raise
Security vulnerabilities, single points of failure, scalability bottlenecks, excessive costs, overly complex solutions, missing test coverage, lack of monitoring, poor UX

### Success Criteria
- Clarifying questions asked → multiple options with rationale provided
- Citizen-centric, serves public good
- TDD with tests; documentation follows templates
- Security, compliance, cost optimization, maintainability addressed

---

## Artifact Saving

Save outputs using `{yymmdd_HHMM_NN}_{kebab-description}.md` naming (`NN` = sequential index within the same minute: `01`, `02`, …):
- **Feature specs**: `{cwd}/.claude/specs/` — written **before** plans/todos (see below)
- **Plans/todos**: `{cwd}/.claude/todos/` — project-scoped; include acceptance checklist
- **Cross-project docs**: `${ARTIFACTS_PATH}/{ai-docs|ai-research}/`
- **Project docs**: `{cwd}/docs/`

> **MUST**: Do NOT use `ExitPlanMode`. Always write plans to `.claude/todos/{yymmdd_HHMM_NN}_{kebab-description}.md` using `Write` tool directly.

### Feature Spec Before Plan (MANDATORY)

For any feature or significant change, write a spec to `.claude/specs/` **before** creating the plan/todo file.

1. **Create spec first** — `{cwd}/.claude/specs/{yymmdd_HHMM_NN}_{kebab-description}-spec.md`
2. **Then create plan/todo** — reference the spec file in the plan's frontmatter or header
3. Spec captures **what and why**; plan captures **how and when**

**Spec template:**
```markdown
---
spec: {yymmdd_HHMM_NN}_{kebab-description}
status: draft | approved | superseded
---
# {Feature Title}

## Problem
What problem does this solve? Who is affected?

## Proposed Solution
High-level approach — what changes, what stays the same.

## Design Details
Key technical decisions, data flow, interfaces, edge cases.

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Out of Scope
What this does NOT cover.
```

**Rules:**
- Spec is required for features, significant refactors, and new integrations. Not required for simple bugfixes or config changes.
- Get user alignment on the spec before writing the plan.
- Plan/todo file should include `spec: .claude/specs/{filename}` in frontmatter to link back.

### Checklist as Inter-Session State

The acceptance checklist in every plan/todo file is the primary handoff mechanism between agent sessions:

1. Update the checklist immediately after completing each item — mark `[x]`
2. Add inline notes for status or blockers
3. Never leave stale checkboxes — future sessions read this to know where to resume

### Checklist Integrity Rules

**MUST**: Never bulk-tick checkboxes. Each item verified individually before marking `[x]`.

- **Implementation** `[x]` — only after code is written and confirmed working
- **Unit test** `[x]` — only after running the specific test and seeing it pass (e.g. `bun test --filter "test name"`)
- **E2E** `[x]` — only after user confirms manually against the live system

Prohibited: `sed`, regex replace, or any bulk operation to tick multiple checkboxes. One checkbox = one verification = one `[x]`.

### User E2E Test Checklist

Every plan/todo file **MUST** include a `## User E2E Test Checklist` section — manual tests only (sending real messages, tapping buttons, observing live responses). Automated/mock-based tests go in the test suite.

Each step: numbered, self-contained, user instruction + expected outcome, checkable as pass/fail without reading code.

```markdown
---
e2e-due-days: 7              # deadline = write date + N days (default 7)
e2e-group: Code Quality       # Telegram group name → Things project prefix
e2e-thread: memory-source     # thread short name → Things project: "{group} / {thread}"
---
# {yymmdd_NN} {todo-file-name-description}

## User E2E Test Checklist

### Scenario: <feature or bug>

- [ ] **Step 1** — <action> → Expected: <outcome>
- [ ] **Step 2** — <action> → Expected: <outcome>
```

Rules: At least one scenario per plan. Write before implementation. Do not mix implementation tasks here. Frontmatter auto-syncs E2E items to Things 3 under Area "Jarvis".

### Explore Todos
Check 5 most recent todos at session start; ask user to pick or start afresh.

---

## Activity Log (Always Active)

Central activity diary at `~/.claude/activity-log/entries.jsonl`. Entries are JSONL — one JSON per line, append-only.

### Session Start

At session start, append a `session_start` entry:

```bash
echo '{"ts":"<ISO8601>","date":"<YYYY-MM-DD>","type":"session_start","project":"<basename of cwd>","cwd":"<cwd>","intent":"<1-line: what the user wants to do>","tags":[]}' >> ~/.claude/activity-log/entries.jsonl
```

Then embed it: `echo '<the json>' | python3 ~/.claude/activity-log/embed-entry.py`

### On Commit (automated via PostToolUse hook)

The `post-commit-activity.sh` hook fires after `git commit` and outputs instructions. Follow them:
1. Append a `commit` entry to `entries.jsonl` with LLM-generated `summary`, `status`, `next_steps`
2. Embed via `embed-entry.py`
3. Regenerate today's diary: `python3 ~/.claude/activity-log/generate-diary.py`

### Session End

When the user says "done", "that's all", or explicitly ends work — **and also when the conversation has produced real work but no commits today** — append a `session_end` entry. This is the idle-flush path that catches work not captured by the post-commit hook.

**Protocol:**

1. **Scan for uncommitted work** in the current cwd:
   ```bash
   git status --short 2>/dev/null              # uncommitted changes
   git log --since=midnight --oneline 2>/dev/null  # today's commits (if any)
   ```
2. **Decide if an entry is warranted.** Skip if today already has a `session_end` for this project AND no new uncommitted changes since. Otherwise proceed.
3. **Build the entry.** Include `files_touched` (uncommitted) so the diary can show non-committed work:

   ```bash
   echo '{"ts":"<ISO8601>","date":"<YYYY-MM-DD>","type":"session_end","project":"<project>","cwd":"<cwd>","summary":"<what was accomplished>","status":"<completed|in-progress|blocked>","next_steps":["<remaining work>"],"files_touched":["<path1>","<path2>"],"committed":<true|false>}' >> ~/.claude/activity-log/entries.jsonl
   ```
4. **Embed and regenerate diary:**
   ```bash
   echo '<the json>' | python3 ~/.claude/activity-log/embed-entry.py
   python3 ~/.claude/activity-log/generate-diary.py
   ```

**Heuristic for the auto-trigger** (no explicit signal): if the user disengages after a meaningful work block (file edits, build/install, doc updates) and there have been no commits today, write the session_end before going idle. Err toward writing one entry per project per session — the diary deduplicates better than it backfills.

### Diary & Insights

| Command | Purpose |
|---------|---------|
| `python3 ~/.claude/activity-log/generate-diary.py` | Today's diary |
| `python3 ~/.claude/activity-log/generate-diary.py YYYY-MM-DD` | Specific date |
| `python3 ~/.claude/activity-log/generate-diary.py --week` | This week |
| `python3 ~/.claude/activity-log/generate-diary.py --stale 7` | Projects idle >7 days |

---

## Documentation (Always Active)

For every coding task, documentation is **mandatory** — not optional.

### Rules
1. **Discover first** — before writing anything, scan `docs/`, `README*`, `CHANGELOG*`, and any existing wiki or inline docs in the project. Reuse and update existing files; only create a new file if no suitable one exists.
2. **Always update the changelog** — append an entry to `{cwd}/CHANGELOG.md` for every change set. If no changelog exists, create one at project root.
3. **Be specific and concise** — document what changed, why, and how to use the affected feature. No background assumptions: the reader may be unfamiliar with the codebase but must be able to understand and use the full feature from the docs alone.
4. **Cover all features** — document every user-facing behaviour, config option, CLI flag, API endpoint, or environment variable introduced or modified.
5. **Feature docs** — for any code development, update or create `{cwd}/docs/{features_group}-{features_name}.md` covering the feature's purpose, usage, and key design decisions.

### Changelog Entry Format

```markdown
## [Unreleased] / YYYY-MM-DD — <short title>

### Added / Changed / Fixed / Removed
- **<component>**: <what changed and why>. Usage: `<example command or snippet>`.
```

### Guideline Trigger
Any coding work (implement, refactor, bugfix) → load `~/.claude/guidelines/documentation.md`.

## Git Workflow

**MUST**: Never code on master/main directly — no exceptions, even for critical/urgent fixes. Always create a feature branch BEFORE any code edit. Never `git push` unless user explicitly asks. Ask if unsure.

Branch naming:
- `{plans|todos}/{description_name}` | `bugfix/{description_name}` | `feat/{description_name}` | `misc/{description_name}`

Commits are GPG-signed automatically via global git config. Do NOT use `--no-gpg-sign`.

Tag naming: `v{YYYY}.{MM}.{DD}_{NNN}` where `NNN` is a zero-padded counter (001, 002, ...) for multiple tags on the same day. Check existing tags for the day (`git tag -l "v{YYYY}.{MM}.{DD}_*"`) to determine the next counter.

### Git Worktree Protocol (MANDATORY)

> **Enforced by hook**: `~/.claude/hooks/pre-worktree-gate.sh` blocks `Edit`/`Write`/`MultiEdit` when on `main`/`master` or outside a worktree (bootstrap-exempt for empty repos). Escape hatch: `SKIP_WORKTREE_GATE=1` in the env — use sparingly.

1. **Always use a worktree** — never work in the main CWD directly.
   ```bash
   git worktree add worktrees/<branch-name> -b <branch-name>
   ```
2. **Assume other Claude agents may be running in the same CWD.** Never modify files outside your worktree. Never restart shared services without user confirmation.
3. **Do NOT merge to master** until the user explicitly says so.
4. **Before merging:** run tests and update docs — always. No exceptions.
   - Update `{cwd}/CLAUDE.md` on the feature branch to reflect new features, changed behaviours, updated commands, or conventions. Keep it concise — one bullet per meaningful change.
   - Run tests: `bun test` must pass.
   ```bash
   bun test   # must pass before merge
   git checkout master && git merge --no-ff <branch-name>
   ```
5. **Clean up worktree** only after the user confirms the work is done:
   ```bash
   git worktree remove worktrees/<branch-name>
   ```

---

## Plans/Todos Workflow

- All todos/plans saved in `{cwd}/.claude/todos/`
- Complex development/research/debate tasks → save into plans after analysis phase

### Coding Task State (MUST for all agents)

Any LLM agent tasked with coding **MUST** maintain a todos file as single source of truth for inter-session/inter-agent state.

1. **Before coding** — write feature spec to `{cwd}/.claude/specs/` first (if feature/refactor/integration), then create `{cwd}/.claude/todos/{yymmdd_HHMM_NN}_{description}.md` with task description, acceptance criteria, implementation checklist, User E2E Test Checklist, and `spec:` frontmatter linking to the spec file
2. **During coding** — update checklist after each completed item (mark `[x]`, add notes/blockers)
3. **After coding** — all completed items ticked, uncompleted items have status notes, file reflects true state for next session
4. **Spec-vs-Code Review (MANDATORY)** — after implementation completes, spawn an independent reviewer agent (`code-reviewer` or `analyzer`) to cross-validate the final codebase against the original spec. The reviewer:
   - Reads the spec from `.claude/specs/` and the current code (not the todos)
   - Identifies gaps: missing acceptance criteria, partial implementations, behavioural drift from spec intent
   - Produces a concise gap report (list of gaps with severity: critical/minor)
   - If **no gaps** → proceed to commit/PR
   - If **gaps found** → present the gap report to the user and ask whether to iterate (fix gaps) or accept as-is
   - This step is automatic — do not skip it or ask whether to run it

Applies to: `/code` sessions, multi-agent group tasks, subagents, any autonomous coding workflow. No coding without a todos file; no session end without updating it.

---

## Decision Journal (Always Active)

Every coding session **MUST** maintain `{cwd}/DECISIONS.md` — captures **why** decisions were made (reasoning that git commits alone cannot show).

**When to write**: significant architecture/design choice, bug root-cause fix, threshold/parameter tuning, structural refactor, decision to defer/reject.

```markdown
## YYYY-MM-DD — <short title> [<commit-hash>]

**Change**: <one sentence>
**Why**: <reasoning — root cause, evidence, or constraint>
**Rejected**: <alternatives and why not>
**Branch**: <branch name>
```

Rules: Append-only, one entry per logical decision, short hash (7 chars) or "pending", write at session end, decisions only (not diffs).

At session start: skim last 10 entries in `{cwd}/DECISIONS.md` if it exists.

<!-- ---

## E2E Test Framework (Telegram Bot)

**Load when**: Grammy-based Telegram bot project, or writing/reviewing `*.test.ts` / `*.e2e.test.ts` files interacting with Telegram.

Load: `~/.claude/CLAUDE.e2e.md` (global fixture schema) + project-local `CLAUDE.e2e.md`.

**Rules**: Grammy SDK boundary only. No assumptions about ctx shapes — use captured fixtures. No derived fixtures without `source: "derived"` + rationale.

**Claude CLI fixtures**: Load when mocking `claudeText`/`claudeStream` or modifying `src/claude-process.ts`. Mock helpers: `mockClaudeText(id)` / `mockClaudeStream(id)` in `tests/e2e/runner.ts`. -->

---

## Workflow Learning & Reuse (Always Active)

Learn and persist project workflows so future sessions can replay steps with new context.

### Session Start — Detect Mode

1. **Check** `{cwd}/CLAUDE.md` exists
2. **If absent** → **Learning Mode** (silent): track user commands, instructions, and sequences. Do not announce.
3. **If present** → **Replay Mode**: user says "run Step 3" or "repeat Phase 2 with X" to re-execute with new context

### Learning Mode — New Project Bootstrap

When `{cwd}/CLAUDE.md` is absent and user begins work:

1. **Observe** — silently track all commands/instructions
2. **Git init** — if not a git repo, note `git init` as Step 1 when user does it
3. **Worktree** — follow global Git Worktree Protocol (branch + worktree before any edits)
4. **`.gitignore`** — before first commit, ensure `.gitignore` exists. Auto-generate based on:
   - **Always**: `.DS_Store`, `.env`, `.claude/`, `worktrees/`
   - **Python**: `__pycache__/`, `*.pyc`, `.venv/`, `dist/`, `*.egg-info/`
   - **Node**: `node_modules/`, `.next/`, `dist/`
   - **General**: `*.log`, `.tmp_*/`, `coverage/`
   - Detect from file extensions and tooling present; ask user to confirm before writing
5. **Existing artifacts** — detect and note presence of `CHANGELOG.md`, `DECISIONS.md`, `docs/`, `README*` (global CLAUDE.md governs their maintenance — reference, don't duplicate rules)

### Compile on First Commit

**Trigger**: user's first `git commit` (or commit request) in a Learning Mode session.

1. **Compile** observed workflow into structured phases/steps
2. **Present**: "I've compiled the workflow from this session — review and I'll save to `{cwd}/CLAUDE.md`"
3. **On approval** → save to `{cwd}/CLAUDE.md`
4. **On edits** → incorporate, then save

### Workflow Format

```
# {Project Name} — Claude Workflow

## {Phase Name}

### Step N — {Short description}
{Executable command or instruction with `<PLACEHOLDER>` for variable parts}
```

Rules:
- **Concise** — one line per step; no prose unless critical
- **Executable** — copy-pasteable with minimal substitution
- **Grouped by phase** — logical groupings (setup, process, analyse, output)
- **Reference, don't duplicate** — for changelog/decisions/docs rules, write "see global CLAUDE.md" not the full rules
- **Include directory structure** — append a tree view of project layout

### Continuous Update

1. **Observe** new commands after initial save
2. **At breakpoints** (next commit, phase boundary, or user says "update workflow") → "New steps observed — update CLAUDE.md?"
3. **Insert intelligently** — match to existing phases; new phase only if no fit
4. **Never duplicate** — refining a step? Update in place
5. **Cap** — if workflow exceeds ~100 lines, consolidate

### Replay Mode

- `"Run Step 3"` → execute that step
- `"Repeat Phase 2 with X"` → re-run with substituted context
- `"Skip to Step 5"` → jump ahead
- `"Add step after Step 3"` → extend, then update CLAUDE.md

---

## NLAH Dev/QA Harness

This user has the NLAH-style multi-agent Dev/QA harness installed globally.

**Activation**: triggered by the `dev-qa-harness` skill (loaded automatically
based on its description, or explicitly via "use the dev-qa-harness skill").

**Roles**:
- `pm-spec` — turns requests into a frozen, observable specification
- `dev` — implements against the spec; cannot modify it
- `qa` — derives tests from the spec; runs them against dev's code

**Workspace**: per-task state under `run/` (gitignored). Test command is
auto-detected from build files (`package.json`, `pyproject.toml`, `Cargo.toml`,
`go.mod`). Override per-project via `.claude/nlah-config.sh` if needed.

**Escalation policy**: user is consulted only at spec-time (if ambiguous) or
when override budget is exceeded. All autonomous decisions logged to
`run/state/decisions.jsonl` for post-hoc review.

**Charter authority**: detailed runtime charter is in the user-global skill at
`~/.claude/skills/dev-qa-harness/SKILL.md`.

**Override budgets**: defaults are MAX_ATTEMPTS=5, MAX_SAME_FAILURE=3. Override
per-project via `.claude/nlah-config.sh` or env vars.

---
**Last Updated**: 2026-04-28
