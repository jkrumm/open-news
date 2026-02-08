# RALPH Script Comparison

Comparison between the original `epos.student-enrolment` RALPH loop and the adapted OpenNews version.

## Core Philosophy

| Aspect | student-enrolment | OpenNews |
|--------|-------------------|----------|
| **Use Case** | Repeatable migrations (event refactoring) | One-shot MVP implementation |
| **Execution Model** | Fully autonomous until done/blocked | **Phase-based with human checkpoints** |
| **Human Interaction** | Only on interrupt or completion | **After every phase (5 checkpoints)** |
| **Reusability** | Designed for multiple similar migrations | Single-use for initial implementation |

## Structural Differences

### 1. Task Organization

**student-enrolment:**
```bash
# OpenSpec structure
openspec/changes/<change-name>/
├── proposal.md
├── design.md
├── tasks.md              # Source of truth
├── .ralph-tasks.json     # Generated state
└── .ralph-logs/          # Logs

# Task structure: Grouped by parent
{
  "taskGroups": [
    {
      "id": "1",
      "title": "Parent task",
      "status": "pending",
      "attempts": 0,
      "subtasks": [
        {"id": "1.1", "title": "...", "files": [...], "status": "pending"},
        {"id": "1.2", "title": "...", "files": [...], "status": "pending"}
      ]
    }
  ]
}
```

**OpenNews:**
```bash
# Implementation-driven structure
docs/
├── SPEC.md               # Technical spec
└── IMPLEMENTATION.md     # Source of truth (28 tasks, 5 phases)

.ralph-logs/
├── state.json            # Phase + task state
├── parse-phase-N.log
├── task-N.M.log
└── RALPH_REPORT.md

# State structure: Phase-based + flat tasks
{
  "current_phase": 1,
  "phases": {
    "1": {"status": "pending", "started_at": null, "completed_at": null}
  },
  "tasks": [
    {"id": "1.1", "title": "...", "status": "pending", "attempts": 0}
  ]
}
```

### 2. Execution Flow

**student-enrolment: Continuous Loop**
```
┌─────────────────────────────────────┐
│ Parse tasks.md → JSON (once)        │
└──────────┬──────────────────────────┘
           │
           ▼
┌─────────────────────────────────────┐
│ While tasks remain:                 │
│  1. Get next task group             │
│  2. Validate previous work          │◄───┐
│  3. Implement task group            │    │
│  4. Safety check                    │    │
│  5. Commit if complete              │    │
│  6. Retry if failed                 │────┘
└──────────┬──────────────────────────┘
           │ (All done or 3 consecutive failures)
           ▼
┌─────────────────────────────────────┐
│ Generate final report               │
└─────────────────────────────────────┘
```

**OpenNews: Phase-Based with Checkpoints**
```
┌─────────────────────────────────────┐
│ For each phase (1-5):               │
│                                     │
│  ┌───────────────────────────────┐ │
│  │ Parse phase tasks             │ │
│  └──────┬────────────────────────┘ │
│         │                           │
│         ▼                           │
│  ┌───────────────────────────────┐ │
│  │ While tasks in phase:         │ │
│  │  1. Get next task          ◄──┼─┼─┐
│  │  2. Implement task            │ │ │
│  │  3. /code-quality + /commit   │ │ │
│  │  4. Retry if failed       ────┼─┼─┘
│  └──────┬────────────────────────┘ │
│         │ (Phase complete)          │
│         ▼                           │
│  ┌───────────────────────────────┐ │
│  │ Generate phase report         │ │
│  └──────┬────────────────────────┘ │
│         │                           │
│         ▼                           │
│  ┌───────────────────────────────┐ │
│  │ HUMAN CHECKPOINT              │ │
│  │ - Review implementation       │ │
│  │ - Review logs                 │ │
│  │ - Decision:                   │ │
│  │   • Continue → next phase     │ │
│  │   • Retry → re-run phase      │ │
│  │   • Stop → exit               │ │
│  └───────────────────────────────┘ │
│                                     │
└─────────────────────────────────────┘
           │ (All phases done)
           ▼
┌─────────────────────────────────────┐
│ Final summary                       │
└─────────────────────────────────────┘
```

### 3. Claude Invocation

**student-enrolment:**
```bash
# Explicit permissions bypass + plugin directory
timeout "${CLAUDE_TIMEOUT}s" \
  env ENABLE_TOOL_SEARCH=true CLAUDE_CODE_ENABLE_TASKS=true \
  claude --dangerously-skip-permissions --plugin-dir "$PLUGIN_DIR" \
  -p "$prompt" 2>&1 | tee "$log_file"
```

**OpenNews:**
```bash
# Fast mode + no cache (simpler)
timeout ${CLAUDE_TIMEOUT} \
  claude --fast --no-cache "${prompt}" 2>&1 | tee -a "${log_file}"
```

