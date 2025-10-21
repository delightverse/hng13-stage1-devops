#!/bin/bash

# DevOps Stage 1 - Automated Deployment Script
# Author: HNG DevOps Intern
# Version: 1.0
# Description: Automated deployment script for Dockerized applications

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Exit codes for different error types
readonly EXIT_SUCCESS=0
readonly EXIT_ERROR_INPUT=1
readonly EXIT_ERROR_GIT=2
readonly EXIT_ERROR_SSH=3
readonly EXIT_ERROR_DOCKER=4
readonly EXIT_ERROR_NGINX=5
readonly EXIT_ERROR_VALIDATION=6
readonly EXIT_ERROR_REMOTE=7
readonly EXIT_ERROR_FILE_TRANSFER=8

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/deploy_$(date +%Y%m%d_%H%M%S).log"
CLEANUP_MODE=false
PROJECT_NAME=""
CONTAINER_NAME=""
NGINX_CONFIG_NAME=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE"
            ;;
        "DEBUG")
            echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE"
            ;;
    esac
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Error handling function
handle_error() {
    local exit_code=$?
    local line_number=$1
    log "ERROR" "Script failed at line $line_number with exit code $exit_code"
    log "ERROR" "Check the log file: $LOG_FILE"
    exit $exit_code
}

# Set up error trap
trap 'handle_error $LINENO' ERR

# Cleanup function
cleanup() {
    log "INFO" "Performing cleanup operations..."
    # Add cleanup operations here if needed
}

# Set up exit trap for cleanup
trap cleanup EXIT

# Input validation functions
validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/.* ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 1
    fi
    
    # Check if each octet is valid (0-255)
    IFS='.' read -ra ADDR <<< "$ip"
    for i in "${ADDR[@]}"; do
        if [[ $i -gt 255 ]]; then
            return 1
        fi
    done
    return 0
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

# Function to collect user input
collect_user_input() {
    log "INFO" "Collecting deployment parameters..."
    
    # Git Repository URL
    while true; do
        read -p "Enter Git Repository URL: " REPO_URL
        if validate_url "$REPO_URL"; then
            break
        else
            log "ERROR" "Invalid URL format. Please enter a valid Git repository URL."
        fi
    done
    
    # Personal Access Token
    read -s -p "Enter Personal Access Token (PAT): " PAT
    echo
    if [[ -z "$PAT" ]]; then
        log "ERROR" "PAT cannot be empty"
        exit $EXIT_ERROR_INPUT
    fi
    
    # Branch name (optional, defaults to main)
    read -p "Enter branch name (default: main): " BRANCH
    BRANCH="${BRANCH:-main}"
    
    # SSH details
    read -p "Enter SSH username: " SSH_USER
    if [[ -z "$SSH_USER" ]]; then
        log "ERROR" "SSH username cannot be empty"
        exit $EXIT_ERROR_INPUT
    fi
    
    # Server IP
    while true; do
        read -p "Enter server IP address: " SERVER_IP
        if validate_ip "$SERVER_IP"; then
            break
        else
            log "ERROR" "Invalid IP address format"
        fi
    done
    
    # SSH key path
    read -p "Enter SSH key path (default: ~/.ssh/id_rsa): " SSH_KEY_PATH
    SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa}"
    
    if [[ ! -f "$SSH_KEY_PATH" ]]; then
        log "ERROR" "SSH key file not found: $SSH_KEY_PATH"
        exit $EXIT_ERROR_INPUT
    fi
    
    # Application port
    while true; do
        read -p "Enter application port (internal container port): " APP_PORT
        if validate_port "$APP_PORT"; then
            break
        else
            log "ERROR" "Invalid port number. Must be between 1-65535"
        fi
    done
    
    # Set project name from repo URL
    PROJECT_NAME=$(basename "$REPO_URL" .git)
    CONTAINER_NAME="deploy_${PROJECT_NAME,,}"
    NGINX_CONFIG_NAME="${PROJECT_NAME,,}"
    
    log "INFO" "Parameters collected successfully"
    log "DEBUG" "Repository: $REPO_URL"
    log "DEBUG" "Branch: $BRANCH"
    log "DEBUG" "SSH User: $SSH_USER"
    log "DEBUG" "Server IP: $SERVER_IP"
    log "DEBUG" "SSH Key: $SSH_KEY_PATH"
    log "DEBUG" "App Port: $APP_PORT"
    log "DEBUG" "Project Name: $PROJECT_NAME"
}

