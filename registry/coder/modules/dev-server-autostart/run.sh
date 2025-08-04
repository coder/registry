#!/usr/bin/env bash

# Development Server Auto-Start Script
# Automatically detects and starts development servers based on project type

set -euo pipefail

# Default values (can be overridden by environment variables)
WORK_DIR="${WORK_DIR:-/workspaces}"
SCAN_SUBDIRECTORIES="${SCAN_SUBDIRECTORIES:-true}"
MAX_DEPTH="${MAX_DEPTH:-2}"
DEVCONTAINER_INTEGRATION="${DEVCONTAINER_INTEGRATION:-true}"
DEVCONTAINER_SERVICE="${DEVCONTAINER_SERVICE:-}"
DISABLED_FRAMEWORKS="${DISABLED_FRAMEWORKS:-}"
STARTUP_DELAY="${STARTUP_DELAY:-5}"
HEALTH_CHECK_ENABLED="${HEALTH_CHECK_ENABLED:-true}"
LOG_LEVEL="${LOG_LEVEL:-info}"
AUTO_INSTALL_DEPS="${AUTO_INSTALL_DEPS:-true}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-300}"

# Custom commands (injected by Terraform)
${custom_commands}

# Logging setup
LOG_DIR="/tmp/dev-server-autostart"
LOG_FILE="$LOG_DIR/autostart.log"
SERVER_LOG_FILE="$LOG_DIR/server.log"
PID_FILE="$LOG_DIR/autostart.pid"

mkdir -p "$LOG_DIR"

# Logging functions
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$LOG_LEVEL" in
        "debug") allowed_levels="debug info warn error" ;;
        "info")  allowed_levels="info warn error" ;;
        "warn")  allowed_levels="warn error" ;;
        "error") allowed_levels="error" ;;
        *) allowed_levels="info warn error" ;;
    esac
    
    if [[ " $allowed_levels " =~ " $level " ]]; then
        echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
        if [[ "$level" == "error" ]]; then
            echo "[$timestamp] [$level] $message" >&2
        fi
    fi
}

log_debug() { log "debug" "$@"; }
log_info() { log "info" "$@"; }
log_warn() { log "warn" "$@"; }
log_error() { log "error" "$@"; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    rm -f "$PID_FILE"
}

trap cleanup EXIT

# Save PID
echo $$ > "$PID_FILE"

log_info "Starting Development Server Auto-Start"
log_info "Working directory: $WORK_DIR"
log_info "Scan subdirectories: $SCAN_SUBDIRECTORIES"
log_info "Max depth: $MAX_DEPTH"

# Check if work directory exists
if [[ ! -d "$WORK_DIR" ]]; then
    log_warn "Work directory $WORK_DIR does not exist, trying alternative locations..."
    
    # Try alternative common locations
    for alt_dir in "/workspace" "/home/coder" "$HOME" "$(pwd)"; do
        if [[ -d "$alt_dir" ]]; then
            WORK_DIR="$alt_dir"
            log_info "Using alternative directory: $WORK_DIR"
            break
        fi
    done
    
    if [[ ! -d "$WORK_DIR" ]]; then
        log_error "No valid work directory found. Exiting."
        exit 1
    fi
fi

cd "$WORK_DIR"

# Wait for startup delay
if [[ "$STARTUP_DELAY" -gt 0 ]]; then
    log_info "Waiting $STARTUP_DELAY seconds for workspace to initialize..."
    sleep "$STARTUP_DELAY"
fi

