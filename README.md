# DevOps Stage 1 - Automated Deployment Script

## 🚀 Overview

This is a production-grade Bash script that automates the complete setup, deployment, and configuration of Dockerized applications on remote Linux servers. The script handles everything from Git repository cloning to Nginx reverse proxy configuration with comprehensive error handling and logging.

## ✨ Features

- **Interactive Parameter Collection**: Prompts and validates all required deployment parameters
- **Git Repository Management**: Clones repositories using Personal Access Tokens (PAT) with branch switching
- **Remote Server Preparation**: Automatically installs Docker, Docker Compose, and Nginx
- **Dockerized Application Deployment**: Supports both Dockerfile and Docker Compose deployments  
- **Nginx Reverse Proxy**: Automatically configures Nginx as a reverse proxy with health checks
- **Comprehensive Validation**: Tests all services and connectivity before completion
- **Robust Error Handling**: Detailed logging with timestamped log files and meaningful exit codes
- **Idempotent Operations**: Safe to re-run without breaking existing deployments
- **Cleanup Functionality**: Optional cleanup mode to remove all deployed resources

## 📋 Requirements

### Local Machine
- **Operating System**: Linux (Fedora, Ubuntu, CentOS, etc.)
- **Shell**: Bash 4.0 or higher
- **Git**: For repository cloning
- **SSH Client**: For remote server access
- **Internet Connectivity**: For downloading packages and Docker images

### Remote Server
- **Operating System**: Ubuntu/Debian-based Linux distribution
- **SSH Access**: User account with sudo privileges
- **SSH Key Authentication**: Password-less SSH key setup
- **Internet Connectivity**: For downloading packages and Docker images
- **Ports**: Application port and port 80 (HTTP) should be accessible

### Prerequisites Setup

1. **SSH Key Setup**:
   ```bash
   # Generate SSH key if you don't have one
   ssh-keygen -t rsa -b 4096 -C "your-email@example.com"
   
   # Copy public key to remote server
   ssh-copy-id user@your-server-ip
   ```

2. **GitHub Personal Access Token**:
   - Go to GitHub Settings → Developer settings → Personal access tokens
   - Generate a new token with repository access permissions
   - Keep the token secure and ready for script input

## 🎯 Usage

### Basic Deployment

1. **Make the script executable**:
   ```bash
   chmod +x deploy.sh
   ```

2. **Run the deployment**:
   ```bash
   ./deploy.sh
   ```

3. **Follow the interactive prompts**:
   - Git Repository URL (e.g., `https://github.com/username/my-app.git`)
   - Personal Access Token (hidden input)
   - Branch name (defaults to `main`)
   - SSH username for remote server
   - Remote server IP address
   - SSH key path (defaults to `~/.ssh/id_rsa`)
   - Application port (internal container port)

### Command Line Options

```bash
./deploy.sh                # Interactive deployment
./deploy.sh --cleanup      # Remove all deployed resources
./deploy.sh --help         # Show help information
```

### Example Session

```bash
$ ./deploy.sh
[INFO] Starting DevOps Stage 1 Deployment Script
[INFO] Log file: ./deploy_20241020_173045.log
[INFO] Collecting deployment parameters...
Enter Git Repository URL: https://github.com/username/my-webapp.git
Enter Personal Access Token (PAT): [hidden]
Enter branch name (default: main): main
Enter SSH username: ubuntu
Enter server IP address: 192.168.1.100
Enter SSH key path (default: ~/.ssh/id_rsa): 
Enter application port (internal container port): 3000
[INFO] Parameters collected successfully
...
[INFO] Deployment completed successfully!
[INFO] Application should be accessible at: http://192.168.1.100
🚀 Deployment Successful!
Application URL: http://192.168.1.100
Log file: ./deploy_20241020_173045.log
```

## 🏗️ Script Architecture

### Main Functions

1. **`collect_user_input()`**: Interactive parameter collection with validation
2. **`clone_repository()`**: Git repository cloning with PAT authentication
3. **`navigate_and_verify()`**: Project directory navigation and Docker file verification
4. **`test_ssh_connection()`**: SSH connectivity testing
5. **`prepare_remote_environment()`**: Remote server environment setup
6. **`transfer_files()`**: Project file transfer to remote server
7. **`deploy_docker_application()`**: Docker container building and deployment
8. **`configure_nginx()`**: Nginx reverse proxy configuration
9. **`validate_deployment()`**: Comprehensive deployment validation
10. **`handle_cleanup()`**: Resource cleanup functionality

### Validation Functions

- **`validate_url()`**: Validates Git repository URLs
- **`validate_ip()`**: Validates IPv4 addresses with proper octet checking
- **`validate_port()`**: Validates port numbers (1-65535 range)

### Utility Functions

- **`log()`**: Colored logging with multiple levels (INFO, WARN, ERROR, DEBUG)
- **`handle_error()`**: Centralized error handling with line number reporting
- **`execute_remote_command()`**: Remote SSH command execution with error handling

## 📁 Project Structure

After deployment, the remote server will have the following structure:

