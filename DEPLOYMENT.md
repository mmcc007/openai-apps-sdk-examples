# Pizzaz MCP Server - Production Deployment Guide

This guide covers deploying the Pizzaz MCP server to production. The server runs directly on a VM with systemd services, nginx reverse proxy, and Let's Encrypt SSL.

## Prerequisites

- VM with Ubuntu (tested on Ubuntu 20.04+)
- Domain name with DNS configured
- SSH access to the VM
- Node.js 18+ and pnpm installed on the VM

## Architecture

```
Internet → HTTPS:443 → nginx → localhost:8001 (MCP Server)
                            → localhost:4444 (Assets Server)
```

**Key Components:**
- **MCP Server** (port 8001): Node.js server implementing MCP protocol over SSE
- **Assets Server** (port 4444): Static file server for widget bundles
- **nginx**: Reverse proxy with SSL termination and SSE optimization
- **systemd**: Service management with auto-restart

## Deployment Process

### 1. Initial Setup (One-time)

The initial VM setup was done using:
- DNS: `pizzaz.lazzloe.com` A record → VM IP
- SSL certificate from Let's Encrypt
- nginx configuration with SSE support
- Firewall rules (ports 22, 80, 443)

See `setup/README.md` and `DEV-SETUP.md` for historical context.

### 2. Deploying Updates

Use the deployment script:

```bash
./scripts/deploy-pizzaz.sh
```

**What it does:**
1. Builds widget assets locally with production `BASE_URL`
2. Copies code and assets to VM
3. Installs dependencies on VM
4. Updates systemd service files
5. Updates nginx configuration
6. Restarts services
7. Verifies health

**Deployment time:** ~2-3 minutes (depends on build and network speed)

### 3. Manual Deployment Steps

If the script fails or you need to deploy manually:

```bash
# 1. Build assets locally
BASE_URL=https://pizzaz.lazzloe.com pnpm run build

# 2. Copy files to VM
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  ./ ubuntu@46.224.27.7:/opt/pizzaz-mcp/

# 3. Install dependencies on VM
ssh ubuntu@46.224.27.7 "cd /opt/pizzaz-mcp && /home/ubuntu/.local/share/pnpm/pnpm install"

# 4. Update systemd services
scp setup/pizzaz-mcp.service ubuntu@46.224.27.7:/tmp/
scp setup/pizzaz-assets.service ubuntu@46.224.27.7:/tmp/
ssh ubuntu@46.224.27.7 "
  sudo cp /tmp/pizzaz-mcp.service /etc/systemd/system/ &&
  sudo cp /tmp/pizzaz-assets.service /etc/systemd/system/ &&
  sudo systemctl daemon-reload &&
  sudo systemctl restart pizzaz-mcp.service pizzaz-assets.service
"

# 5. Update nginx (if needed)
scp setup/nginx-pizzaz-production.conf ubuntu@46.224.27.7:/tmp/
ssh ubuntu@46.224.27.7 "
  sudo cp /tmp/nginx-pizzaz-production.conf /etc/nginx/sites-available/pizzaz.lazzloe.com &&
  sudo nginx -t &&
  sudo systemctl reload nginx
"

# 6. Verify
MCP_URL=https://pizzaz.lazzloe.com/mcp pnpm exec tsx tests/test-mcp.ts
```

## Service Management

### Check Service Status

```bash
ssh ubuntu@46.224.27.7 'sudo systemctl status pizzaz-mcp.service'
ssh ubuntu@46.224.27.7 'sudo systemctl status pizzaz-assets.service'
```

### View Logs

```bash
# MCP server logs
ssh ubuntu@46.224.27.7 'sudo journalctl -u pizzaz-mcp.service -f'

# Assets server logs
ssh ubuntu@46.224.27.7 'sudo journalctl -u pizzaz-assets.service -f'

# Recent errors
ssh ubuntu@46.224.27.7 'sudo journalctl -u pizzaz-mcp.service -n 50 --no-pager'
```