# Project detection functions
detect_nodejs() {
    local dir="$1"
    if [[ -f "$dir/package.json" ]]; then
        local pkg_manager="npm"
        local start_cmd="npm start"
        
        # Detect package manager
        if [[ -f "$dir/yarn.lock" ]]; then
            pkg_manager="yarn"
            start_cmd="yarn start"
        elif [[ -f "$dir/pnpm-lock.yaml" ]]; then
            pkg_manager="pnpm"
            start_cmd="pnpm start"
        fi
        
        # Check for Next.js
        if [[ -f "$dir/next.config.js" ]] || [[ -f "$dir/next.config.ts" ]]; then
            start_cmd="$pkg_manager run dev"
            echo "nextjs:$start_cmd"
            return
        fi
        
        # Check for custom start script in package.json
        if command -v jq >/dev/null 2>&1; then
            local scripts=$(jq -r '.scripts // {}' "$dir/package.json" 2>/dev/null || echo '{}')
            if echo "$scripts" | jq -e '.dev' >/dev/null 2>&1; then
                start_cmd="$pkg_manager run dev"
            elif echo "$scripts" | jq -e '.serve' >/dev/null 2>&1; then
                start_cmd="$pkg_manager run serve"
            fi
        fi
        
        echo "node:$start_cmd"
    fi
}

detect_python() {
    local dir="$1"
    
    # Django
    if [[ -f "$dir/manage.py" ]]; then
        echo "django:python manage.py runserver 0.0.0.0:8000"
        return
    fi
    
    # FastAPI
    if [[ -f "$dir/main.py" ]] && grep -q "fastapi\|FastAPI" "$dir/main.py" 2>/dev/null; then
        echo "fastapi:uvicorn main:app --reload --host 0.0.0.0 --port 8000"
        return
    fi
    
    # Flask
    if [[ -f "$dir/app.py" ]] && grep -q "flask\|Flask" "$dir/app.py" 2>/dev/null; then
        echo "flask:python app.py"
        return
    fi
    
    # Generic Python with requirements.txt
    if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]]; then
        if [[ -f "$dir/main.py" ]]; then
            echo "python:python main.py"
        elif [[ -f "$dir/app.py" ]]; then
            echo "python:python app.py"
        fi
    fi
}

detect_ruby() {
    local dir="$1"
    if [[ -f "$dir/Gemfile" ]] && [[ -f "$dir/config/application.rb" ]]; then
        echo "rails:rails server -b 0.0.0.0"
    fi
}

detect_go() {
    local dir="$1"
    if [[ -f "$dir/go.mod" ]]; then
        echo "go:go run ."
    fi
}

detect_java() {
    local dir="$1"
    
    # Maven
    if [[ -f "$dir/pom.xml" ]]; then
        if grep -q "spring-boot" "$dir/pom.xml" 2>/dev/null; then
            echo "java:mvn spring-boot:run"
        else
            echo "java:mvn exec:java"
        fi
        return
    fi
    
    # Gradle
    if [[ -f "$dir/build.gradle" ]] || [[ -f "$dir/build.gradle.kts" ]]; then
        echo "java:gradle bootRun"
    fi
}

detect_php() {
    local dir="$1"
    if [[ -f "$dir/composer.json" ]]; then
        echo "php:php -S 0.0.0.0:8000"
    fi
}

# Install dependencies if needed
install_dependencies() {
    local project_type="$1"
    local dir="$2"
    
    if [[ "$AUTO_INSTALL_DEPS" != "true" ]]; then
        log_debug "Dependency installation disabled"
        return
    fi
    
    log_info "Installing dependencies for $project_type in $dir"
    cd "$dir"
    
    case "$project_type" in
        "node"|"nextjs")
            if [[ -f "yarn.lock" ]]; then
                log_info "Running yarn install..."
                timeout "$TIMEOUT_SECONDS" yarn install
            elif [[ -f "pnpm-lock.yaml" ]]; then
                log_info "Running pnpm install..."
                timeout "$TIMEOUT_SECONDS" pnpm install
            else
                log_info "Running npm install..."
                timeout "$TIMEOUT_SECONDS" npm install
            fi
            ;;
        "python"|"django"|"flask"|"fastapi")
            if [[ -f "requirements.txt" ]]; then
                log_info "Installing Python requirements..."
                timeout "$TIMEOUT_SECONDS" pip install -r requirements.txt
            elif [[ -f "pyproject.toml" ]]; then
                log_info "Installing Python project..."
                timeout "$TIMEOUT_SECONDS" pip install -e .
            fi
            ;;
        "rails")
            log_info "Running bundle install..."
            timeout "$TIMEOUT_SECONDS" bundle install
            ;;
        "go")
            log_info "Running go mod download..."
            timeout "$TIMEOUT_SECONDS" go mod download
            ;;
        "java")
            if [[ -f "pom.xml" ]]; then
                log_info "Running mvn install..."
                timeout "$TIMEOUT_SECONDS" mvn install -DskipTests
            elif [[ -f "build.gradle" ]]; then
                log_info "Running gradle build..."
                timeout "$TIMEOUT_SECONDS" gradle build -x test
            fi
            ;;
        "php")
            log_info "Running composer install..."
            timeout "$TIMEOUT_SECONDS" composer install
            ;;
    esac
}