# Function to clone repository
clone_repository() {
    log "INFO" "Cloning repository..."
    
    local repo_dir="$PROJECT_NAME"
    
    # Create authenticated URL
    local auth_url
    if [[ "$REPO_URL" =~ ^https://github.com/ ]]; then
        auth_url="${REPO_URL/https:\/\/github.com\//https://${PAT}@github.com/}"
    else
        log "WARN" "Non-GitHub repository detected, using standard authentication"
        auth_url="$REPO_URL"
    fi
    
    if [[ -d "$repo_dir" ]]; then
        log "INFO" "Repository directory exists, pulling latest changes..."
        cd "$repo_dir"
        git fetch origin
        git checkout "$BRANCH"
        git pull origin "$BRANCH"
        cd ..
    else
        log "INFO" "Cloning repository..."
        git clone -b "$BRANCH" "$auth_url" "$repo_dir"
    fi
    
    log "INFO" "Repository cloned/updated successfully"
}

# Function to navigate and verify project
navigate_and_verify() {
    log "INFO" "Navigating to project directory and verifying Docker files..."
    
    cd "$PROJECT_NAME"
    
    if [[ -f "Dockerfile" ]]; then
        log "INFO" "Dockerfile found"
    elif [[ -f "docker-compose.yml" ]] || [[ -f "docker-compose.yaml" ]]; then
        log "INFO" "Docker Compose file found"
    else
        log "ERROR" "No Dockerfile or docker-compose.yml found in project"
        exit $EXIT_ERROR_GIT
    fi
    
    log "INFO" "Project verification completed"
}

# Function to test SSH connectivity
test_ssh_connection() {
    log "INFO" "Testing SSH connectivity..."
    
    # Test SSH connection
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log "INFO" "SSH connection test passed"
    else
        log "ERROR" "SSH connection failed"
        exit $EXIT_ERROR_SSH
    fi
    
    # Test ping connectivity
    if ping -c 3 "$SERVER_IP" > /dev/null 2>&1; then
        log "INFO" "Ping connectivity test passed"
    else
        log "WARN" "Ping test failed, but SSH works"
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local max_attempts="${2:-30}"  # Default 30 attempts = 1 minute
    local attempt=1
    
    log "INFO" "Waiting for $service_name to be ready..."
    
    while [[ $attempt -le $max_attempts ]]; do
        if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "sudo systemctl is-active $service_name" > /dev/null 2>&1; then
            log "INFO" "$service_name is now active"
            return 0
        fi
        
        log "DEBUG" "Attempt $attempt/$max_attempts: $service_name not ready yet, waiting..."
        sleep 2
        ((attempt++))
    done
    
    log "WARN" "$service_name did not become active within expected time"
    return 1
}

# Function to check remote conditions (non-critical)
check_remote_condition() {
    local command="$1"
    local description="$2"
    
    log "DEBUG" "Checking remote condition: $description"
    
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "$command" > /dev/null 2>&1; then
        log "DEBUG" "$description: condition met"
        return 0
    else
        log "DEBUG" "$description: condition not met"
        return 1
    fi
}

# Function to execute remote commands
execute_remote_command() {
    local command="$1"
    local description="$2"
    local exit_code="${3:-$EXIT_ERROR_REMOTE}"  # Optional custom exit code
    
    log "DEBUG" "Executing remote command: $description"
    
    if ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$SSH_USER@$SERVER_IP" "$command"; then
        log "INFO" "$description completed successfully"
        return 0
    else
        log "ERROR" "$description failed"
        # If this is a critical operation, exit with specific code
        if [[ "$description" =~ [Dd]ocker ]]; then
            exit $EXIT_ERROR_DOCKER
        elif [[ "$description" =~ [Nn]ginx ]]; then
            exit $EXIT_ERROR_NGINX
        elif [[ "$description" =~ [Tt]ransfer ]]; then
            exit $EXIT_ERROR_FILE_TRANSFER
        else
            exit $exit_code
        fi
    fi
}

# Function to prepare remote environment
prepare_remote_environment() {
    log "INFO" "Preparing remote environment..."
    
    # Update system packages
    execute_remote_command "sudo apt update && sudo apt upgrade -y" "System package update"
    
    # Install Docker
    execute_remote_command '
        if ! command -v docker &> /dev/null; then
            echo "Installing Docker..."
            curl -fsSL https://get.docker.com -o get-docker.sh
            sudo sh get-docker.sh
            sudo usermod -aG docker $USER
            sudo systemctl enable docker
            
            # Try to start Docker, but dont fail if deferred
            sudo systemctl start docker || echo "Docker start may be deferred - this is normal"
            echo "Docker installation completed"
        else
            echo "Docker already installed"
            # Ensure Docker is running
            sudo systemctl start docker || true
        fi
    ' "Docker installation"
    
    # Wait for Docker to be ready
    wait_for_service "docker"
    
    # Install Docker Compose
    execute_remote_command '
        if ! command -v docker-compose &> /dev/null; then
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            echo "Docker Compose installed successfully"
        else
            echo "Docker Compose already installed"
        fi
    ' "Docker Compose installation"
    
    # Install Nginx
    execute_remote_command '
        if ! command -v nginx &> /dev/null; then
            echo "Installing Nginx..."
            sudo apt install -y nginx
            sudo systemctl enable nginx
            
            # Try to start Nginx, but dont fail if deferred
            sudo systemctl start nginx || echo "Nginx start may be deferred - this is normal"
            echo "Nginx installation completed"
        else
            echo "Nginx already installed"
            # Ensure Nginx is running
            sudo systemctl start nginx || true
        fi
    ' "Nginx installation"
    
    # Wait for Nginx to be ready
    wait_for_service "nginx"
    
    # Verify installations
    execute_remote_command "docker --version && docker-compose --version && nginx -v" "Installation verification"
    
    log "INFO" "Remote environment preparation completed"
}

# Function to transfer files to remote server
transfer_files() {
    log "INFO" "Transferring project files to remote server..."
    
    # Create remote directory
    execute_remote_command "mkdir -p /home/$SSH_USER/deployments/$PROJECT_NAME" "Remote directory creation"
    
    # Transfer files using rsync
    if command -v rsync &> /dev/null; then
        rsync -avz -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" ./ "$SSH_USER@$SERVER_IP:/home/$SSH_USER/deployments/$PROJECT_NAME/"
        log "INFO" "Files transferred using rsync"
    else
        # Fallback to scp
        scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no -r ./* "$SSH_USER@$SERVER_IP:/home/$SSH_USER/deployments/$PROJECT_NAME/"
        log "INFO" "Files transferred using scp"
    fi
    
    log "INFO" "File transfer completed"
}

# Function to deploy Docker application
deploy_docker_application() {
    log "INFO" "Deploying Docker application..."
    
    # Stop and remove existing containers
    execute_remote_command "
        cd /home/$SSH_USER/deployments/$PROJECT_NAME
        if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
            docker stop $CONTAINER_NAME || true
            docker rm $CONTAINER_NAME || true
            echo 'Stopped and removed existing container'
        fi
    " "Container cleanup"
    
    # Build and run container
    if check_remote_condition "cd /home/$SSH_USER/deployments/$PROJECT_NAME && [[ -f docker-compose.yml || -f docker-compose.yaml ]]" "Check for Docker Compose"; then
        # Use Docker Compose
        execute_remote_command "
            cd /home/$SSH_USER/deployments/$PROJECT_NAME
            docker-compose down || true
            docker-compose build
            docker-compose up -d
        " "Docker Compose deployment"
    else
        # Use Dockerfile
        execute_remote_command "
            cd /home/$SSH_USER/deployments/$PROJECT_NAME
            docker build -t $CONTAINER_NAME .
            docker run -d --name $CONTAINER_NAME -p $APP_PORT:$APP_PORT $CONTAINER_NAME
        " "Docker build and run"
    fi
    
    # Wait for container to start
    sleep 10
    
    # Validate container health
    execute_remote_command "
        if docker ps | grep -q $CONTAINER_NAME; then
            echo 'Container is running'
            docker logs $CONTAINER_NAME --tail 20
        else
            echo 'Container failed to start'
            exit $EXIT_ERROR_DOCKER
        fi
    " "Container health check"
    
    log "INFO" "Docker application deployed successfully"
}

# Function to configure Nginx reverse proxy
configure_nginx() {
    log "INFO" "Configuring Nginx reverse proxy..."
    
    # Create Nginx configuration
    local nginx_config="/tmp/nginx_${NGINX_CONFIG_NAME}.conf"
    
    cat > "$nginx_config" << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeout settings
        proxy_connect_timeout       60s;
        proxy_send_timeout          60s;
        proxy_read_timeout          60s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Transfer Nginx config
    scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$nginx_config" "$SSH_USER@$SERVER_IP:/tmp/"
    
    # Apply Nginx configuration
    execute_remote_command "
        sudo cp /tmp/nginx_${NGINX_CONFIG_NAME}.conf /etc/nginx/sites-available/${NGINX_CONFIG_NAME}
        sudo ln -sf /etc/nginx/sites-available/${NGINX_CONFIG_NAME} /etc/nginx/sites-enabled/
        sudo rm -f /etc/nginx/sites-enabled/default
        sudo nginx -t
        sudo systemctl reload nginx
    " "Nginx configuration"
    
    # Clean up local temp file
    rm -f "$nginx_config"
    
    log "INFO" "Nginx reverse proxy configured successfully"
}

# Function to validate deployment
validate_deployment() {
    log "INFO" "Validating deployment..."
    
    # Check Docker service
    execute_remote_command "sudo systemctl is-active docker" "Docker service status"
    
    # Check container status
    execute_remote_command "docker ps | grep $CONTAINER_NAME" "Container status"
    
    # Check Nginx status
    execute_remote_command "sudo systemctl is-active nginx" "Nginx service status"
    
    # Test application endpoint locally on server
    execute_remote_command "curl -f http://localhost:$APP_PORT || curl -f http://localhost:$APP_PORT/health || curl -f http://localhost:$APP_PORT/" "Local application test"
    
    # Test Nginx proxy
    execute_remote_command "curl -f http://localhost/health" "Nginx proxy test"
    
    # Test from external (this machine)
    sleep 5
    if curl -f "http://$SERVER_IP/" > /dev/null 2>&1; then
        log "INFO" "External connectivity test passed"
    else
        log "WARN" "External connectivity test failed - check firewall settings"
    fi
    
    log "INFO" "Deployment validation completed"
}

# Function to handle cleanup mode
handle_cleanup() {
    log "INFO" "Cleanup mode activated - removing deployed resources..."
    
    execute_remote_command "
        # Stop and remove containers
        if docker ps -q -f name=$CONTAINER_NAME | grep -q .; then
            docker stop $CONTAINER_NAME
            docker rm $CONTAINER_NAME
        fi
        
        # Remove Docker images
        if docker images -q $CONTAINER_NAME | grep -q .; then
            docker rmi $CONTAINER_NAME
        fi
        
        # Remove Nginx config
        sudo rm -f /etc/nginx/sites-available/${NGINX_CONFIG_NAME}
        sudo rm -f /etc/nginx/sites-enabled/${NGINX_CONFIG_NAME}
        sudo systemctl reload nginx
        
        # Remove deployment directory
        rm -rf /home/$SSH_USER/deployments/$PROJECT_NAME
        
        echo 'Cleanup completed'
    " "Resource cleanup"
    
    log "INFO" "Cleanup completed successfully"
}

# Function to display usage information
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

DevOps Stage 1 - Automated Deployment Script

This script automates the deployment of Dockerized applications to remote servers.

OPTIONS:
    --cleanup       Remove all deployed resources and exit
    --help, -h      Show this help message and exit

FEATURES:
    - Collects and validates deployment parameters
    - Clones Git repositories with PAT authentication
    - Sets up remote server environment (Docker, Nginx)
    - Deploys Dockerized applications
    - Configures Nginx reverse proxy
    - Validates deployment success
    - Comprehensive logging and error handling
    - Idempotent operations (safe to re-run)

REQUIREMENTS:
    - Bash 4.0+
    - Git
    - SSH client
    - Internet connectivity
    - Target server with sudo access

EXAMPLES:
    $0                    # Interactive deployment
    $0 --cleanup         # Remove deployed resources

LOG FILES:
    Logs are saved to: deploy_YYYYMMDD_HHMMSS.log

EXIT CODES:
    0 - SUCCESS: Script completed successfully
    1 - INPUT_ERROR: Invalid input parameters
    2 - GIT_ERROR: Git repository or Docker file issues
    3 - SSH_ERROR: SSH connectivity problems
    4 - DOCKER_ERROR: Docker deployment failures
    5 - NGINX_ERROR: Nginx configuration issues
    6 - VALIDATION_ERROR: Deployment validation failures
    7 - REMOTE_ERROR: Remote server operation failures
    8 - FILE_TRANSFER_ERROR: File transfer issues

EOF
}

# Main function
main() {
    log "INFO" "Starting DevOps Stage 1 Deployment Script"
    log "INFO" "Log file: $LOG_FILE"
    
    # Parse command line arguments
    case "${1:-}" in
        --cleanup)
            CLEANUP_MODE=true
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        "")
            # No arguments - normal operation
            ;;
        *)
            log "ERROR" "Unknown option: $1"
            show_usage
            exit $EXIT_ERROR_INPUT
            ;;
    esac
    
    # If cleanup mode, collect minimal info and cleanup
    if [[ "$CLEANUP_MODE" == true ]]; then
        log "INFO" "Running in cleanup mode"
        collect_user_input
        test_ssh_connection
        handle_cleanup
        exit 0
    fi
    
    # Normal deployment flow
    collect_user_input
    clone_repository
    navigate_and_verify
    test_ssh_connection
    prepare_remote_environment
    transfer_files
    deploy_docker_application
    configure_nginx
    validate_deployment
    
    log "INFO" "Deployment completed successfully!"
    log "INFO" "Application should be accessible at: http://$SERVER_IP"
    log "INFO" "Log file saved to: $LOG_FILE"
    
    echo
    echo -e "${GREEN}🚀 Deployment Successful!${NC}"
    echo -e "${BLUE}Application URL: http://$SERVER_IP${NC}"
    echo -e "${BLUE}Log file: $LOG_FILE${NC}"
}

# Run main function with all arguments
main "$@"