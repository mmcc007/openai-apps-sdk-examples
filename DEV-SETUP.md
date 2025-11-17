# Development Environment Setup for ChatGPT MCP Integration

This guide documents how to set up a **development environment** to test your MCP (Model Context Protocol) server with ChatGPT. This is NOT a production deployment guide.

## Overview

To integrate your local MCP server with ChatGPT, you need to expose it over HTTPS. ChatGPT requires:
- HTTPS endpoint (not HTTP)
- Support for Server-Sent Events (SSE)
- Publicly accessible URL

## Architecture: Two-Server Design

The pizzaz MCP implementation uses two separate servers:

1. **MCP Server** (port 8000): Node.js server that implements the MCP protocol
   - Reads widget HTML from filesystem
   - Serves via SSE to ChatGPT
   - Returns `structuredContent` for widget rendering

2. **Asset Server** (port 4444): Static file server
   - Serves JavaScript, CSS, and images
   - Widget HTML embeds URLs pointing to this server
   - Uses `serve` package for simple HTTP serving

The `BASE_URL` environment variable (embedded during build) connects them:
```bash
BASE_URL=https://pizzaz.lazzloe.com pnpm run build
```

This embeds `https://pizzaz.lazzloe.com` into the widget HTML for asset loading.

## Tunneling Approaches Explored

### Approach 1: ngrok (Free Tier) ❌

**Why We Tried It:** Popular, easy to use, free tier available

**What We Found:**
- Free tier shows an interstitial warning page for browser user-agents
- This warning page blocks ChatGPT from connecting to the MCP endpoint
- Would work with paid tier, but not suitable for free development

**Command Tested:**
```bash
ngrok http 8000
```

**Result:** Connection blocked by warning page

---

### Approach 2: Cloudflare Tunnels ❌

**Why We Tried It:** Free, no interstitial pages, official Cloudflare product

**What We Found:**
- Cloudflare Tunnels **buffer GET requests** including SSE streams
- The MCP protocol relies on SSE (Server-Sent Events) for real-time communication
- Even with `X-Accel-Buffering: no` header, buffering persists
- This is a known issue: https://github.com/cloudflare/cloudflared/issues/1449

**Commands Tested:**
```bash
# Quick tunnels (temporary URLs)
cloudflared tunnel --url http://localhost:8000

# Named tunnels (requires domain)
cloudflared tunnel create mcp-tunnel
cloudflared tunnel route dns mcp-tunnel mcp.yourdomain.com
cloudflared tunnel run mcp-tunnel
```

**Configuration Attempted:**
```yaml
# ~/.cloudflared/config.yml
tunnel: <tunnel-id>
credentials-file: ~/.cloudflared/<tunnel-id>.json

ingress:
  - service: http://localhost:8000
    originRequest:
      noTLSVerify: true
```

**Server-side Header Added:**
```typescript
res.setHeader("X-Accel-Buffering", "no");  // Doesn't help with Cloudflare
```

**Result:** SSE buffering prevents MCP from working

---

### Approach 3: SSH Reverse Tunnel + nginx ✅ **WORKING SOLUTION**

**Why This Works:**
- No SSE buffering issues
- Full control over nginx configuration
- Uses existing VM infrastructure (no additional cost)
- Professional SSL setup with Let's Encrypt

**Architecture:**
```
Local Machine                    VM (pizzaz.lazzloe.com)             Internet
───────────────                  ───────────────────────             ────────
MCP (8000)  ────┐               ┌→ localhost:9080
                │               │
                SSH Tunnel ─────┤                                    ChatGPT
                │               │                                    ↓
Assets (4444)───┘               └→ localhost:9081                    HTTPS:443
                                         ↓                            ↓
                                      nginx ←──────────────────────────
                                    (routes by path)
```

**How It Works:**

1. **SSH Reverse Tunnel** forwards local ports to VM:
   ```bash
   ssh -f -N -R 9080:localhost:8000 -R 9081:localhost:4444 user@vm-ip
   ```
   - `-R 9080:localhost:8000`: VM port 9080 → your local port 8000
   - `-R 9081:localhost:4444`: VM port 9081 → your local port 4444
   - Ports 9080/9081 only listen on localhost (127.0.0.1) on the VM

2. **nginx** on VM handles SSL and routing:
   ```nginx
   location /mcp {
       proxy_pass http://127.0.0.1:9080;
       proxy_buffering off;  # Critical for SSE
       proxy_cache off;
       # ... SSE-specific settings
   }

   location / {
       proxy_pass http://127.0.0.1:9081;  # Assets
   }
   ```

