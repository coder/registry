#!/bin/bash

# Auto Development Server Script
# Automatically detects and starts development servers based on project structure

set -euo pipefail

# Configuration from Terraform variables
PROJECT_DIR="PROJECT_DIR_PLACEHOLDER"
ENABLED_FRAMEWORKS='ENABLED_FRAMEWORKS_PLACEHOLDER'
FRAMEWORK_COMMANDS='FRAMEWORK_COMMANDS_PLACEHOLDER'
DETECTION_PATTERNS='DETECTION_PATTERNS_PLACEHOLDER'
START_DELAY=START_DELAY_PLACEHOLDER
LOG_LEVEL="LOG_LEVEL_PLACEHOLDER"
USE_DEVCONTAINER=USE_DEVCONTAINER_PLACEHOLDER

# Expand variables like $HOME
PROJECT_DIR=$(eval echo "$PROJECT_DIR")
LOG_FILE="$PROJECT_DIR/auto-dev-server.log"
PID_DIR="$PROJECT_DIR/.auto-dev-server"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $LOG_LEVEL in
        "DEBUG") [[ "$level" =~ ^(DEBUG|INFO|WARN|ERROR)$ ]] && echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" ;;
        "INFO")  [[ "$level" =~ ^(INFO|WARN|ERROR)$ ]] && echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" ;;
        "WARN")  [[ "$level" =~ ^(WARN|ERROR)$ ]] && echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" ;;
        "ERROR") [[ "$level" == "ERROR" ]] && echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Parse JSON arrays from Terraform
parse_json() {
    echo "$1" | jq -r '.[]' 2>/dev/null || echo ""
}

# Parse JSON objects from Terraform
parse_json_object() {
    echo "$1" | jq -r 'to_entries[] | "\(.key)=\(.value)"' 2>/dev/null || echo ""
}

# Create necessary directories
mkdir -p "$PID_DIR"
touch "$LOG_FILE"

log "INFO" "Auto Development Server starting..."
log "DEBUG" "Project directory: $PROJECT_DIR"
log "DEBUG" "Enabled frameworks: $(echo "$ENABLED_FRAMEWORKS" | jq -c .)"

# Wait for workspace to initialize
log "INFO" "Waiting $START_DELAY seconds for workspace initialization..."
sleep "$START_DELAY"

# Check if devcontainer.json exists and extract startup commands
check_devcontainer() {
    local dir="$1"
    local devcontainer_files=(".devcontainer/devcontainer.json" ".devcontainer.json")
    
    for file in "${devcontainer_files[@]}"; do
        local devcontainer_path="$dir/$file"
        if [[ -f "$devcontainer_path" ]]; then
            log "INFO" "Found devcontainer config: $devcontainer_path"
            
            # Extract postStartCommand or postCreateCommand
            local post_start=$(jq -r '.postStartCommand // empty' "$devcontainer_path" 2>/dev/null)
            local post_create=$(jq -r '.postCreateCommand // empty' "$devcontainer_path" 2>/dev/null)
            
            if [[ -n "$post_start" ]]; then
                log "INFO" "Found postStartCommand in devcontainer: $post_start"
                echo "$post_start"
                return 0
            elif [[ -n "$post_create" ]]; then
                log "INFO" "Found postCreateCommand in devcontainer: $post_create"
                echo "$post_create"
                return 0
            fi
        fi
    done
    
    return 1
}

# Detect framework type in a directory
detect_framework() {
    local dir="$1"
    local detected_frameworks=()
    
    log "DEBUG" "Scanning directory: $dir"
    
    # Parse detection patterns
    while IFS= read -r pattern_line; do
        [[ -z "$pattern_line" ]] && continue
        
        local framework=$(echo "$pattern_line" | cut -d'=' -f1)
        local patterns=$(echo "$pattern_line" | cut -d'=' -f2-)
        
        # Check if framework is enabled
        if echo "$ENABLED_FRAMEWORKS" | jq -e --arg fw "$framework" 'index($fw)' >/dev/null 2>&1; then
            log "DEBUG" "Checking $framework patterns: $patterns"
            
            # Split patterns by |
            IFS='|' read -ra PATTERN_ARRAY <<< "$patterns"
            for pattern in "${PATTERN_ARRAY[@]}"; do
                if [[ -e "$dir/$pattern" ]] || find "$dir" -name "$pattern" -type f -print -quit 2>/dev/null | grep -q .; then
                    log "INFO" "Detected $framework project in $dir (matched: $pattern)"
                    detected_frameworks+=("$framework")
                    break
                fi
            done
        fi
    done <<< "$(parse_json_object "$DETECTION_PATTERNS")"
    
    printf '%s\n' "${detected_frameworks[@]}"
}