### 4. Validation Strategy

**student-enrolment:**
```bash
# Pre-task validation prompt
if [[ -n "$COMPLETED_LIST" ]]; then
  echo "Validating previous tasks..."
  VALIDATE_PROMPT="..."  # Asks Claude to verify completed tasks

  if echo "$VALIDATE_RESULT" | grep -q "VALIDATION_FAILED"; then
    # Re-queue failed task
    update_task_json "$FAILED_TASK" "pending"
  fi
fi
```

**OpenNews:**
```bash
# Relies on /code-quality skill
# No pre-task validation
# Implementation prompt includes: "Run /code-quality to validate changes"
```

### 5. Commit Strategy

**student-enrolment:**
```bash
# Script creates commits directly
git add -A
COMMIT_MSG="feat(${TICKET:-tasks}): task ${GROUP_ID} - ${GROUP_TITLE}"
git commit -m "$COMMIT_MSG" --no-verify || true
```

**OpenNews:**
```bash
# Delegates to /commit skill
# Implementation prompt includes:
# "Create atomic commit with /commit (no --split)"
# "No AI attribution in commits"
```

### 6. Test Requirements

**student-enrolment:**
```
Implementation prompt includes:

4. **Write Unit Tests (100% coverage for new code)**
   - Add tests to existing *.spec.ts files
   - Use OpenSpec specs for test scenarios
   - Test happy paths AND error/edge cases
   - Every new function/method needs tests

5. **Run Targeted Tests**
   - npm run test -- <filename.spec.ts>
   - Fix any failures before proceeding
```

**OpenNews:**
```
Implementation prompt includes:

"Run /code-quality to validate changes"

# No explicit test coverage requirement
# Deferred to /code-quality skill
```

### 7. Forbidden Commands

**student-enrolment (NestJS project-specific):**
```bash
FORBIDDEN_SCRIPTS=(
  # Migrations
  "typeorm:generate"
  "typeorm:run"
  # Services/Docker
  "services"
  "container:nest"
  # Running the app
  "start"
  "start:dev"
  # Dependencies
  "npm install"
  "bun add"
)
```

**OpenNews (generic safety):**
```bash
FORBIDDEN_COMMANDS=(
  "rm -rf"
  "git push --force"
  "git reset --hard"
  "docker-compose down -v"
  "bun install"
  "npm install"
  "bun add"
)
```

### 8. Reports

**student-enrolment:**
- Single final report at completion
- Claude synthesizes from all task logs
- Includes: Summary, Completed Tasks, Blocked Tasks, Issues, Suggestions, Next Steps

**OpenNews:**
- Per-phase reports (5 total)
- Cumulative report (`RALPH_REPORT.md`)
- Each phase report: Summary, Completed Tasks, Blocked Tasks, Issues & Recommendations
- Human reviews report at each checkpoint

### 9. Resume Logic

**student-enrolment:**
```bash
# Automatically resumes from interrupted state
# Checks for in_progress tasks
if [[ "$IN_PROGRESS" -gt 0 ]]; then
  echo "Resuming interrupted run - ${IN_PROGRESS} group(s) were in progress"
fi

# Cleanup on interrupt
cleanup() {
  if [[ -n "$CURRENT_TASK_ID" ]]; then
    update_task_json "$CURRENT_TASK_ID" "pending" "Interrupted, will retry"
  fi
  git checkout -- . 2>/dev/null  # Discard uncommitted changes
}
```

**OpenNews:**
```bash
# Explicit --resume flag
./scripts/ralph-mvp.sh --resume

# Reads current_phase from state.json
if [[ "${resume}" == true ]]; then
  start_phase=$(get_current_phase)
fi
```

### 10. Progress Monitoring

**student-enrolment:**
```bash
# Built into script output
show_progress() {
  echo "Progress: ${total} groups (${subtotal} subtasks) |
        ${done} done | ${pending} pending | ${blocked} blocked | ${percent}%"
}
```

**OpenNews:**
```bash
# Separate status script
./scripts/ralph-status.sh
./scripts/ralph-status.sh --verbose

# Shows:
# - Current phase and status
# - Per-phase statistics
# - Overall progress
# - Recent activity
# - Blocked tasks with log references
```

## Implementation Prompts Comparison

### student-enrolment Implementation Prompt

**Key elements:**
1. **Context Files**: proposal.md, design.md, tasks.md
2. **Completed Tasks**: List for continuity
3. **Task Group**: ALL subtasks in group
4. **Instructions**:
   - Explore First (Explore agent)
   - Research if Needed (/research)
   - Implement ALL Subtasks
   - **Write Unit Tests (100% coverage)**
   - Run Targeted Tests
   - Validate (/code-quality)
   - Fix Issues
   - Review (/review)
   - Signal Completion