# Start server in background
start_server() {
    local project_type="$1"
    local command="$2"
    local dir="$3"
    
    log_info "Starting $project_type server in $dir with command: $command"
    
    # Create a unique session name
    local session_name="dev-server-$project_type-$(basename "$dir")"
    
    cd "$dir"
    
    # Start server in tmux session if available, otherwise use nohup
    if command -v tmux >/dev/null 2>&1; then
        tmux new-session -d -s "$session_name" "$command" 2>&1 | tee -a "$SERVER_LOG_FILE"
        log_info "Server started in tmux session: $session_name"
        log_info "To view: tmux attach-session -t $session_name"
    else
        nohup bash -c "$command" >> "$SERVER_LOG_FILE" 2>&1 &
        local pid=$!
        echo "$pid:$project_type:$dir" >> "$LOG_DIR/server_pids.txt"
        log_info "Server started with PID: $pid"
    fi
}

# Health check function
health_check() {
    local port="$1"
    local max_attempts=30
    local attempt=1
    
    log_debug "Checking health on port $port..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "http://localhost:$port" >/dev/null 2>&1; then
            log_info "Server responding on port $port"
            return 0
        fi
        sleep 2
        ((attempt++))
    done
    
    log_warn "Server not responding on port $port after $max_attempts attempts"
    return 1
}

# Parse devcontainer.json
parse_devcontainer() {
    local devcontainer_file=""
    
    # Look for devcontainer.json in common locations
    for file in ".devcontainer/devcontainer.json" ".devcontainer.json"; do
        if [[ -f "$WORK_DIR/$file" ]]; then
            devcontainer_file="$WORK_DIR/$file"
            break
        fi
    done
    
    if [[ -z "$devcontainer_file" ]]; then
        log_debug "No devcontainer.json found"
        return
    fi
    
    log_info "Found devcontainer.json: $devcontainer_file"
    
    if ! command -v jq >/dev/null 2>&1; then
        log_warn "jq not available, skipping devcontainer.json parsing"
        return
    fi
    
    # Execute postCreateCommand if present
    local post_create_cmd=$(jq -r '.postCreateCommand // empty' "$devcontainer_file" 2>/dev/null)
    if [[ -n "$post_create_cmd" && "$post_create_cmd" != "null" ]]; then
        log_info "Executing postCreateCommand: $post_create_cmd"
        cd "$WORK_DIR"
        eval "$post_create_cmd" >> "$SERVER_LOG_FILE" 2>&1 || log_warn "postCreateCommand failed"
    fi
    
    # Execute postStartCommand if present
    local post_start_cmd=$(jq -r '.postStartCommand // empty' "$devcontainer_file" 2>/dev/null)
    if [[ -n "$post_start_cmd" && "$post_start_cmd" != "null" ]]; then
        log_info "Executing postStartCommand: $post_start_cmd"
        cd "$WORK_DIR"
        
        # Start in background
        if command -v tmux >/dev/null 2>&1; then
            tmux new-session -d -s "devcontainer-post-start" "$post_start_cmd" 2>&1 | tee -a "$SERVER_LOG_FILE"
        else
            nohup bash -c "$post_start_cmd" >> "$SERVER_LOG_FILE" 2>&1 &
        fi
    fi
}

