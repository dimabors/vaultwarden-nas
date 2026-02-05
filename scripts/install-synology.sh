#!/bin/bash
#
# Vaultwarden Installation Script for Synology NAS
#
# This script helps install Vaultwarden on Synology NAS using Docker.
# It creates the necessary directories, configuration files, and starts the container.
#
# Usage:
#   ./install-synology.sh [OPTIONS]
#
# Options:
#   --data-dir DIR     Data directory path (default: /volume1/docker/vaultwarden)
#   --domain DOMAIN    Your Vaultwarden domain (e.g., https://vw.example.com)
#   --port PORT        Host port to expose (default: 8000)
#   --admin-token TOK  Admin panel token (optional, generates one if not provided)
#   --help             Show this help message
#
# Requirements:
#   - Synology NAS with DSM 6.0 or higher
#   - Docker package installed via Package Center
#   - SSH access enabled (Control Panel > Terminal & SNMP)
#
# SPDX-License-Identifier: AGPL-3.0-only

set -euo pipefail

# Default configuration
DEFAULT_DATA_DIR="/volume1/docker/vaultwarden"
DEFAULT_PORT="8000"
DEFAULT_IMAGE="vaultwarden/server:latest"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Show help message
show_help() {
    cat << EOF
Vaultwarden Installation Script for Synology NAS

Usage: $0 [OPTIONS]

Options:
    --data-dir DIR     Data directory path (default: $DEFAULT_DATA_DIR)
    --domain DOMAIN    Your Vaultwarden domain (e.g., https://vw.example.com)
    --port PORT        Host port to expose (default: $DEFAULT_PORT)
    --admin-token TOK  Admin panel token (optional, generates one if not provided)
    --help             Show this help message

Example:
    $0 --domain https://vault.mydomain.com --port 8080

Requirements:
    - Synology NAS with DSM 6.0 or higher
    - Docker package installed via Package Center
    - SSH access enabled (Control Panel > Terminal & SNMP)

For more information, visit:
    https://github.com/dani-garcia/vaultwarden/wiki
EOF
    exit 0
}

# Generate a secure random token
generate_token() {
    if command -v openssl &> /dev/null; then
        openssl rand -base64 48
    elif [ -f /dev/urandom ]; then
        head -c 48 /dev/urandom | base64
    else
        log_error "Cannot generate secure token. Please provide --admin-token"
        exit 1
    fi
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if Docker is installed and running
check_docker() {
    log_info "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed."
        log_info "Please install Docker from Synology Package Center:"
        log_info "  1. Open Package Center"
        log_info "  2. Search for 'Docker' or 'Container Manager'"
        log_info "  3. Click Install"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running."
        log_info "Please ensure Docker/Container Manager is running in Package Center."
        exit 1
    fi

    log_success "Docker is installed and running"
}

# Check Synology-specific requirements
check_synology() {
    log_info "Checking Synology NAS environment..."

    # Check if we're on Synology
    if [ -f /etc/synoinfo.conf ]; then
        DSM_VERSION=$(grep "^majorversion=" /etc/synoinfo.conf 2>/dev/null | cut -d'"' -f2 || echo "unknown")
        log_success "Detected Synology DSM version: $DSM_VERSION"
    else
        log_warning "Not running on Synology NAS. Script may still work on other systems."
    fi

    # Check for available volume
    if [ ! -d /volume1 ]; then
        log_warning "/volume1 not found. Please ensure a volume is available."
    fi
}

# Create data directory with proper permissions
create_data_directory() {
    local data_dir="$1"

    log_info "Creating data directory: $data_dir"

    if [ -d "$data_dir" ]; then
        log_warning "Data directory already exists: $data_dir"
        read -r -p "Do you want to continue and use the existing directory? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                log_info "Using existing directory"
                ;;
            *)
                log_error "Installation cancelled"
                exit 1
                ;;
        esac
    else
        mkdir -p "$data_dir"
        log_success "Created data directory: $data_dir"
    fi

    # Set permissions (UID 1000 is commonly used in containers)
    chmod 755 "$data_dir"
}

# Create environment configuration file
create_env_file() {
    local data_dir="$1"
    local domain="$2"
    local admin_token="$3"
    local env_file="$data_dir/.env"

    log_info "Creating environment configuration..."

    if [ -f "$env_file" ]; then
        log_warning "Environment file already exists: $env_file"
        read -r -p "Do you want to overwrite it? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                cp "$env_file" "${env_file}.backup.$(date +%Y%m%d_%H%M%S)"
                log_info "Backup created"
                ;;
            *)
                log_info "Keeping existing configuration"
                return
                ;;
        esac
    fi

    cat > "$env_file" << EOF
## Vaultwarden Configuration for Synology NAS
## Generated by install-synology.sh on $(date)

## Domain configuration
## Set this to your Vaultwarden URL (required for proper operation)
DOMAIN=${domain}

## Admin panel token
## Access the admin panel at ${domain}/admin
## Keep this token secure!
ADMIN_TOKEN=${admin_token}

## Database settings (SQLite is default and recommended for small deployments)
# DATABASE_URL=/data/db.sqlite3

## Enable Web Vault
WEB_VAULT_ENABLED=true

## Signups configuration
## Set to false to disable new user registrations after initial setup
SIGNUPS_ALLOWED=true

## Invitation settings
# INVITATIONS_ALLOWED=true

## Logging
LOG_FILE=/data/vaultwarden.log
LOG_LEVEL=info

## Uncomment and configure for SMTP email support
# SMTP_HOST=smtp.example.com
# SMTP_FROM=vaultwarden@example.com
# SMTP_PORT=587
# SMTP_SECURITY=starttls
# SMTP_USERNAME=username
# SMTP_PASSWORD=password
EOF

    chmod 600 "$env_file"
    log_success "Created environment file: $env_file"
}

