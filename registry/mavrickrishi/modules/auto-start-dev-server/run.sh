#!/usr/bin/env bash

set -e

# Color codes for output
BOLD='\033[0;1m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "$${BOLD}🚀 Auto-Start Development Servers$${RESET}"
echo "Workspace Directory: ${WORKSPACE_DIR}"
echo "Log Path: ${LOG_PATH}"
echo "Scan Depth: ${SCAN_DEPTH}"

# Wait for startup delay to allow other setup to complete
if [ "${STARTUP_DELAY}" -gt 0 ]; then
  echo -e "$${YELLOW}⏳ Waiting ${STARTUP_DELAY} seconds for system initialization...$${RESET}"
  sleep "${STARTUP_DELAY}"
fi

# Initialize log file
echo "=== Auto-Start Dev Servers Log ===" > "${LOG_PATH}"
echo "Started at: $(date)" >> "${LOG_PATH}"

# Initialize detected projects JSON file
DETECTED_PROJECTS_FILE="/tmp/detected-projects.json"
echo '[]' > "$DETECTED_PROJECTS_FILE"

# Initialize detected port file for preview app
DETECTED_PORT_FILE="/tmp/detected-port.txt"
FIRST_PORT_DETECTED=false

# Function to log messages
log_message() {
  echo -e "$1"
  echo "$1" >> "${LOG_PATH}"
}

# Function to add detected project to JSON
add_detected_project() {
  local project_dir="$1"
  local project_type="$2"
  local port="$3"
  local command="$4"
  
  # Set the first detected port for preview app
  if [ "$FIRST_PORT_DETECTED" = false ]; then
    echo "$port" > "$DETECTED_PORT_FILE"
    FIRST_PORT_DETECTED=true
    log_message "$${BLUE}🎯 First project detected - Preview app will be available on port $port$${RESET}"
  fi
  
  # Create JSON entry for this project
  local project_json=$(jq -n \
    --arg dir "$project_dir" \
    --arg type "$project_type" \
    --arg port "$port" \
    --arg cmd "$command" \
    '{"directory": $dir, "type": $type, "port": $port, "command": $cmd}')
  
  # Append to the detected projects file
  jq ". += [$project_json]" "$DETECTED_PROJECTS_FILE" > "$DETECTED_PROJECTS_FILE.tmp" && \
    mv "$DETECTED_PROJECTS_FILE.tmp" "$DETECTED_PROJECTS_FILE"
}

# Function to detect and start npm/yarn projects
detect_npm_projects() {
  if [ "${ENABLE_NPM}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Node.js/npm projects...$${RESET}"
  
  # Use find with maxdepth to respect scan depth
  while IFS= read -r -d '' package_json; do
    project_dir=$(dirname "$package_json")
    log_message "$${GREEN}📦 Found Node.js project: $project_dir$${RESET}"
    
    cd "$project_dir"
    
    # Check package.json for start script
    if [ -f "package.json" ] && command -v jq &> /dev/null; then
      start_script=$(jq -r '.scripts.start // empty' package.json)
      dev_script=$(jq -r '.scripts.dev // empty' package.json)
      
      if [ -n "$start_script" ]; then
        log_message "$${GREEN}🟢 Starting npm project with 'npm start' in $project_dir$${RESET}"
        nohup npm start >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "nodejs" "3000" "npm start"
      elif [ -n "$dev_script" ]; then
        log_message "$${GREEN}🟢 Starting npm project with 'npm run dev' in $project_dir$${RESET}"
        nohup npm run dev >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "nodejs" "3000" "npm run dev"
      fi
    elif [ -f "yarn.lock" ] && command -v yarn &> /dev/null; then
      log_message "$${GREEN}🟢 Starting yarn project with 'yarn start' in $project_dir$${RESET}"
      nohup yarn start >> "${LOG_PATH}" 2>&1 &
      add_detected_project "$project_dir" "nodejs" "3000" "yarn start"
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "package.json" -type f -print0)
}

# Function to detect and start Rails projects
detect_rails_projects() {
  if [ "${ENABLE_RAILS}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Ruby on Rails projects...$${RESET}"
  
  while IFS= read -r -d '' gemfile; do
    project_dir=$(dirname "$gemfile")
    log_message "$${GREEN}💎 Found Rails project: $project_dir$${RESET}"
    
    cd "$project_dir"
    
    # Check if it's actually a Rails project
    if grep -q "gem ['\"]rails['\"]" Gemfile 2>/dev/null; then
      log_message "$${GREEN}🟢 Starting Rails server in $project_dir$${RESET}"
      nohup bundle exec rails server >> "${LOG_PATH}" 2>&1 &
      add_detected_project "$project_dir" "rails" "3000" "bundle exec rails server"
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "Gemfile" -type f -print0)
}

