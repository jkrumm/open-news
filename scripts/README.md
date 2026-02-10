# OpenNews Scripts

## ralph-mvp.sh

One-shot autonomous implementation script for OpenNews MVP with human-in-the-loop checkpoints.

### Purpose

Automates the initial implementation of OpenNews following the 28 tasks across 5 phases defined in `docs/TASKS.md`. This script is designed for **one-time use** during initial development and includes human review checkpoints after each major phase.

### How It Works

1. **Phase-based execution**: Runs autonomously within each of the 5 phases
2. **Fresh Claude context per task**: Prevents context drift over long runs
3. **Human checkpoints**: Pauses after each phase for review and approval
4. **Comprehensive logging**: All Claude output, validation, and commits logged to `.ralph-logs/`
5. **Atomic commits**: One commit per completed task
6. **Safety checks**: Blocks destructive commands
7. **Resumable**: Can be interrupted and resumed

### Phases

| Phase | Tasks | Description |
|-------|-------|-------------|
| 1 | 1-5 | Project Setup (monorepo, tooling, schema) |
| 2 | 6-13 | Backend Core (auth, CRUD, services, feed endpoint) |
| 3 | 14-20 | AI Pipeline (Mastra agents, workflows, tools) |
| 4 | 21-25 | Frontend (feed, article, settings) |
| 5 | 26-28 | Polish (error handling, onboarding) |

### Usage

```bash
# Start from beginning
./scripts/ralph-mvp.sh

# Start from specific phase (e.g., phase 3)
./scripts/ralph-mvp.sh --phase 3

# Resume from interruption
./scripts/ralph-mvp.sh --resume
```

### Human Checkpoint Flow

After each phase completes:

1. **Phase report generated**: Claude synthesizes what was accomplished
2. **Review prompt**: You review implementation, logs, and commits
3. **Decision**:
   - **Continue** → Proceed to next phase
   - **Retry** → Re-run current phase (tasks reset to pending)
   - **Stop** → Exit (resume later with `--resume`)

### Output

All logs and reports are written to `.ralph-logs/` (gitignored):

```
.ralph-logs/
├── state.json                  # Task tracking state
├── parse-phase-N.log           # Task parsing logs
├── task-X.Y.log                # Per-task implementation logs
├── report-phase-N.log          # Phase report generation logs
└── RALPH_REPORT.md             # Cumulative implementation report
```

### Configuration

Key constants (edit in script if needed):

- `MAX_TASK_RETRIES=3` - Max attempts per task
- `API_RETRIES=3` - Retries for transient API errors
- `CLAUDE_TIMEOUT=1800` - 30 minutes per Claude call
- `RETRY_DELAY=10` - Seconds between retries

### Safety Features

- **Forbidden commands**: Blocks destructive operations (rm -rf, force push, etc.)
- **Completion signals**: Tasks must explicitly signal completion or blocked status
- **Graceful interrupts**: SIGINT/SIGTERM save state for resumption
- **Fresh context**: Each task gets clean Claude context (no drift)

### Integration with /code-quality and /commit

The script instructs Claude to use:

- `/code-quality` - Validate changes (format, lint, typecheck, test)
- `/commit` - Create conventional commits (no AI attribution)

These run in forked contexts to save tokens (~80% reduction).

### Cost & Time Estimates

Based on student-enrolment event migration (58 tasks):

- **Cost**: ~$1.50 per task (Sonnet 4.5)
- **Time**: ~5-10 minutes per task
- **Total for OpenNews MVP (28 tasks)**: ~$42 and ~3-5 hours

### After MVP Completion

Once MVP is implemented:

1. Archive this script (for reference)
2. Delete `.ralph-logs/` (or keep for historical context)
3. Switch to manual `/commit`, `/pr`, `/code-quality` workflow
4. Use standard spec-driven development for post-MVP work

### Monitoring Progress

Use the status viewer to check progress at any time:

```bash
# Quick summary
./scripts/ralph-status.sh

# Verbose output (all task details)
./scripts/ralph-status.sh --verbose
```

Shows:
- Current phase and status
- Per-phase completion statistics
- Overall progress percentage
- Recent activity (last 5 completed tasks)
- Blocked tasks with log references

### Troubleshooting

**Task blocked repeatedly:**
- Check `.ralph-logs/task-X.Y.log` for Claude's reasoning
- May need manual intervention or spec clarification

**API timeout:**
- Increase `CLAUDE_TIMEOUT` if tasks are complex
- Split large tasks in TASKS.md

**Script interrupted:**
- Resume with `--resume` flag
- State is preserved in `.ralph-logs/state.json`

**Safety check fails:**
- Review task log for forbidden commands
- Claude may have suggested destructive operation
- Edit task instructions or run manually

---

## ralph-status.sh

Quick status viewer for RALPH MVP implementation progress.

### Usage

```bash
./scripts/ralph-status.sh           # Summary view
./scripts/ralph-status.sh --verbose # Detailed task list
```

### Output

- Current phase and name
- Per-phase completion statistics
- Overall progress (completed/blocked/pending/in progress)
- Recent activity (last 5 completed tasks)
- Blocked tasks with log file references
- Link to full report
