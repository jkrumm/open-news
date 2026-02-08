#!/usr/bin/env bash
set -euo pipefail

################################################################################
# OpenNews Ralph MVP Loop v1.0
#
# One-shot autonomous implementation script for OpenNews MVP with human-in-the-loop
# checkpoints after each major phase.
#
# Usage: ./scripts/ralph-mvp.sh [--phase N] [--resume]
#
# Features:
# - Phase-based execution (5 phases from IMPLEMENTATION.md)
# - Human checkpoint after each phase for review/approval
# - Fresh Claude context per task (prevents drift)
# - Comprehensive logging + safety checks
# - Atomic commits per task
# - Resumable from interruption
################################################################################

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
readonly MAX_TASK_RETRIES=3
readonly API_RETRIES=3
readonly RETRY_DELAY=10
readonly CLAUDE_TIMEOUT=1800  # 30 minutes per Claude call
readonly TASK_COMPLETE="RALPH_TASK_COMPLETE"
readonly TASK_BLOCKED="RALPH_TASK_BLOCKED"

# Paths
readonly IMPL_FILE="docs/IMPLEMENTATION.md"
readonly LOGS_DIR=".ralph-logs"
readonly STATE_FILE="${LOGS_DIR}/state.json"
readonly REPORT_FILE="${LOGS_DIR}/RALPH_REPORT.md"

# Forbidden commands (prevent destructive operations)
readonly FORBIDDEN_COMMANDS=(
  "rm -rf"
  "git push --force"
  "git reset --hard"
  "docker-compose down -v"
  "bun install"  # Should use lockfile
  "npm install"
  "bun add"
  "npm add"
)

# Phase definitions (from IMPLEMENTATION.md)
declare -A PHASE_NAMES=(
  [1]="Project Setup"
  [2]="Backend Core"
  [3]="AI Pipeline"
  [4]="Frontend"
  [5]="Polish"
)

declare -A PHASE_TASK_RANGES=(
  [1]="1-5"
  [2]="6-13"
  [3]="14-20"
  [4]="21-25"
  [5]="26-28"
)

################################################################################
# Helper Functions
################################################################################

log() {
  echo -e "${CYAN}[$(date +'%H:%M:%S')]${NC} $*"
}

log_success() {
  echo -e "${GREEN}[$(date +'%H:%M:%S')] ✓${NC} $*"
}

log_error() {
  echo -e "${RED}[$(date +'%H:%M:%S')] ✗${NC} $*" >&2
}

log_warn() {
  echo -e "${YELLOW}[$(date +'%H:%M:%S')] ⚠${NC} $*"
}

log_phase() {
  echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $*${NC}"
  echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"
}

# Initialize state file
init_state() {
  mkdir -p "${LOGS_DIR}"

  if [[ ! -f "${STATE_FILE}" ]]; then
    log "Initializing state file..."
    cat > "${STATE_FILE}" <<EOF
{
  "current_phase": 1,
  "phases": {
    "1": {"status": "pending", "tasks": [], "started_at": null, "completed_at": null},
    "2": {"status": "pending", "tasks": [], "started_at": null, "completed_at": null},
    "3": {"status": "pending", "tasks": [], "started_at": null, "completed_at": null},
    "4": {"status": "pending", "tasks": [], "started_at": null, "completed_at": null},
    "5": {"status": "pending", "tasks": [], "started_at": null, "completed_at": null}
  },
  "tasks": []
}
EOF
  fi
}

# Get current phase from state
get_current_phase() {
  jq -r '.current_phase' "${STATE_FILE}"
}

# Update phase status
update_phase_status() {
  local phase=$1
  local status=$2
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ "${status}" == "in_progress" ]]; then
    jq --arg phase "${phase}" --arg ts "${timestamp}" \
      '.phases[$phase].status = "in_progress" | .phases[$phase].started_at = $ts' \
      "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  elif [[ "${status}" == "completed" ]]; then
    jq --arg phase "${phase}" --arg ts "${timestamp}" \
      '.phases[$phase].status = "completed" | .phases[$phase].completed_at = $ts' \
      "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  fi
}

# Add task to state
add_task() {
  local task_id=$1
  local title=$2
  local status=${3:-pending}

  local task_json=$(jq -n \
    --arg id "${task_id}" \
    --arg title "${title}" \
    --arg status "${status}" \
    '{id: $id, title: $title, status: $status, attempts: 0, started_at: null, completed_at: null}')

  jq --argjson task "${task_json}" \
    '.tasks += [$task]' \
    "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
}