# Function to detect and start Django projects
detect_django_projects() {
  if [ "${ENABLE_DJANGO}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Django projects...$${RESET}"
  
  while IFS= read -r -d '' manage_py; do
    project_dir=$(dirname "$manage_py")
    log_message "$${GREEN}🐍 Found Django project: $project_dir$${RESET}"
    
    cd "$project_dir"
    log_message "$${GREEN}🟢 Starting Django development server in $project_dir$${RESET}"
    nohup python manage.py runserver 0.0.0.0:8000 >> "${LOG_PATH}" 2>&1 &
    add_detected_project "$project_dir" "django" "8000" "python manage.py runserver"
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "manage.py" -type f -print0)
}

# Function to detect and start Flask projects
detect_flask_projects() {
  if [ "${ENABLE_FLASK}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Flask projects...$${RESET}"
  
  while IFS= read -r -d '' requirements_txt; do
    project_dir=$(dirname "$requirements_txt")
    
    # Check if Flask is in requirements
    if grep -q -i "flask" "$requirements_txt" 2>/dev/null; then
      log_message "$${GREEN}🌶️ Found Flask project: $project_dir$${RESET}"
      
      cd "$project_dir"
      
      # Look for common Flask app files
      for app_file in app.py main.py run.py; do
        if [ -f "$app_file" ]; then
          log_message "$${GREEN}🟢 Starting Flask application ($app_file) in $project_dir$${RESET}"
          export FLASK_ENV=development
          nohup python "$app_file" >> "${LOG_PATH}" 2>&1 &
          add_detected_project "$project_dir" "flask" "5000" "python $app_file"
          break
        fi
      done
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "requirements.txt" -type f -print0)
}

# Function to detect and start Spring Boot projects
detect_spring_boot_projects() {
  if [ "${ENABLE_SPRING_BOOT}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Spring Boot projects...$${RESET}"
  
  # Maven projects
  while IFS= read -r -d '' pom_xml; do
    project_dir=$(dirname "$pom_xml")
    
    # Check if it's a Spring Boot project
    if grep -q "spring-boot" "$pom_xml" 2>/dev/null; then
      log_message "$${GREEN}🍃 Found Spring Boot Maven project: $project_dir$${RESET}"
      
      cd "$project_dir"
      if command -v ./mvnw &> /dev/null; then
        log_message "$${GREEN}🟢 Starting Spring Boot application with Maven wrapper in $project_dir$${RESET}"
        nohup ./mvnw spring-boot:run >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "spring-boot" "8080" "./mvnw spring-boot:run"
      elif command -v mvn &> /dev/null; then
        log_message "$${GREEN}🟢 Starting Spring Boot application with Maven in $project_dir$${RESET}"
        nohup mvn spring-boot:run >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "spring-boot" "8080" "mvn spring-boot:run"
      fi
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "pom.xml" -type f -print0)
  
  # Gradle projects
  while IFS= read -r -d '' build_gradle; do
    project_dir=$(dirname "$build_gradle")
    
    # Check if it's a Spring Boot project
    if grep -q "spring-boot" "$build_gradle" 2>/dev/null; then
      log_message "$${GREEN}🍃 Found Spring Boot Gradle project: $project_dir$${RESET}"
      
      cd "$project_dir"
      if command -v ./gradlew &> /dev/null; then
        log_message "$${GREEN}🟢 Starting Spring Boot application with Gradle wrapper in $project_dir$${RESET}"
        nohup ./gradlew bootRun >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "spring-boot" "8080" "./gradlew bootRun"
      elif command -v gradle &> /dev/null; then
        log_message "$${GREEN}🟢 Starting Spring Boot application with Gradle in $project_dir$${RESET}"
        nohup gradle bootRun >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "spring-boot" "8080" "gradle bootRun"
      fi
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "build.gradle" -type f -print0)
}

# Function to detect and start Go projects
detect_go_projects() {
  if [ "${ENABLE_GO}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Go projects...$${RESET}"
  
  while IFS= read -r -d '' go_mod; do
    project_dir=$(dirname "$go_mod")
    log_message "$${GREEN}🐹 Found Go project: $project_dir$${RESET}"
    
    cd "$project_dir"
    
    # Look for main.go or check if there's a main function
    if [ -f "main.go" ]; then
      log_message "$${GREEN}🟢 Starting Go application in $project_dir$${RESET}"
      nohup go run main.go >> "${LOG_PATH}" 2>&1 &
      add_detected_project "$project_dir" "go" "8080" "go run main.go"
    elif [ -f "cmd/main.go" ]; then
      log_message "$${GREEN}🟢 Starting Go application (cmd/main.go) in $project_dir$${RESET}"
      nohup go run cmd/main.go >> "${LOG_PATH}" 2>&1 &
      add_detected_project "$project_dir" "go" "8080" "go run cmd/main.go"
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "go.mod" -type f -print0)
}