5. **Forbidden Commands**: Project-specific
6. **Ticket Reference**: EP-XXX

### OpenNews Implementation Prompt (as designed)

**Key elements:**
1. **Context Files**: IMPLEMENTATION.md, SPEC.md, CLAUDE.md
2. **Task Details**: From IMPLEMENTATION.md
3. **Instructions**:
   - Read task description
   - Understand dependencies
   - Implement following conventions
   - Run /code-quality
   - Create atomic commit with /commit
   - Output completion signal
4. **Forbidden Commands**: Generic safety
5. **Important**: Follow patterns, no AI attribution, single commit

**Notable differences:**
- ❌ No pre-task validation
- ❌ No explicit test coverage requirement
- ❌ No /review step
- ❌ No /research mention
- ✅ Simpler, more focused
- ✅ Delegates to /commit skill

## Human Checkpoint Flow (OpenNews Only)

```bash
human_checkpoint() {
  # Generate phase report
  generate_phase_report "${phase}"

  # Display report + logs
  echo "Review the implementation and logs in .ralph-logs/"
  echo "Check git commits for changes made"

  # Interactive decision
  read -p "Choice [1-3]: " choice

  case ${choice} in
    1) Continue to next phase ;;
    2) Retry this phase (reset tasks to pending) ;;
    3) Stop (resume later with --resume) ;;
  esac
}
```

## What Was Preserved

✅ **Fresh Claude context per task** (prevents drift)
✅ **Comprehensive logging** (per-task logs)
✅ **Safety checks** (forbidden commands)
✅ **Retry logic** (max 3 attempts per task)
✅ **Graceful interrupts** (SIGINT/SIGTERM handling)
✅ **State persistence** (JSON-based)
✅ **Completion signals** (`RALPH_TASK_COMPLETE` / `RALPH_TASK_BLOCKED`)
✅ **Consecutive failure abort** (3 failures = stop)
✅ **Colored output** (progress visualization)
✅ **Claude Tasks integration** (ENV var: `CLAUDE_CODE_ENABLE_TASKS=true`)

## What Changed for OpenNews

🆕 **Phase-based execution** (5 phases, not continuous)
🆕 **Human checkpoints** (review after each phase)
🆕 **Phase reports** (Claude summarizes accomplishments)
🆕 **Interactive decisions** (continue/retry/stop)
🆕 **Status monitor script** (separate ralph-status.sh)
🆕 **Per-phase parsing** (not single upfront parse)
🆕 **Flat task structure** (not grouped subtasks)
🆕 **Simpler Claude invocation** (--fast --no-cache)
🆕 **Delegates to /commit** (not direct git commit)
🆕 **No pre-task validation** (relies on /code-quality)
🆕 **No explicit test requirements** (deferred to /code-quality)
🆕 **Explicit --resume flag** (not automatic)

## What Was Simplified

⚡ **No taskGroups structure** - Flat task list instead of grouped subtasks
⚡ **No pre-task validation** - Relies on /code-quality for validation
⚡ **No explicit test coverage prompts** - Trusts /code-quality to catch issues
⚡ **No /review step** - Simplified implementation flow
⚡ **Generic forbidden commands** - Not project-specific
⚡ **Simpler state management** - Phase + tasks instead of taskGroups + subtasks

## When to Use Which Script

### Use student-enrolment RALPH when:
- ✅ Repeatable migrations (similar pattern across many items)
- ✅ Full autonomy desired (minimal human intervention)
- ✅ OpenSpec-based workflow (proposal + design + tasks)
- ✅ Grouped subtasks with shared context
- ✅ Explicit test coverage requirements
- ✅ Pre-task validation needed

### Use OpenNews RALPH when:
- ✅ One-shot implementation (MVP, initial setup)
- ✅ Human review desired after major milestones
- ✅ Phase-based workflow (backend → AI → frontend)
- ✅ Independent tasks within phases
- ✅ Simpler validation (delegate to /code-quality)
- ✅ Interactive decision points

## Recommendations for Future Adaptations

If adapting for another project, consider:

1. **Execution model**: Continuous vs phase-based vs hybrid
2. **Human involvement**: Fully autonomous vs checkpoints vs manual
3. **Task structure**: Grouped subtasks vs flat tasks vs hierarchical
4. **Validation strategy**: Pre-task validation vs post-task validation vs none
5. **Test requirements**: Explicit coverage vs delegated to /code-quality
6. **Commit strategy**: Script-managed vs skill-delegated
7. **Prompt complexity**: Detailed instructions vs minimal (trust skills)
8. **Resume logic**: Automatic vs explicit flag
9. **Monitoring**: Built-in progress vs separate status script

The student-enrolment script is **more autonomous and thorough**, while the OpenNews script is **more interactive and focused**. Choose based on your project needs and risk tolerance.