# Update task status
update_task_status() {
  local task_id=$1
  local status=$2
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  if [[ "${status}" == "in_progress" ]]; then
    jq --arg id "${task_id}" --arg ts "${timestamp}" \
      '(.tasks[] | select(.id == $id)) |= (.status = "in_progress" | .started_at = $ts | .attempts += 1)' \
      "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  elif [[ "${status}" == "completed" ]]; then
    jq --arg id "${task_id}" --arg ts "${timestamp}" \
      '(.tasks[] | select(.id == $id)) |= (.status = "completed" | .completed_at = $ts)' \
      "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  elif [[ "${status}" == "blocked" ]]; then
    jq --arg id "${task_id}" --arg ts "${timestamp}" \
      '(.tasks[] | select(.id == $id)) |= (.status = "blocked" | .completed_at = $ts)' \
      "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
  fi
}

# Get task attempts
get_task_attempts() {
  local task_id=$1
  jq -r --arg id "${task_id}" '.tasks[] | select(.id == $id) | .attempts' "${STATE_FILE}"
}

# Check if output contains forbidden commands
check_safety() {
  local output=$1

  for cmd in "${FORBIDDEN_COMMANDS[@]}"; do
    if echo "${output}" | grep -q "${cmd}"; then
      log_error "Forbidden command detected: ${cmd}"
      return 1
    fi
  done

  return 0
}

# Run Claude with timeout and logging
run_claude() {
  local prompt=$1
  local log_file=$2
  local retry=0

  while [[ ${retry} -lt ${API_RETRIES} ]]; do
    log "Running Claude (attempt $((retry + 1))/${API_RETRIES})..."

    if timeout ${CLAUDE_TIMEOUT} claude --fast --no-cache "${prompt}" 2>&1 | tee -a "${log_file}"; then
      return 0
    else
      local exit_code=$?

      if [[ ${exit_code} -eq 124 ]]; then
        log_error "Claude timed out after ${CLAUDE_TIMEOUT}s"
      else
        log_error "Claude failed with exit code ${exit_code}"
      fi

      retry=$((retry + 1))
      if [[ ${retry} -lt ${API_RETRIES} ]]; then
        log_warn "Retrying in ${RETRY_DELAY}s..."
        sleep ${RETRY_DELAY}
      fi
    fi
  done

  return 1
}