# Main scanning function
scan_for_projects() {
    local base_dir="$1"
    local current_depth="${2:-0}"
    
    log_debug "Scanning directory: $base_dir (depth: $current_depth)"
    
    # Check if we've reached max depth
    if [[ $current_depth -ge $MAX_DEPTH ]]; then
        log_debug "Reached maximum depth, stopping scan"
        return
    fi
    
    # Convert disabled frameworks to array
    IFS=',' read -ra DISABLED_ARRAY <<< "$DISABLED_FRAMEWORKS"
    
    # Detect project types in current directory
    local detected_projects=()
    
    # Run detection functions
    for detector in detect_nodejs detect_python detect_ruby detect_go detect_java detect_php; do
        local result=$($detector "$base_dir")
        if [[ -n "$result" ]]; then
            detected_projects+=("$result")
        fi
    done
    
    # Process detected projects
    for project in "${detected_projects[@]}"; do
        IFS=':' read -ra PROJECT_PARTS <<< "$project"
        local project_type="${PROJECT_PARTS[0]}"
        local command="${PROJECT_PARTS[1]}"
        
        # Check if framework is disabled
        local is_disabled=false
        for disabled in "${DISABLED_ARRAY[@]}"; do
            if [[ "$project_type" == "$disabled" ]]; then
                is_disabled=true
                break
            fi
        done
        
        if [[ "$is_disabled" == "true" ]]; then
            log_info "Skipping disabled framework: $project_type"
            continue
        fi
        
        # Check for custom command override
        local custom_var="CUSTOM_CMD_$(echo "$project_type" | tr '[:lower:]' '[:upper:]')"
        if [[ -n "${!custom_var:-}" ]]; then
            command="${!custom_var}"
            log_info "Using custom command for $project_type: $command"
        fi
        
        # Install dependencies and start server
        install_dependencies "$project_type" "$base_dir" || log_warn "Failed to install dependencies for $project_type"
        start_server "$project_type" "$command" "$base_dir"
        
        # Basic health check for common ports
        if [[ "$HEALTH_CHECK_ENABLED" == "true" ]]; then
            case "$project_type" in
                "node"|"nextjs") health_check 3000 ;;
                "django"|"fastapi"|"python") health_check 8000 ;;
                "flask") health_check 5000 ;;
                "rails") health_check 3000 ;;
                "java") health_check 8080 ;;
                "php") health_check 8000 ;;
            esac
        fi
    done
    
    # Recursively scan subdirectories if enabled
    if [[ "$SCAN_SUBDIRECTORIES" == "true" ]]; then
        for subdir in "$base_dir"/*; do
            if [[ -d "$subdir" && "$(basename "$subdir")" != "node_modules" && "$(basename "$subdir")" != ".git" && "$(basename "$subdir")" != "venv" && "$(basename "$subdir")" != "__pycache__" ]]; then
                scan_for_projects "$subdir" $((current_depth + 1))
            fi
        done
    fi
}

# Main execution
main() {
    log_info "Starting project detection and server auto-start"
    
    # Parse devcontainer.json if integration is enabled
    if [[ "$DEVCONTAINER_INTEGRATION" == "true" ]]; then
        parse_devcontainer
    fi
    
    # Scan for projects
    scan_for_projects "$WORK_DIR"
    
    log_info "Development server auto-start completed"
    log_info "Logs available at: $LOG_FILE"
    log_info "Server logs available at: $SERVER_LOG_FILE"
    
    # Display running sessions if tmux is available
    if command -v tmux >/dev/null 2>&1; then
        local sessions=$(tmux list-sessions 2>/dev/null | grep "dev-server" || true)
        if [[ -n "$sessions" ]]; then
            log_info "Running development servers:"
            echo "$sessions" | while read session; do
                log_info "  - $session"
            done
        fi
    fi
}

# Run main function
main "$@"