# Start development server for a framework
start_dev_server() {
    local framework="$1"
    local project_path="$2"
    local custom_command="$3"
    
    # Get the command for this framework
    local command=""
    if [[ -n "$custom_command" ]]; then
        command="$custom_command"
    else
        command=$(echo "$FRAMEWORK_COMMANDS" | jq -r --arg fw "$framework" '.[$fw] // empty')
    fi
    
    if [[ -z "$command" ]]; then
        log "ERROR" "No start command defined for framework: $framework"
        return 1
    fi
    
    local pid_file="$PID_DIR/${framework}.pid"
    local log_file="$PID_DIR/${framework}.log"
    
    # Check if server is already running
    if [[ -f "$pid_file" ]] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
        log "WARN" "$framework server already running (PID: $(cat "$pid_file"))"
        return 0
    fi
    
    log "INFO" "Starting $framework server in $project_path"
    log "INFO" "Command: $command"
    
    # Start the server in background
    cd "$project_path"
    (
        # Set environment variables for development
        export NODE_ENV=development
        export RAILS_ENV=development
        export FLASK_ENV=development
        export DEBUG=true
        
        # Execute the command
        bash -c "$command" > "$log_file" 2>&1 &
        echo $! > "$pid_file"
        log "INFO" "$framework server started with PID $! (logs: $log_file)"
    )
}

# Stop all running servers
stop_all_servers() {
    log "INFO" "Stopping all development servers..."
    
    for pid_file in "$PID_DIR"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        
        local framework=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        
        if kill -0 "$pid" 2>/dev/null; then
            log "INFO" "Stopping $framework server (PID: $pid)"
            kill "$pid" || kill -9 "$pid" 2>/dev/null
        fi
        
        rm -f "$pid_file"
    done
}

# Signal handlers
trap stop_all_servers EXIT INT TERM

# Main scanning and detection logic
scan_projects() {
    local base_dir="$PROJECT_DIR"
    
    # Ensure base directory exists
    if [[ ! -d "$base_dir" ]]; then
        log "ERROR" "Project directory does not exist: $base_dir"
        return 1
    fi
    
    log "INFO" "Scanning for projects in: $base_dir"
    
    # Scan current directory and subdirectories (max depth 3)
    local scanned_dirs=()
    
    # Add current directory
    scanned_dirs+=("$base_dir")
    
    # Add subdirectories
    while IFS= read -r -d '' dir; do
        scanned_dirs+=("$dir")
    done < <(find "$base_dir" -maxdepth 3 -type d -print0 2>/dev/null)
    
    local servers_started=0
    local processed_frameworks=()
    
    for dir in "${scanned_dirs[@]}"; do
        # Skip hidden directories and common non-project dirs
        [[ "$(basename "$dir")" =~ ^\. ]] && continue
        [[ "$(basename "$dir")" =~ ^(node_modules|vendor|target|build|dist|__pycache__|\.git)$ ]] && continue
        
        # Check for devcontainer first if enabled
        local devcontainer_command=""
        if [[ "$USE_DEVCONTAINER" == "true" ]]; then
            devcontainer_command=$(check_devcontainer "$dir") || true
        fi
        
        # Detect frameworks in this directory
        local frameworks=($(detect_framework "$dir"))
        
        for framework in "${frameworks[@]}"; do
            # Skip if we already processed this framework
            if [[ " ${processed_frameworks[*]} " =~ " $framework " ]]; then
                log "DEBUG" "Framework $framework already processed, skipping"
                continue
            fi
            
            # Start the server
            if start_dev_server "$framework" "$dir" "$devcontainer_command"; then
                servers_started=$((servers_started + 1))
                processed_frameworks+=("$framework")
            fi
        done
    done
    
    if [[ $servers_started -eq 0 ]]; then
        log "INFO" "No development projects detected or all servers already running"
    else
        log "INFO" "Started $servers_started development server(s)"
    fi
}

# Health check function
health_check() {
    local healthy_servers=0
    local total_servers=0
    
    for pid_file in "$PID_DIR"/*.pid; do
        [[ -f "$pid_file" ]] || continue
        
        total_servers=$((total_servers + 1))
        local framework=$(basename "$pid_file" .pid)
        local pid=$(cat "$pid_file")
        
        if kill -0 "$pid" 2>/dev/null; then
            healthy_servers=$((healthy_servers + 1))
            log "DEBUG" "$framework server is healthy (PID: $pid)"
        else
            log "WARN" "$framework server is not responding (PID: $pid)"
            rm -f "$pid_file"
        fi
    done
    
    log "INFO" "Health check: $healthy_servers/$total_servers servers healthy"
}

# Main execution
main() {
    log "INFO" "=== Auto Development Server Started ==="
    
    # Ensure required tools are available
    for tool in jq find; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            log "ERROR" "Required tool not found: $tool"
            log "INFO" "Installing $tool..."
            # Try to install jq if missing
            if [[ "$tool" == "jq" ]]; then
                if command -v apt-get >/dev/null 2>&1; then
                    sudo apt-get update && sudo apt-get install -y jq
                elif command -v yum >/dev/null 2>&1; then
                    sudo yum install -y jq
                elif command -v brew >/dev/null 2>&1; then
                    brew install jq
                else
                    log "ERROR" "Cannot install jq automatically. Please install manually."
                    exit 1
                fi
            fi
        fi
    done
    
    # Run the main scanning
    scan_projects
    
    # Keep running and do periodic health checks
    while true; do
        sleep 60
        health_check
    done
}

# Run main function
main "$@"