# Parse tasks from IMPLEMENTATION.md for a phase
parse_phase_tasks() {
  local phase=$1
  local range=${PHASE_TASK_RANGES[$phase]}
  local start_task=${range%-*}
  local end_task=${range#*-}

  log "Parsing tasks ${start_task}-${end_task} from ${IMPL_FILE}..."

  # Extract tasks using Claude
  local parse_prompt=$(cat <<EOF
Parse tasks ${start_task} through ${end_task} from docs/IMPLEMENTATION.md.

For each task, extract:
1. Task ID (e.g., "1.1", "2.3")
2. Task title (brief description)
3. Dependencies (if any)

Output a JSON array with this structure:
[
  {
    "id": "1.1",
    "title": "Initialize Bun monorepo",
    "dependencies": []
  },
  ...
]

Read docs/IMPLEMENTATION.md and output ONLY the JSON array, no other text.
EOF
)

  local parse_log="${LOGS_DIR}/parse-phase-${phase}.log"
  local output=$(run_claude "${parse_prompt}" "${parse_log}")

  # Extract JSON from output
  local tasks_json=$(echo "${output}" | sed -n '/^\[/,/^\]/p')

  if [[ -z "${tasks_json}" ]]; then
    log_error "Failed to parse tasks from Claude output"
    return 1
  fi

  # Add tasks to state
  echo "${tasks_json}" | jq -c '.[]' | while read -r task; do
    local task_id=$(echo "${task}" | jq -r '.id')
    local task_title=$(echo "${task}" | jq -r '.title')
    add_task "${task_id}" "${task_title}" "pending"
  done

  log_success "Parsed $(echo "${tasks_json}" | jq '. | length') tasks"
}

# Get next pending task for phase
get_next_task() {
  local phase=$1
  local range=${PHASE_TASK_RANGES[$phase]}
  local start_task=${range%-*}
  local end_task=${range#*-}

  # Get first pending or in_progress task in range
  jq -r --arg start "${start_task}" --arg end "${end_task}" \
    '.tasks[] | select(.status == "pending" or .status == "in_progress") | select(.id >= $start and .id <= $end) | .id' \
    "${STATE_FILE}" | head -n 1
}

# Implement a single task
implement_task() {
  local task_id=$1
  local task=$(jq --arg id "${task_id}" '.tasks[] | select(.id == $id)' "${STATE_FILE}")
  local task_title=$(echo "${task}" | jq -r '.title')
  local attempts=$(get_task_attempts "${task_id}")

  log_phase "Task ${task_id}: ${task_title}"

  if [[ ${attempts} -ge ${MAX_TASK_RETRIES} ]]; then
    log_error "Task ${task_id} exceeded max retries (${MAX_TASK_RETRIES})"
    update_task_status "${task_id}" "blocked"
    return 1
  fi

  log "Attempt $((attempts + 1))/${MAX_TASK_RETRIES}"
  update_task_status "${task_id}" "in_progress"

  # Build implementation prompt
  local impl_prompt=$(cat <<EOF
Implement task ${task_id} from docs/IMPLEMENTATION.md: "${task_title}"

CONTEXT:
- Read docs/IMPLEMENTATION.md for full task details
- Read docs/SPEC.md for architecture and design decisions
- Read CLAUDE.md for project-specific conventions
- Check existing code in apps/server, apps/web, packages/shared

INSTRUCTIONS:
1. Read the full task description from IMPLEMENTATION.md
2. Understand dependencies and acceptance criteria
3. Implement the task following project conventions
4. Run /code-quality to validate changes
5. Create atomic commit with /commit (no --split)
6. Output "${TASK_COMPLETE}" when done
7. If blocked, explain why and output "${TASK_BLOCKED}"

FORBIDDEN COMMANDS:
${FORBIDDEN_COMMANDS[@]}

IMPORTANT:
- Follow patterns from existing code
- Use project-specific tools (/code-quality, /commit)
- No AI attribution in commits
- Single atomic commit per task
- Must output completion signal: ${TASK_COMPLETE} or ${TASK_BLOCKED}
EOF
)

  local task_log="${LOGS_DIR}/task-${task_id}.log"
  local output

  if ! output=$(run_claude "${impl_prompt}" "${task_log}"); then
    log_error "Claude failed for task ${task_id}"
    update_task_status "${task_id}" "pending"  # Retry
    return 1
  fi

  # Safety check
  if ! check_safety "${output}"; then
    log_error "Safety check failed for task ${task_id}"
    update_task_status "${task_id}" "blocked"
    return 1
  fi

  # Check completion signals
  if echo "${output}" | grep -q "${TASK_COMPLETE}"; then
    log_success "Task ${task_id} completed"
    update_task_status "${task_id}" "completed"
    return 0
  elif echo "${output}" | grep -q "${TASK_BLOCKED}"; then
    log_warn "Task ${task_id} blocked by Claude"
    update_task_status "${task_id}" "blocked"
    return 1
  else
    log_warn "Task ${task_id} did not output completion signal, marking for retry"
    update_task_status "${task_id}" "pending"
    return 1
  fi
}

# Run a single phase
run_phase() {
  local phase=$1
  local phase_name=${PHASE_NAMES[$phase]}

  log_phase "PHASE ${phase}: ${phase_name}"

  update_phase_status "${phase}" "in_progress"

  # Parse tasks for this phase
  parse_phase_tasks "${phase}"

  # Process tasks sequentially
  local task_id
  local consecutive_failures=0

  while task_id=$(get_next_task "${phase}") && [[ -n "${task_id}" ]]; do
    if implement_task "${task_id}"; then
      consecutive_failures=0
    else
      consecutive_failures=$((consecutive_failures + 1))

      if [[ ${consecutive_failures} -ge 3 ]]; then
        log_error "3 consecutive failures, stopping phase ${phase}"
        return 1
      fi
    fi
  done

  update_phase_status "${phase}" "completed"
  log_success "Phase ${phase} completed"
  return 0
}

# Generate phase report
generate_phase_report() {
  local phase=$1
  local phase_name=${PHASE_NAMES[$phase]}
  local report_log="${LOGS_DIR}/report-phase-${phase}.log"

  log "Generating report for phase ${phase}..."

  # Count tasks
  local completed=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "completed")] | length' "${STATE_FILE}")
  local blocked=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "blocked")] | length' "${STATE_FILE}")
  local pending=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "pending")] | length' "${STATE_FILE}")

  # Build report prompt
  local report_prompt=$(cat <<EOF
Generate a summary report for Phase ${phase}: ${phase_name}.

CONTEXT:
- Read .ralph-logs/state.json for task details
- Read .ralph-logs/task-*.log for implementation logs
- Completed: ${completed} tasks
- Blocked: ${blocked} tasks
- Pending: ${pending} tasks

OUTPUT FORMAT (Markdown):

## Phase ${phase}: ${phase_name}

### Summary
[2-3 sentences about what was accomplished]

### Completed Tasks (${completed})
- Task X.Y: [Brief description]
...

### Blocked Tasks (${blocked})
[If any, list with reasons]

### Issues & Recommendations
[Any problems found or suggestions for next phase]

---

Keep it concise and actionable. Focus on what was done and what needs attention.
EOF
)

  local report=$(run_claude "${report_prompt}" "${report_log}")

  # Append to main report
  echo -e "\n${report}\n" >> "${REPORT_FILE}"

  # Display report
  echo -e "\n${CYAN}════════════════════════════════════════${NC}"
  echo -e "${report}"
  echo -e "${CYAN}════════════════════════════════════════${NC}\n"
}