# Create docker-compose.yml file
create_compose_file() {
    local data_dir="$1"
    local port="$2"
    local compose_file="$data_dir/docker-compose.yml"

    log_info "Creating Docker Compose configuration..."

    cat > "$compose_file" << EOF
# Vaultwarden Docker Compose for Synology NAS
# Generated by install-synology.sh on $(date)

services:
  vaultwarden:
    image: ${DEFAULT_IMAGE}
    container_name: vaultwarden
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data:/data
    ports:
      - "${port}:80"
    environment:
      - TZ=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/alive"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s
EOF

    chmod 644 "$compose_file"
    log_success "Created Docker Compose file: $compose_file"
}

# Pull the Docker image
pull_docker_image() {
    log_info "Pulling Vaultwarden Docker image..."

    if docker pull "$DEFAULT_IMAGE"; then
        log_success "Successfully pulled $DEFAULT_IMAGE"
    else
        log_error "Failed to pull Docker image"
        exit 1
    fi
}

# Start the container
start_container() {
    local data_dir="$1"
    local port="$2"

    log_info "Starting Vaultwarden container..."

    # Check if container already exists
    if docker ps -a --format '{{.Names}}' | grep -q "^vaultwarden$"; then
        log_warning "Container 'vaultwarden' already exists"
        read -r -p "Do you want to remove it and create a new one? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                docker stop vaultwarden 2>/dev/null || true
                docker rm vaultwarden 2>/dev/null || true
                log_info "Removed existing container"
                ;;
            *)
                log_info "Keeping existing container"
                return
                ;;
        esac
    fi

    # Create data subdirectory for persistence
    mkdir -p "$data_dir/data"

    # Try docker compose first (newer), then docker-compose (older)
    cd "$data_dir"
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    elif docker compose version &> /dev/null 2>&1; then
        docker compose up -d
    else
        # Fallback to docker run if compose is not available
        log_warning "Docker Compose not found, using docker run..."
        docker run -d \
            --name vaultwarden \
            --restart unless-stopped \
            --env-file "$data_dir/.env" \
            -v "$data_dir/data:/data" \
            -p "${port}:80" \
            "$DEFAULT_IMAGE"
    fi

    log_success "Vaultwarden container started"
}

# Verify the installation
verify_installation() {
    local port="$1"
    local max_attempts=30
    local attempt=1

    log_info "Verifying installation..."

    while [ $attempt -le $max_attempts ]; do
        if curl -sf "http://localhost:${port}/alive" > /dev/null 2>&1; then
            log_success "Vaultwarden is running and healthy!"
            return 0
        fi
        log_info "Waiting for Vaultwarden to start (attempt $attempt/$max_attempts)..."
        sleep 2
        attempt=$((attempt + 1))
    done

    log_warning "Could not verify Vaultwarden is running."
    log_info "Check container logs with: docker logs vaultwarden"
    return 1
}

# Print post-installation instructions
print_instructions() {
    local domain="$1"
    local port="$2"
    local data_dir="$3"
    local admin_token="$4"

    echo ""
    echo "=========================================="
    echo -e "${GREEN}Vaultwarden Installation Complete!${NC}"
    echo "=========================================="
    echo ""
    echo "Access your Vaultwarden instance:"
    echo "  Local:  http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'your-nas-ip'):${port}"
    if [ -n "$domain" ] && [ "$domain" != "https://vw.example.com" ]; then
        echo "  Domain: ${domain}"
    fi
    echo ""
    echo "Admin Panel:"
    echo "  URL:   http://localhost:${port}/admin"
    echo "  Token: ${admin_token}"
    echo ""
    echo "Data directory: ${data_dir}"
    echo ""
    echo "Important next steps:"
    echo "  1. Set up a reverse proxy (HTTPS is required for web vault)"
    echo "  2. Configure your domain DNS to point to your NAS"
    echo "  3. Set SIGNUPS_ALLOWED=false after creating your account"
    echo "  4. Configure email (SMTP) for password reset functionality"
    echo ""
    echo "Useful commands:"
    echo "  View logs:     docker logs -f vaultwarden"
    echo "  Stop:          docker stop vaultwarden"
    echo "  Start:         docker start vaultwarden"
    echo "  Restart:       docker restart vaultwarden"
    echo "  Update:        docker pull ${DEFAULT_IMAGE} && docker restart vaultwarden"
    echo ""
    echo "For more information, visit:"
    echo "  https://github.com/dani-garcia/vaultwarden/wiki"
    echo ""
}

# Main installation function
main() {
    local data_dir="$DEFAULT_DATA_DIR"
    local domain="https://vw.example.com"
    local port="$DEFAULT_PORT"
    local admin_token=""

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --data-dir)
                data_dir="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --port)
                port="$2"
                shift 2
                ;;
            --admin-token)
                admin_token="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                ;;
        esac
    done

    # Generate admin token if not provided
    if [ -z "$admin_token" ]; then
        admin_token=$(generate_token)
    fi

    echo ""
    echo "=========================================="
    echo "Vaultwarden Installer for Synology NAS"
    echo "=========================================="
    echo ""

    # Run installation steps
    check_root
    check_synology
    check_docker
    create_data_directory "$data_dir"
    create_env_file "$data_dir" "$domain" "$admin_token"
    create_compose_file "$data_dir" "$port"
    pull_docker_image
    start_container "$data_dir" "$port"

    # Wait a moment for container to start
    sleep 3

    verify_installation "$port"
    print_instructions "$domain" "$port" "$data_dir" "$admin_token"
}

# Run main function
main "$@"
