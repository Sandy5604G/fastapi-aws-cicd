#!/usr/bin/env bash
# ==============================================================================
# FastAPI AWS CI/CD — Realtime CMD Automation (Git, Jenkins, Ruff, Pytest, Docker)
# ==============================================================================
set -euo pipefail

# Project root resolution (resolves symlinks cleanly)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
PROJECT_DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
cd "$PROJECT_DIR"

# Color definitions
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() { echo -e "${CYAN}ℹ️  ${BOLD}$1${NC}"; }
log_success() { echo -e "${GREEN}✅ ${BOLD}$1${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  ${BOLD}$1${NC}"; }
log_error() { echo -e "${RED}❌ ${BOLD}$1${NC}"; }
log_step() { echo -e "\n${MAGENTA}▶ ${BOLD}$1${NC}"; }

# Jenkins & AWS Config
JENKINS_URL="${JENKINS_URL:-http://65.1.87.197:8080}"
ALB_URL="${ALB_URL:-http://fastapi-cicd-alb-1317333918.ap-south-1.elb.amazonaws.com}"

cmd_help() {
    echo -e "${CYAN}${BOLD}========================================================================${NC}"
    echo -e "${BOLD}FastAPI AWS CI/CD — Command Center Tool (CMD Automation)${NC}"
    echo -e "${CYAN}${BOLD}========================================================================${NC}"
    echo "Usage: ./cicd.sh <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  format           Format & auto-fix Python code with Ruff"
    echo "  lint             Verify code compliance with Ruff linter"
    echo "  test             Run Pytest test suite with coverage enforcement (>=80%)"
    echo "  build            Build local Docker container image"
    echo "  commit [msg]     Format, run tests, stage changes and commit to Git"
    echo "  push             Push committed changes to GitHub (triggers Jenkins CI/CD)"
    echo "  release [msg]    Full Pipeline: Format -> Test -> Build -> Commit -> Push"
    echo "  status           Display current Git, Docker, and AWS / Jenkins status"
    echo "  start | serve    Launch local FastAPI backend and Control Center dashboard"
    echo "  trigger          Simulate a demo commit update and push immediately"
    echo "  help             Show this guidance menu"
    echo ""
    echo "Examples:"
    echo "  ./cicd.sh format"
    echo "  ./cicd.sh test"
    echo "  ./cicd.sh commit 'feat: add health ping metric'"
    echo "  ./cicd.sh release 'feat: upgrade container build'"
    echo "  ./cicd.sh start"
    echo -e "${CYAN}========================================================================${NC}"
}

cmd_format() {
    log_step "Formatting Python codebase with Ruff..."
    python3 -m ruff format app tests
    log_step "Auto-fixing linting issues with Ruff..."
    python3 -m ruff check --fix app tests
    log_success "Formatting & lint fixing completed successfully."
}

cmd_lint() {
    log_step "Checking code compliance with Ruff (Quality Gate)..."
    python3 -m ruff check app tests
    python3 -m ruff format --check app tests
    log_success "Code lint and format quality checks passed."
}

cmd_test() {
    log_step "Executing Pytest test suite with coverage analysis..."
    python3 -m pytest tests/ -v --cov=app --cov-report=term-missing --cov-fail-under=80
    log_success "All unit tests passed with required coverage threshold (>=80%)."
}

cmd_build() {
    log_step "Building container image with Docker..."
    GIT_SHA=$(git rev-parse --short=8 HEAD 2>/dev/null || echo "local")
    docker build --build-arg APP_VERSION="${GIT_SHA}" -t fastapi-cicd:local .
    log_success "Docker build completed. Tagged as 'fastapi-cicd:local' (Version: ${GIT_SHA})."
}

cmd_commit() {
    local msg="${1:-}"
    if [ -z "$msg" ]; then
        TIME_STAMP=$(date +'%H:%M:%S')
        msg="feat: code update at ${TIME_STAMP}"
    fi

    # Run format & test before committing
    cmd_format
    cmd_test

    log_step "Staging files and creating Git commit..."
    git add -A
    
    # Check if there are changes to commit
    if git diff-index --quiet HEAD -- 2>/dev/null; then
        log_warn "No changes detected to commit in repository."
    else
        git commit -m "$msg"
        log_success "Created commit: $(git log -1 --oneline)"
    fi
}

cmd_push() {
    log_step "Pushing commit to remote repository on GitHub..."
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    git push origin "$branch"
    log_success "Pushed to origin/${branch} successfully!"
    echo -e "${CYAN}ℹ️  GitHub webhook / SCM polling will trigger Jenkins CI/CD on: ${JENKINS_URL}${NC}"
}

cmd_release() {
    local msg="${1:-}"
    if [ -z "$msg" ]; then
        TIME_STAMP=$(date +'%H:%M:%S')
        msg="feat: automated release at ${TIME_STAMP}"
    fi

    echo -e "\n${BOLD}${CYAN}🚀 Executing Full CI/CD Release Pipeline...${NC}\n"
    cmd_format
    cmd_test
    cmd_build
    cmd_commit "$msg"
    cmd_push
    echo -e "\n${GREEN}${BOLD}🎉 Full Realtime CI/CD Execution Finished!${NC}"
    echo -e "${CYAN}👉 Jenkins Server:  ${JENKINS_URL}${NC}"
    echo -e "${CYAN}👉 AWS Live ALB:    ${ALB_URL}/version${NC}"
    echo -e "${CYAN}👉 Swagger Docs:    ${ALB_URL}/docs${NC}\n"
}

cmd_status() {
    log_step "Project & CI/CD Status Overview"
    echo -e "📁 Directory:       ${PWD}"
    echo -e "🌿 Git Branch:      $(git rev-parse --abbrev-ref HEAD)"
    echo -e "🏷️  Latest Commit:   $(git log -1 --oneline)"
    
    echo -e "\n${BOLD}--- Git Status ---${NC}"
    git status -s
    
    echo -e "\n${BOLD}--- Docker Local Images ---${NC}"
    docker images fastapi-cicd --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" 2>/dev/null || echo "No local docker image found."
    
    echo -e "\n${BOLD}--- Endpoints ---${NC}"
    echo -e "Jenkins:     ${JENKINS_URL}"
    echo -e "Live ALB:    ${ALB_URL}"
}

cmd_start() {
    log_step "Starting local FastAPI Backend and React Control Center..."
    ./run.sh
}

cmd_trigger() {
    log_step "Executing demo timestamp trigger update..."
    sed -i '/# Demo live update/d' app/main.py
    echo "" >> app/main.py
    echo "# Demo live update $(date)" >> app/main.py
    NEW_TIME=$(date +'%H:%M:%S')
    cmd_release "feat: live demo release at ${NEW_TIME}"
}

# Main command dispatch
ACTION="${1:-help}"
shift 2>/dev/null || true

case "$ACTION" in
    format)
        cmd_format
        ;;
    lint)
        cmd_lint
        ;;
    test)
        cmd_test
        ;;
    build)
        cmd_build
        ;;
    commit)
        cmd_commit "$@"
        ;;
    push)
        cmd_push
        ;;
    release|deploy|all)
        cmd_release "$@"
        ;;
    status)
        cmd_status
        ;;
    start|serve)
        cmd_start
        ;;
    trigger)
        cmd_trigger
        ;;
    help|--help|-h)
        cmd_help
        ;;
    *)
        log_error "Unknown command: ${ACTION}"
        cmd_help
        exit 1
        ;;
esac