# Human checkpoint
human_checkpoint() {
  local phase=$1
  local phase_name=${PHASE_NAMES[$phase]}

  echo -e "\n${YELLOW}══════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  HUMAN CHECKPOINT: Phase ${phase} Complete${NC}"
  echo -e "${YELLOW}══════════════════════════════════════════════════════${NC}\n"

  generate_phase_report "${phase}"

  echo -e "${CYAN}Review the implementation and logs in .ralph-logs/${NC}"
  echo -e "${CYAN}Check git commits for changes made${NC}\n"

  echo -e "${YELLOW}What would you like to do?${NC}"
  echo -e "  ${GREEN}1)${NC} Continue to next phase"
  echo -e "  ${YELLOW}2)${NC} Retry this phase"
  echo -e "  ${RED}3)${NC} Stop (resume later with --resume)"
  echo ""

  read -p "Choice [1-3]: " choice

  case ${choice} in
    1)
      log_success "Continuing to next phase..."
      return 0
      ;;
    2)
      log_warn "Retrying phase ${phase}..."
      # Reset phase tasks to pending
      jq --arg p "${phase}" \
        '(.tasks[] | select(.id | startswith($p)) | select(.status != "completed")) |= .status = "pending"' \
        "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"
      update_phase_status "${phase}" "pending"
      return 2  # Signal retry
      ;;
    3)
      log "Stopping. Resume with: ./scripts/ralph-mvp.sh --resume"
      exit 0
      ;;
    *)
      log_error "Invalid choice, stopping"
      exit 1
      ;;
  esac
}

# Main execution
main() {
  local start_phase=1
  local resume=false

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --phase)
        start_phase=$2
        shift 2
        ;;
      --resume)
        resume=true
        shift
        ;;
      *)
        log_error "Unknown option: $1"
        echo "Usage: $0 [--phase N] [--resume]"
        exit 1
        ;;
    esac
  done

  log_phase "OpenNews Ralph MVP Loop v1.0"

  # Initialize state
  init_state

  # Resume from saved phase if requested
  if [[ "${resume}" == true ]]; then
    start_phase=$(get_current_phase)
    log "Resuming from phase ${start_phase}"
  fi

  # Initialize report
  cat > "${REPORT_FILE}" <<EOF
# OpenNews Ralph MVP Implementation Report

Started: $(date)
Script: ralph-mvp.sh

---
EOF

  # Run phases
  for phase in $(seq ${start_phase} 5); do
    local retry=true

    while [[ "${retry}" == true ]]; do
      retry=false

      # Update current phase in state
      jq --arg p "${phase}" '.current_phase = ($p | tonumber)' \
        "${STATE_FILE}" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "${STATE_FILE}"

      # Run phase
      if run_phase "${phase}"; then
        # Human checkpoint
        if human_checkpoint "${phase}"; then
          break  # Continue to next phase
        else
          retry=true  # Retry this phase
        fi
      else
        log_error "Phase ${phase} failed"
        human_checkpoint "${phase}"  # Allow review even on failure
        break
      fi
    done
  done

  # Final summary
  log_phase "Implementation Complete!"

  local total_completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "${STATE_FILE}")
  local total_blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "${STATE_FILE}")
  local total_pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "${STATE_FILE}")

  echo -e "${GREEN}✓ Completed: ${total_completed}${NC}"
  echo -e "${RED}✗ Blocked: ${total_blocked}${NC}"
  echo -e "${YELLOW}⏳ Pending: ${total_pending}${NC}"
  echo -e "\nFull report: ${REPORT_FILE}"
  echo -e "Logs: ${LOGS_DIR}/"
}

# Trap interrupts
trap 'log_error "Interrupted. Resume with: ./scripts/ralph-mvp.sh --resume"; exit 130' SIGINT SIGTERM

# Run main
main "$@"