3. **Let's Encrypt** provides free SSL certificate
4. **DNS** points `pizzaz.lazzloe.com` to VM IP

## Complete Setup Instructions

Detailed step-by-step instructions are in [`setup/README.md`](setup/README.md), including:
- DNS configuration
- Firewall setup (ports 22, 80, 443)
- nginx installation and configuration
- SSL certificate acquisition
- SSH tunnel service setup

## Quick Start (Assuming VM Ready)

```bash
# 1. Build widgets with production URL
BASE_URL=https://pizzaz.lazzloe.com pnpm run build

# 2. Start local servers
cd pizzaz_server_node && pnpm start  # Terminal 1
pnpm -w run serve                     # Terminal 2

# 3. Start SSH tunnel
ssh -f -N -R 9080:localhost:8000 -R 9081:localhost:4444 ubuntu@your-vm-ip

# 4. Test MCP endpoint
MCP_URL=https://pizzaz.lazzloe.com/mcp pnpm exec tsx tests/test-mcp.ts

# 5. Add to ChatGPT
# Go to ChatGPT Actions → Add MCP Server → https://pizzaz.lazzloe.com/mcp
```

## Lessons Learned

### Port Conflicts
- VM may have services using common ports (8080, 8081, etc.)
- Check before choosing tunnel ports: `ssh user@vm 'sudo lsof -i:8080'`
- We use ports 9080/9081 to avoid conflicts with existing Docker containers

### CAA DNS Records
- Let's Encrypt requires CAA record allowing `letsencrypt.org` (not `.com`)
- Check existing CAA: `dig CAA yourdomain.com`
- Add if needed:
  ```
  Type: CAA
  Name: @ (or yourdomain.com)
  Tag: issue
  Value: letsencrypt.org
  ```

### Firewall Configuration
- Cloud providers often have external firewalls (e.g., Hetzner Cloud Firewall)
- Required ports:
  - 22 (SSH) - For tunnel connection
  - 80 (HTTP) - For Let's Encrypt validation
  - 443 (HTTPS) - For ChatGPT access
- Tunnel ports (9080/9081) should NOT be exposed publicly

### SSL Certificate Gotchas
- nginx config can't reference non-existent SSL certs
- Deploy temporary HTTP-only config first
- Get certificate with certbot
- Then deploy production HTTPS config

### SSE Requirements
Critical nginx settings for SSE:
```nginx
proxy_buffering off;
proxy_cache off;
proxy_set_header Connection '';
chunked_transfer_encoding off;
proxy_http_version 1.1;
```

## Testing

Run MCP protocol tests:
```bash
# Local
pnpm exec tsx tests/test-mcp.ts

# Remote
MCP_URL=https://pizzaz.lazzloe.com/mcp pnpm exec tsx tests/test-mcp.ts
```

See [`tests/README.md`](tests/README.md) for detailed testing documentation.

## Troubleshooting

### SSH Tunnel Disconnects
- Use autossh or systemd service for persistence
- Check `setup/pizzaz-tunnel.service` for systemd template

### nginx 502 Bad Gateway
- Verify SSH tunnel is active: `ps aux | grep ssh | grep 9080`
- Check tunnel ports on VM: `ssh user@vm 'ss -tlnp | grep -E "9080|9081"'`
- Restart tunnel if needed

### ChatGPT Can't Connect
- Test endpoint: `curl https://pizzaz.lazzloe.com/mcp`
- Should see SSE event stream
- Check nginx logs: `ssh user@vm 'sudo tail -f /var/log/nginx/error.log'`

### Widget Assets Don't Load
- Verify BASE_URL was set during build: `grep -r "pizzaz.lazzloe.com" assets/`
- Check asset server is running: `lsof -i:4444`
- Test asset URL: `curl https://pizzaz.lazzloe.com/pizzaz-HASH.html`

## Security Notes

- SSH tunnel is encrypted
- Ports 9080/9081 only listen on localhost (not exposed to internet)
- nginx handles SSL termination
- Let's Encrypt provides automatic certificate renewal
- Firewall only exposes ports 22, 80, 443

## What's Next?

This setup is for **development and testing**. For production deployment:
- Consider dedicated infrastructure
- Set up monitoring and logging
- Implement rate limiting
- Use process managers (PM2, systemd) for server persistence
- Regular security updates
- Backup and disaster recovery planning

## Files Reference

- `setup/` - Complete setup scripts and configs
- `tests/` - MCP protocol test suite
- `pizzaz_server_node/src/server.ts` - MCP server implementation
- `build-all.mts` - Widget build script (embeds BASE_URL)