### Restart Services

```bash
ssh ubuntu@46.224.27.7 'sudo systemctl restart pizzaz-mcp.service pizzaz-assets.service'
```

### Stop Services

```bash
ssh ubuntu@46.224.27.7 'sudo systemctl stop pizzaz-mcp.service pizzaz-assets.service'
```

## Configuration Files

### Systemd Services

**`setup/pizzaz-mcp.service`**
- Runs the MCP server on port 8001
- Auto-restarts on failure
- Logs to journalctl

**`setup/pizzaz-assets.service`**
- Serves static assets on port 4444
- Auto-restarts on failure

### nginx Configuration

**`setup/nginx-pizzaz-production.conf`**
- Proxies `/mcp` → `localhost:8001`
- Proxies `/` → `localhost:4444`
- Critical SSE settings:
  ```nginx
  proxy_buffering off;
  proxy_cache off;
  proxy_set_header Connection '';
  chunked_transfer_encoding off;
  ```

## Testing

### Run Protocol Tests

```bash
MCP_URL=https://pizzaz.lazzloe.com/mcp pnpm exec tsx tests/test-mcp.ts
```

Tests verify:
- MCP protocol compliance
- All 5 tools present
- Widget resources accessible
- Correct MIME types
- Tool invocation works

### Manual Endpoint Test

```bash
# Should return SSE stream (will stay open)
curl https://pizzaz.lazzloe.com/mcp

# Check assets
curl https://pizzaz.lazzloe.com/pizzaz-2d2b.html
```

## Troubleshooting

### Service Won't Start

1. Check logs:
   ```bash
   ssh ubuntu@46.224.27.7 'sudo journalctl -u pizzaz-mcp.service -n 50'
   ```

2. Common issues:
   - **Port already in use**: Check `sudo lsof -i:8001`
   - **Missing dependencies**: Run `pnpm install` in `/opt/pizzaz-mcp/pizzaz_server_node`
   - **Missing assets**: Run `BASE_URL=https://pizzaz.lazzloe.com pnpm run build` locally

### nginx 502 Bad Gateway

- Service not running: `sudo systemctl status pizzaz-mcp.service`
- Wrong port in config: Check nginx config has `proxy_pass http://127.0.0.1:8001`
- Firewall: Ensure ports are open

### SSE Connection Issues

- nginx buffering SSE: Check `proxy_buffering off` in nginx config
- Timeout too short: Increase `proxy_read_timeout` in nginx config
- Check server logs for connection errors

## Rollback

If deployment fails:

```bash
# 1. Check git history
git log --oneline

# 2. Revert to previous commit
git checkout <previous-commit>

# 3. Redeploy
./scripts/deploy-pizzaz.sh
```

## Port Configuration

**Production ports:**
- `8001` - MCP Server (changed from 8000 to avoid conflict with ai-voice service)
- `4444` - Assets Server

**Note:** Port 8000 was already in use by a uvicorn service on the shared VM.

## Security Considerations

**Current setup:**
- ✅ HTTPS with Let's Encrypt SSL
- ✅ Auto-restart on crash
- ✅ Logging to journalctl
- ❌ No authentication (MCP server is public)
- ❌ No rate limiting
- ❌ No monitoring/alerts

**For production hardening:**
- Add rate limiting in nginx
- Implement authentication if needed
- Set up monitoring (UptimeRobot, etc.)
- Configure log rotation
- Add backup strategy

## URLs

**Production Endpoint:**
```
https://pizzaz.lazzloe.com/mcp
```

**ChatGPT Integration:**
Use this URL when configuring the MCP server in ChatGPT.

## Related Documentation

- `DEV-SETUP.md` - Development environment setup (SSH tunnels)
- `setup/README.md` - Initial VM setup guide
- `tests/README.md` - Testing documentation