```
/home/[username]/
└── deployments/
    └── [project-name]/
        ├── [project files]
        ├── Dockerfile or docker-compose.yml
        └── [other application files]

/etc/nginx/
├── sites-available/
│   └── [project-name]
└── sites-enabled/
    └── [project-name] -> ../sites-available/[project-name]
```

## 🛠️ Deployment Process

### Step-by-Step Process

1. **Parameter Collection**: Validates and collects all deployment parameters
2. **Repository Cloning**: Clones the Git repository using PAT authentication
3. **Docker File Verification**: Ensures Dockerfile or docker-compose.yml exists
4. **SSH Connectivity Test**: Verifies SSH access to the remote server
5. **Remote Environment Setup**: 
   - Updates system packages
   - Installs Docker, Docker Compose, and Nginx
   - Configures services and user permissions
6. **File Transfer**: Transfers project files to remote server using rsync or scp
7. **Docker Deployment**:
   - Stops existing containers (idempotent)
   - Builds new Docker image or uses Docker Compose
   - Runs containers with proper port mapping
8. **Nginx Configuration**:
   - Creates dynamic Nginx configuration
   - Sets up reverse proxy to application port
   - Includes health check endpoint
9. **Validation**:
   - Verifies Docker service status
   - Checks container health
   - Tests Nginx proxy functionality
   - Validates external connectivity

## 📊 Logging

### Log Levels

- **INFO**: General information about script progress
- **WARN**: Warnings that don't stop execution
- **ERROR**: Errors that may cause script failure
- **DEBUG**: Detailed information for troubleshooting

### Log File Format

Log files are named with timestamps: `deploy_YYYYMMDD_HHMMSS.log`

Example log entries:
```
[2024-10-20 17:30:45] [INFO] Starting DevOps Stage 1 Deployment Script
[2024-10-20 17:30:46] [DEBUG] Repository: https://github.com/username/webapp.git
[2024-10-20 17:30:47] [INFO] SSH connection test passed
[2024-10-20 17:31:15] [ERROR] Container failed to start
```

## 🔧 Configuration

### Nginx Configuration Template

The script automatically generates Nginx configuration:

```nginx
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://localhost:[APP_PORT];
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeout settings
        proxy_connect_timeout       60s;
        proxy_send_timeout          60s;
        proxy_read_timeout          60s;
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
```

### Docker Configuration Support

The script supports both deployment methods:

1. **Dockerfile**: Builds image and runs container with port mapping
2. **Docker Compose**: Uses docker-compose for full stack deployments

## 🚨 Troubleshooting

### Common Issues and Solutions

#### 1. SSH Connection Failed
**Error**: `SSH connection failed`
**Solutions**:
- Verify SSH key exists and has correct permissions (600)
- Ensure public key is added to remote server's authorized_keys
- Check if SSH service is running on remote server
- Verify server IP address and network connectivity

#### 2. Git Clone Authentication Failed  
**Error**: `fatal: Authentication failed`
**Solutions**:
- Verify Personal Access Token has repository access permissions
- Check if token has expired
- Ensure repository URL is correct and accessible

#### 3. Docker Installation Failed
**Error**: `Docker installation failed`
**Solutions**:
- Check internet connectivity on remote server
- Verify sudo privileges for remote user
- Check if ports 443/80 are accessible for downloading packages

#### 4. Container Failed to Start
**Error**: `Container failed to start`
**Solutions**:
- Check Dockerfile syntax and base image availability
- Verify application port is correctly exposed
- Check container logs: `docker logs [container-name]`
- Ensure no port conflicts with existing services

#### 5. Nginx Configuration Failed
**Error**: `Nginx configuration failed`
**Solutions**:
- Check nginx syntax: `sudo nginx -t`
- Verify application is running on specified port
- Check nginx error logs: `sudo tail -f /var/log/nginx/error.log`

#### 6. External Connectivity Failed
**Error**: `External connectivity test failed`
**Solutions**:
- Check firewall settings on remote server
- Ensure port 80 is open and accessible
- Verify security group rules (if using cloud services)
- Check if application is binding to correct interface

### Debug Mode

For additional troubleshooting, check the generated log file for DEBUG messages that provide detailed information about each operation.

### Manual Verification Commands

If deployment seems to fail, you can manually verify on the remote server:

```bash
# Check Docker status
sudo systemctl status docker

# Check running containers  
docker ps -a

# Check container logs
docker logs [container-name]

# Check Nginx status
sudo systemctl status nginx

# Test Nginx configuration
sudo nginx -t

# Check if application port is listening
netstat -tlnp | grep [port]

# Test local connectivity
curl http://localhost:[port]
curl http://localhost/health
```

## 🔒 Security Considerations

### SSH Security
- Use SSH key authentication instead of passwords
- Ensure SSH keys have appropriate permissions (600 for private key)
- Consider using SSH agent for key management

### Token Security
- Store Personal Access Tokens securely
- Use tokens with minimal required permissions
- Rotate tokens regularly
- Never commit tokens to version control

### Server Security
- Keep remote server packages updated
- Configure proper firewall rules
- Use non-root users with sudo access
- Monitor system logs for unusual activities