# Function to detect and start PHP projects
detect_php_projects() {
  if [ "${ENABLE_PHP}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for PHP projects...$${RESET}"
  
  while IFS= read -r -d '' composer_json; do
    project_dir=$(dirname "$composer_json")
    log_message "$${GREEN}🐘 Found PHP project: $project_dir$${RESET}"
    
    cd "$project_dir"
    
    # Look for common PHP entry points
    for entry_file in index.php public/index.php; do
      if [ -f "$entry_file" ]; then
        log_message "$${GREEN}🟢 Starting PHP development server in $project_dir$${RESET}"
        nohup php -S 0.0.0.0:8080 -t "$(dirname "$entry_file")" >> "${LOG_PATH}" 2>&1 &
        add_detected_project "$project_dir" "php" "8080" "php -S 0.0.0.0:8080"
        break
      fi
    done
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "composer.json" -type f -print0)
}

# Function to detect and start Rust projects
detect_rust_projects() {
  if [ "${ENABLE_RUST}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for Rust projects...$${RESET}"
  
  while IFS= read -r -d '' cargo_toml; do
    project_dir=$(dirname "$cargo_toml")
    log_message "$${GREEN}🦀 Found Rust project: $project_dir$${RESET}"
    
    cd "$project_dir"
    
    # Check if it's a binary project (has [[bin]] or default main.rs)
    if grep -q "\[\[bin\]\]" Cargo.toml 2>/dev/null || [ -f "src/main.rs" ]; then
      log_message "$${GREEN}🟢 Starting Rust application in $project_dir$${RESET}"
      nohup cargo run >> "${LOG_PATH}" 2>&1 &
      add_detected_project "$project_dir" "rust" "8000" "cargo run"
    fi
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "Cargo.toml" -type f -print0)
}

# Function to detect and start .NET projects
detect_dotnet_projects() {
  if [ "${ENABLE_DOTNET}" != "true" ]; then
    return
  fi
  
  log_message "$${BLUE}🔍 Scanning for .NET projects...$${RESET}"
  
  while IFS= read -r -d '' csproj; do
    project_dir=$(dirname "$csproj")
    log_message "$${GREEN}🔷 Found .NET project: $project_dir$${RESET}"
    
    cd "$project_dir"
    log_message "$${GREEN}🟢 Starting .NET application in $project_dir$${RESET}"
    nohup dotnet run >> "${LOG_PATH}" 2>&1 &
    add_detected_project "$project_dir" "dotnet" "5000" "dotnet run"
    
  done < <(find "${WORKSPACE_DIR}" -maxdepth "${SCAN_DEPTH}" -name "*.csproj" -type f -print0)
}

# Main execution
main() {
  log_message "Starting auto-detection of development projects..."
  
  # Expand workspace directory if it contains variables
  WORKSPACE_DIR=$(eval echo "${WORKSPACE_DIR}")
  
  # Check if workspace directory exists
  if [ ! -d "$WORKSPACE_DIR" ]; then
    log_message "$${RED}❌ Workspace directory does not exist: $WORKSPACE_DIR$${RESET}"
    exit 1
  fi
  
  cd "$WORKSPACE_DIR"
  
  # Run all detection functions
  detect_npm_projects
  detect_rails_projects
  detect_django_projects
  detect_flask_projects
  detect_spring_boot_projects
  detect_go_projects
  detect_php_projects
  detect_rust_projects
  detect_dotnet_projects
  
  log_message "$${GREEN}✅ Auto-start scan completed!$${RESET}"
  log_message "$${YELLOW}💡 Check running processes with 'ps aux | grep -E \"(npm|rails|python|java|go|php|cargo|dotnet)\"'$${RESET}"
  log_message "$${YELLOW}💡 View logs: tail -f ${LOG_PATH}$${RESET}"
  
  # Set default port if no projects were detected
  if [ "$FIRST_PORT_DETECTED" = false ]; then
    echo "3000" > "$DETECTED_PORT_FILE"
    log_message "$${YELLOW}⚠️ No projects detected - Preview app will default to port 3000$${RESET}"
  fi
}

# Run main function
main "$@"