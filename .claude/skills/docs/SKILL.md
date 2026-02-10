---
name: docs
description: Sync documentation with code changes. Audits git diff and updates ARCHITECTURE.md, DECISIONS.md, TASKS.md, CLAUDE.md, and README.md to reflect current implementation.
user_invocable: true
---

# /docs — Documentation Sync

Keep project documentation in sync with code changes. Run after implementing a task.

## Process

### 1. Audit Changes

Run `git diff --name-only HEAD` (or `git diff --name-only` for unstaged changes) to categorize what changed:

| Changed Files | Docs to Check |
|--------------|---------------|
| `apps/server/src/db/schema.ts` | ARCHITECTURE.md §Data Model |
| `apps/server/src/routes/*` | ARCHITECTURE.md §API Design |
| `apps/server/src/mastra/*` | AI_STACK.md |
| `apps/web/src/*` | ARCHITECTURE.md §Frontend Design |
| `package.json`, `bun.lock` | ARCHITECTURE.md §Dependencies |
| `Dockerfile`, `docker-compose.yml` | ARCHITECTURE.md §Infrastructure |
| `biome.json`, `tsconfig.json` | ARCHITECTURE.md §Infrastructure |
| `.github/workflows/*` | ARCHITECTURE.md §Infrastructure |
| Any `apps/server/src/*` | `apps/server/CLAUDE.md` patterns |
| Any `apps/web/src/*` | `apps/web/CLAUDE.md` patterns |
| Any new env vars | README.md, ARCHITECTURE.md §Infrastructure |
| Any new scripts in package.json | Root CLAUDE.md commands section |

### 2. Check Each Document

For each affected document:

**`docs/ARCHITECTURE.md`** — Does the architecture still match the implementation?
- Schema changes → update §Data Model code blocks
- New/changed API routes → update §API Design endpoint list
- Dependency additions/removals → update §Dependencies
- Only update sections where implementation **deviated from** or **refined** the spec

**`docs/DECISIONS.md`** — Any new or changed decisions?
- New ADRs or changed decisions → update ADR section or Decision Log table
- Only add entries when a decision was actually made or revisited

**`docs/TASKS.md`** — Should tasks be marked complete?
- Check off completed tasks: `- [ ]` → `- [x]`
- If implementation revealed new sub-tasks, add them
- Update task descriptions if approach changed

**`CLAUDE.md`** (root + app-level) — Are commands and structure current?
- New scripts in package.json → update Commands section
- New directories or patterns → update structure/patterns
- New critical decisions → update Critical Architecture Decisions

**`README.md`** — Is setup info complete?
- New env vars → update env var reference
- New commands → update usage section
- Setup steps changed → update installation guide

### 3. Apply Updates

- Make minimal, targeted changes — only what the implementation changed
- Preserve existing doc structure and formatting
- Update code blocks to match actual implementation
- Do NOT rewrite sections that are still accurate

### 4. Report

After checking all docs, report:

```
## /docs Sync Report

### Updated
- docs/ARCHITECTURE.md §Data Model: Updated schema to reflect [change]
- docs/TASKS.md: Checked off task 1.5

### Already in Sync
- CLAUDE.md: No changes needed
- README.md: No changes needed

### Needs Manual Review
- [anything that requires a decision, not just a sync]
```

## Rules

- Do NOT modify source code — this skill only touches documentation
- Do NOT create new documentation files
- Do NOT commit changes — that's the user's job via `/commit`
- Keep changes minimal — match docs to code, nothing more
- If a spec section is outdated but the change is ambiguous, flag it for manual review
