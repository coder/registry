#!/bin/bash

set -euo pipefail

# Configuration variables
PROJECT_DIR="${project_dir}"
AUTO_START="${auto_start}"
PORT_RANGE_START="${port_range_start}"
PORT_RANGE_END="${port_range_end}"
LOG_LEVEL="${log_level}"
LOG_FILE="$HOME/.auto-dev-server.log"
PID_DIR="$HOME/.auto-dev-server-pids"

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

# Create PID directory
mkdir -p "$PID_DIR"

# Project detection functions
detect_nodejs() {
    local dir=$1
    if [[ -f "$dir/package.json" ]]; then
        local start_script=$(jq -r '.scripts.start // empty' "$dir/package.json" 2>/dev/null || echo "")
        local dev_script=$(jq -r '.scripts.dev // empty' "$dir/package.json" 2>/dev/null || echo "")
        
        if [[ -n "$dev_script" ]]; then
            echo "npm run dev"
        elif [[ -n "$start_script" ]]; then
            echo "npm start"
        elif [[ -f "$dir/yarn.lock" ]]; then
            echo "yarn start"
        else
            echo "npm start"
        fi
    fi
}

detect_python() {
    local dir=$1
    if [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/setup.py" ]]; then
        if [[ -f "$dir/manage.py" ]]; then
            echo "python manage.py runserver"
        elif [[ -f "$dir/app.py" ]] || [[ -f "$dir/main.py" ]]; then
            if command -v flask >/dev/null 2>&1; then
                echo "flask run"
            else
                echo "python app.py"
            fi
        elif [[ -f "$dir/pyproject.toml" ]] && grep -q "fastapi" "$dir/pyproject.toml" 2>/dev/null; then
            echo "uvicorn main:app --reload"
        fi
    fi
}

detect_ruby() {
    local dir=$1
    if [[ -f "$dir/Gemfile" ]]; then
        if [[ -f "$dir/config.ru" ]]; then
            echo "bundle exec rackup"
        elif [[ -f "$dir/config/application.rb" ]]; then
            echo "bundle exec rails server"
        fi
    fi
}

detect_go() {
    local dir=$1
    if [[ -f "$dir/go.mod" ]] || [[ -f "$dir/main.go" ]]; then
        echo "go run ."
    fi
}

detect_rust() {
    local dir=$1
    if [[ -f "$dir/Cargo.toml" ]]; then
        echo "cargo run"
    fi
}

detect_php() {
    local dir=$1
    if [[ -f "$dir/composer.json" ]] || [[ -f "$dir/index.php" ]]; then
        echo "php -S localhost:8000"
    fi
}

detect_devcontainer() {
    local dir=$1
    local devcontainer_file=""
    
    if [[ -f "$dir/.devcontainer/devcontainer.json" ]]; then
        devcontainer_file="$dir/.devcontainer/devcontainer.json"
    elif [[ -f "$dir/.devcontainer.json" ]]; then
        devcontainer_file="$dir/.devcontainer.json"
    fi
    
    if [[ -n "$devcontainer_file" ]]; then
        # Extract postStartCommand from devcontainer.json
        local post_start_cmd=$(jq -r '.postStartCommand // empty' "$devcontainer_file" 2>/dev/null || echo "")
        if [[ -n "$post_start_cmd" ]]; then
            echo "$post_start_cmd"
        fi
    fi
}

# Find available port
find_available_port() {
    local start_port=$PORT_RANGE_START
    local end_port=$PORT_RANGE_END
    
    for ((port=start_port; port<=end_port; port++)); do
        if ! ss -tuln | grep -q ":$port "; then
            echo $port
            return 0
        fi
    done
    
    log "ERROR" "No available ports in range $start_port-$end_port"
    return 1
}

# Start development server
start_dev_server() {
    local dir=$1
    local command=$2
    local project_name=$(basename "$dir")
    local port=$(find_available_port)
    
    if [[ -z "$port" ]]; then
        log "ERROR" "Could not find available port for $project_name"
        return 1
    fi
    
    log "INFO" "Starting development server for $project_name in $dir"
    log "INFO" "Command: $command"
    log "INFO" "Port: $port"
    
    cd "$dir"
    
    # Modify command to use specific port if possible
    if [[ "$command" == *"npm"* ]] || [[ "$command" == *"yarn"* ]]; then
        command="PORT=$port $command"
    elif [[ "$command" == *"flask"* ]]; then
        command="$command --port $port"
    elif [[ "$command" == *"rails"* ]]; then
        command="$command -p $port"
    elif [[ "$command" == *"uvicorn"* ]]; then
        command="$command --port $port"
    fi
    
    # Start the server in background
    nohup bash -c "$command" > "$HOME/.auto-dev-server-$project_name.log" 2>&1 &
    local pid=$!
    
    # Save PID for cleanup
    echo $pid > "$PID_DIR/$project_name.pid"
    
    log "INFO" "Started $project_name with PID $pid on port $port"
    
    # Create Coder app for the development server
    if command -v coder >/dev/null 2>&1; then
        coder apps create "$project_name-dev" \
            --url "http://localhost:$port" \
            --icon "/icon/code.svg" \
            --display-name "$project_name Development Server" || true
    fi
}

# Main detection and startup logic
scan_and_start_projects() {
    log "INFO" "Scanning for projects in $PROJECT_DIR"
    
    # Find all potential project directories
    find "$PROJECT_DIR" -maxdepth 3 -type f \( \
        -name "package.json" -o \
        -name "requirements.txt" -o \
        -name "pyproject.toml" -o \
        -name "Gemfile" -o \
        -name "go.mod" -o \
        -name "Cargo.toml" -o \
        -name "composer.json" -o \
        -name "devcontainer.json" -o \
        -name ".devcontainer.json" \
    \) | while read -r file; do
        local project_dir=$(dirname "$file")
        local project_name=$(basename "$project_dir")
        
        # Skip if already running
        if [[ -f "$PID_DIR/$project_name.pid" ]] && kill -0 "$(cat "$PID_DIR/$project_name.pid")" 2>/dev/null; then
            log "INFO" "Project $project_name is already running"
            continue
        fi
        
        log "INFO" "Found project: $project_name in $project_dir"
        
        # Try different detection methods
        local command=""
        
        # Check devcontainer first
        command=$(detect_devcontainer "$project_dir")
        if [[ -z "$command" ]]; then
            command=$(detect_nodejs "$project_dir")
        fi
        if [[ -z "$command" ]]; then
            command=$(detect_python "$project_dir")
        fi
        if [[ -z "$command" ]]; then
            command=$(detect_ruby "$project_dir")
        fi
        if [[ -z "$command" ]]; then
            command=$(detect_go "$project_dir")
        fi
        if [[ -z "$command" ]]; then
            command=$(detect_rust "$project_dir")
        fi
        if [[ -z "$command" ]]; then
            command=$(detect_php "$project_dir")
        fi
        
        if [[ -n "$command" ]]; then
            start_dev_server "$project_dir" "$command"
        else
            log "WARN" "No suitable development server command found for $project_name"
        fi
    done
}

# Cleanup function
cleanup_dead_processes() {
    log "INFO" "Cleaning up dead processes"
    
    for pid_file in "$PID_DIR"/*.pid; do
        if [[ -f "$pid_file" ]]; then
            local pid=$(cat "$pid_file")
            local project_name=$(basename "$pid_file" .pid)
            
            if ! kill -0 "$pid" 2>/dev/null; then
                log "INFO" "Cleaning up dead process for $project_name (PID: $pid)"
                rm -f "$pid_file"
            fi
        fi
    done
}

# Install required dependencies
install_dependencies() {
    log "INFO" "Checking and installing dependencies"
    
    # Install jq if not available
    if ! command -v jq >/dev/null 2>&1; then
        log "INFO" "Installing jq"
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y jq
        elif command -v apk >/dev/null 2>&1; then
            sudo apk add jq
        fi
    fi
}

# Main execution
main() {
    log "INFO" "Auto Development Server starting..."
    log "INFO" "Project directory: $PROJECT_DIR"
    log "INFO" "Auto start: $AUTO_START"
    log "INFO" "Port range: $PORT_RANGE_START-$PORT_RANGE_END"
    
    install_dependencies
    cleanup_dead_processes
    
    if [[ "$AUTO_START" == "true" ]]; then
        scan_and_start_projects
    else
        log "INFO" "Auto start is disabled"
    fi
    
    log "INFO" "Auto Development Server completed"
}

# Run main function
main "$@"