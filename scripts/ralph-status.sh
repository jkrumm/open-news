#!/usr/bin/env bash
set -euo pipefail

################################################################################
# OpenNews Ralph Status Viewer
#
# Quick status overview of RALPH MVP implementation progress
#
# Usage: ./scripts/ralph-status.sh [--verbose]
################################################################################

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

readonly STATE_FILE=".ralph-logs/state.json"
readonly REPORT_FILE=".ralph-logs/RALPH_REPORT.md"

if [[ ! -f "${STATE_FILE}" ]]; then
  echo -e "${RED}✗ No RALPH state found${NC}"
  echo "Run ./scripts/ralph-mvp.sh to start implementation"
  exit 1
fi

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
  VERBOSE=true
fi

# Phase names
declare -A PHASE_NAMES=(
  [1]="Project Setup"
  [2]="Backend Core"
  [3]="AI Pipeline"
  [4]="Frontend"
  [5]="Polish"
)

echo -e "\n${BLUE}═══════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  OpenNews Ralph MVP - Status${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}\n"

# Current phase
current_phase=$(jq -r '.current_phase' "${STATE_FILE}")
echo -e "${CYAN}Current Phase:${NC} ${current_phase} - ${PHASE_NAMES[$current_phase]}\n"

# Phase summary
echo -e "${CYAN}Phase Summary:${NC}\n"

for phase in {1..5}; do
  phase_status=$(jq -r --arg p "${phase}" '.phases[$p].status' "${STATE_FILE}")
  phase_name=${PHASE_NAMES[$phase]}

  case ${phase_status} in
    completed)
      icon="${GREEN}✓${NC}"
      ;;
    in_progress)
      icon="${YELLOW}●${NC}"
      ;;
    pending)
      icon="${CYAN}○${NC}"
      ;;
    *)
      icon="?"
      ;;
  esac

  # Count tasks for this phase
  completed=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "completed")] | length' "${STATE_FILE}")
  blocked=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "blocked")] | length' "${STATE_FILE}")
  pending=$(jq --arg p "${phase}" '[.tasks[] | select(.id | startswith($p)) | select(.status == "pending")] | length' "${STATE_FILE}")
  total=$((completed + blocked + pending))

  if [[ ${total} -eq 0 ]]; then
    # Phase not yet parsed
    echo -e "  ${icon} Phase ${phase}: ${phase_name} ${CYAN}(not started)${NC}"
  else
    echo -e "  ${icon} Phase ${phase}: ${phase_name}"
    echo -e "     ${GREEN}${completed}${NC} completed | ${RED}${blocked}${NC} blocked | ${YELLOW}${pending}${NC} pending | ${total} total"
  fi
done

# Overall statistics
echo -e "\n${CYAN}Overall Progress:${NC}\n"

total_completed=$(jq '[.tasks[] | select(.status == "completed")] | length' "${STATE_FILE}")
total_blocked=$(jq '[.tasks[] | select(.status == "blocked")] | length' "${STATE_FILE}")
total_pending=$(jq '[.tasks[] | select(.status == "pending")] | length' "${STATE_FILE}")
total_in_progress=$(jq '[.tasks[] | select(.status == "in_progress")] | length' "${STATE_FILE}")
total_tasks=$(jq '[.tasks[]] | length' "${STATE_FILE}")

echo -e "  ${GREEN}✓ Completed:${NC}    ${total_completed}"
echo -e "  ${RED}✗ Blocked:${NC}      ${total_blocked}"
echo -e "  ${YELLOW}⏳ Pending:${NC}     ${total_pending}"
echo -e "  ${BLUE}● In Progress:${NC}  ${total_in_progress}"
echo -e "  ${CYAN}Total Tasks:${NC}   ${total_tasks}"

if [[ ${total_tasks} -gt 0 ]]; then
  completion_pct=$(echo "scale=1; ${total_completed} * 100 / ${total_tasks}" | bc)
  echo -e "\n  Completion: ${completion_pct}%"
fi

# Verbose mode: show task details
if [[ "${VERBOSE}" == true ]]; then
  echo -e "\n${CYAN}Task Details:${NC}\n"

  jq -r '.tasks[] | "\(.id) | \(.title) | \(.status) | \(.attempts)"' "${STATE_FILE}" | \
    while IFS='|' read -r id title status attempts; do
      id=$(echo "${id}" | xargs)
      title=$(echo "${title}" | xargs)
      status=$(echo "${status}" | xargs)
      attempts=$(echo "${attempts}" | xargs)

      case ${status} in
        completed)
          icon="${GREEN}✓${NC}"
          ;;
        blocked)
          icon="${RED}✗${NC}"
          ;;
        in_progress)
          icon="${YELLOW}●${NC}"
          ;;
        pending)
          icon="${CYAN}○${NC}"
          ;;
      esac

      echo -e "  ${icon} ${id}: ${title} ${CYAN}(${attempts} attempts)${NC}"
    done
fi

# Recent activity (last 5 completed tasks)
echo -e "\n${CYAN}Recent Activity:${NC}\n"

recent=$(jq -r '[.tasks[] | select(.status == "completed") | select(.completed_at != null)] | sort_by(.completed_at) | reverse | .[0:5] | .[] | "\(.id) | \(.title) | \(.completed_at)"' "${STATE_FILE}")

if [[ -n "${recent}" ]]; then
  echo "${recent}" | while IFS='|' read -r id title completed_at; do
    id=$(echo "${id}" | xargs)
    title=$(echo "${title}" | xargs)
    completed_at=$(echo "${completed_at}" | xargs)

    echo -e "  ${GREEN}✓${NC} ${id}: ${title} ${CYAN}(${completed_at})${NC}"
  done
else
  echo -e "  ${YELLOW}No completed tasks yet${NC}"
fi

# Blocked tasks (if any)
blocked_tasks=$(jq -r '[.tasks[] | select(.status == "blocked")] | .[] | "\(.id) | \(.title)"' "${STATE_FILE}")

if [[ -n "${blocked_tasks}" ]]; then
  echo -e "\n${RED}⚠ Blocked Tasks:${NC}\n"

  echo "${blocked_tasks}" | while IFS='|' read -r id title; do
    id=$(echo "${id}" | xargs)
    title=$(echo "${title}" | xargs)

    echo -e "  ${RED}✗${NC} ${id}: ${title}"
    echo -e "     ${CYAN}→ Check .ralph-logs/task-${id}.log for details${NC}"
  done
fi

# Report link
if [[ -f "${REPORT_FILE}" ]]; then
  echo -e "\n${CYAN}Full Report:${NC} ${REPORT_FILE}"
fi

echo -e "\n${CYAN}Logs Directory:${NC} .ralph-logs/\n"
