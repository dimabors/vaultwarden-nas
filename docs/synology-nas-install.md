# Installing Vaultwarden on Synology NAS

This guide walks you through installing Vaultwarden on your Synology NAS using Docker.

## Prerequisites

Before you begin, ensure you have:

1. **Synology NAS** with DSM 6.0 or higher
2. **Docker** or **Container Manager** package installed from Package Center
3. **SSH access** enabled (Control Panel > Terminal & SNMP > Enable SSH service)
4. **Admin/root access** to your NAS

## Quick Installation

### Option 1: Using the Installation Script (Recommended)

1. Connect to your NAS via SSH:
   ```bash
   ssh admin@your-nas-ip
   ```

2. Download and run the installation script:
   ```bash
   sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/dani-garcia/vaultwarden/main/scripts/install-synology.sh)"
   ```

   Or with custom options:
   ```bash
   sudo ./scripts/install-synology.sh \
       --domain https://vault.yourdomain.com \
       --port 8080 \
       --data-dir /volume1/docker/vaultwarden
   ```

### Option 2: Manual Installation via Docker

1. SSH into your NAS:
   ```bash
   ssh admin@your-nas-ip
   sudo -i
   ```

2. Create a directory for Vaultwarden data:
   ```bash
   mkdir -p /volume1/docker/vaultwarden/data
   cd /volume1/docker/vaultwarden
   ```

3. Create a `.env` file with your configuration:
   ```bash
   cat > .env << 'EOF'
   DOMAIN=https://vault.yourdomain.com
   ADMIN_TOKEN=your-secure-admin-token
   SIGNUPS_ALLOWED=true
   WEB_VAULT_ENABLED=true
   EOF
   ```

4. Create a `docker-compose.yml` file:
   ```yaml
   services:
     vaultwarden:
       image: vaultwarden/server:latest
       container_name: vaultwarden
       restart: unless-stopped
       env_file:
         - .env
       volumes:
         - ./data:/data
       ports:
         - "8000:80"
   ```

5. Start the container:
   ```bash
   docker-compose up -d
   ```

### Option 3: Using Synology Container Manager GUI

1. Open **Container Manager** (or Docker) from your DSM applications
2. Go to **Registry** and search for `vaultwarden/server`
3. Download the **latest** tag
4. Go to **Image** and select the downloaded image
5. Click **Launch** and configure:
   - **Container Name**: vaultwarden
   - **Port Settings**: Local Port 8000 → Container Port 80
   - **Volume**: Create a folder (e.g., `/docker/vaultwarden`) and mount it to `/data`
   - **Environment Variables**: Add your configuration (DOMAIN, ADMIN_TOKEN, etc.)
6. Click **Apply** to start the container

## Configuration

### Essential Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DOMAIN` | Your Vaultwarden URL | `https://vault.yourdomain.com` |
| `ADMIN_TOKEN` | Token for admin panel access | `your-secure-token` |
| `SIGNUPS_ALLOWED` | Allow new user registrations | `true` or `false` |
| `WEB_VAULT_ENABLED` | Enable web vault interface | `true` |

### Generating a Secure Admin Token

```bash
openssl rand -base64 48
```

### Full Configuration Reference

For all available configuration options, see:
- [.env.template](../.env.template) in this repository
- [Vaultwarden Wiki - Configuration](https://github.com/dani-garcia/vaultwarden/wiki)

## Setting Up HTTPS (Required)

> **Important**: The web vault requires HTTPS to function properly. You must set up a reverse proxy.

### Option A: Using Synology Reverse Proxy

1. Go to **Control Panel** > **Login Portal** > **Advanced** > **Reverse Proxy**
2. Click **Create** and configure:
   - **Description**: Vaultwarden
   - **Source**: 
     - Protocol: HTTPS
     - Hostname: vault.yourdomain.com
     - Port: 443
   - **Destination**:
     - Protocol: HTTP
     - Hostname: localhost
     - Port: 8000
3. Under **Custom Header**, add:
   - Create > WebSocket
4. Apply and ensure your SSL certificate is configured

### Option B: Using a Separate Reverse Proxy Container

You can also use nginx, Caddy, or Traefik as a reverse proxy. See the [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki/Proxy-examples) for configuration examples.

## Post-Installation

### Access Your Instance

- **Web Vault**: `https://vault.yourdomain.com`
- **Admin Panel**: `https://vault.yourdomain.com/admin`

### Security Recommendations

1. **Disable signups** after creating your account:
   ```bash
   # Edit .env file
   SIGNUPS_ALLOWED=false
   ```
   Then restart: `docker restart vaultwarden`

2. **Set up regular backups** of your data directory

3. **Configure email (SMTP)** for password reset functionality

4. **Keep Vaultwarden updated**:
   ```bash
   docker pull vaultwarden/server:latest
   docker-compose down
   docker-compose up -d
   ```

## Backup and Restore

### Backup

```bash
# Stop the container
docker stop vaultwarden

# Backup the data directory
tar -czvf vaultwarden-backup-$(date +%Y%m%d).tar.gz /volume1/docker/vaultwarden/data

# Start the container
docker start vaultwarden
```

### Restore

```bash
# Stop the container
docker stop vaultwarden

# Restore the backup
tar -xzvf vaultwarden-backup-YYYYMMDD.tar.gz -C /

# Start the container
docker start vaultwarden
```

## Troubleshooting

### View Container Logs

```bash
docker logs -f vaultwarden
```

### Container Won't Start

1. Check if the port is already in use:
   ```bash
   netstat -tlnp | grep 8000
   ```

2. Verify directory permissions:
   ```bash
   ls -la /volume1/docker/vaultwarden
   ```

3. Check Docker status:
   ```bash
   docker ps -a
   ```

### WebSocket Connection Issues

Ensure your reverse proxy is configured to forward WebSocket connections. This is required for real-time sync between clients.

### Admin Panel Not Accessible

Verify the `ADMIN_TOKEN` is set correctly in your `.env` file and restart the container.

## Updating Vaultwarden

```bash
cd /volume1/docker/vaultwarden

# Pull the latest image
docker pull vaultwarden/server:latest

# Restart with new image
docker-compose down
docker-compose up -d

# Or if using docker run:
docker stop vaultwarden
docker rm vaultwarden
# Re-run your docker run command
```

## Uninstallation

```bash
# Stop and remove the container
docker stop vaultwarden
docker rm vaultwarden

# Optionally remove the image
docker rmi vaultwarden/server:latest

# Optionally remove data (CAUTION: This deletes all your passwords!)
# rm -rf /volume1/docker/vaultwarden
```

## Support

- [Vaultwarden Wiki](https://github.com/dani-garcia/vaultwarden/wiki)
- [GitHub Discussions](https://github.com/dani-garcia/vaultwarden/discussions)
- [Matrix Chat](https://matrix.to/#/#vaultwarden:matrix.org)
