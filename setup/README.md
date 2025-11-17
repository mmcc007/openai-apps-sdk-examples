# Pizzaz MCP Server - Development Environment Setup

> **Note:** This guide is for setting up a **development environment** to test your MCP server with ChatGPT. For production deployment, additional considerations around monitoring, rate limiting, high availability, and security hardening are required.

This guide will help you set up the Pizzaz MCP server to be accessible via ChatGPT using SSH reverse tunneling through a VM. This approach was chosen after evaluating ngrok (interstitial page issues) and Cloudflare Tunnels (SSE buffering issues).

## Architecture Overview

```
ChatGPT
    ↓ HTTPS
pizzaz.lazzloe.com (VM)
    ├─ nginx (:443)
    │   ├─ /mcp → localhost:8080
    │   └─ /*   → localhost:8081
    ↓ SSH Reverse Tunnel
Your Local Machine
    ├─ MCP Server (port 8000)
    └─ Asset Server (port 4444)
```

## Prerequisites

- VM with public IP address
- Root/sudo access to the VM
- Domain: lazzloe.com with DNS management access
- SSH access from your local machine to the VM
- SSH key pair for authentication

## Setup Steps

### 1. DNS Configuration

Add an A record for your subdomain:

```
Type: A
Name: pizzaz (or pizzaz.lazzloe.com depending on your DNS provider)
Value: <YOUR_VM_IP_ADDRESS>
TTL: 3600 (or default)
```

**Verify DNS propagation:**
```bash
dig pizzaz.lazzloe.com
# or
nslookup pizzaz.lazzloe.com
```

### 2. VM Setup

**Step 2.1:** Copy the nginx configuration to your VM:
```bash
scp setup/nginx-pizzaz.conf your-user@your-vm-ip:/tmp/
```

**Step 2.2:** Copy and run the VM setup script:
```bash
scp setup/vm-setup.sh your-user@your-vm-ip:/tmp/
ssh your-user@your-vm-ip
sudo bash /tmp/vm-setup.sh
```

**Step 2.3:** The script will:
- Install nginx and certbot
- Configure nginx with SSE-friendly settings
- Obtain Let's Encrypt SSL certificate for pizzaz.lazzloe.com
- Enable and start nginx

**Note:** You'll need to provide your email for Let's Encrypt certificate registration.

### 3. SSH Reverse Tunnel Setup (Local Machine)

**Step 3.1:** Ensure you have SSH key access to your VM:
```bash
ssh-copy-id your-user@your-vm-ip
# or manually copy your public key to ~/.ssh/authorized_keys on the VM
```

**Step 3.2:** Test the SSH tunnel manually:
```bash
ssh -N -R 8080:localhost:8000 -R 8081:localhost:4444 your-user@your-vm-ip
```

**Step 3.3:** Set up the systemd service for automatic tunneling:

Edit `setup/pizzaz-tunnel.service` and replace:
- `VM_USER` with your VM username
- `VM_HOST` with your VM IP or hostname
- `/home/mmcc/.ssh/id_rsa` with your SSH key path

Then install the service:
```bash
sudo cp setup/pizzaz-tunnel.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable pizzaz-tunnel
sudo systemctl start pizzaz-tunnel
```

**Step 3.4:** Check tunnel status:
```bash
sudo systemctl status pizzaz-tunnel
```

### 4. Build and Start Local Servers

**Step 4.1:** Rebuild widgets with the production BASE_URL:
```bash
BASE_URL=https://pizzaz.lazzloe.com pnpm run build
```

**Step 4.2:** Start the MCP server:
```bash
cd pizzaz_server_node
pnpm start
# Should see: "Pizzaz MCP server listening on http://localhost:8000"
```

**Step 4.3:** Start the asset server (in a new terminal):
```bash
pnpm -w run serve
# Should serve from port 4444
```

### 5. Testing

**Step 5.1:** Test the MCP endpoint:
```bash
curl https://pizzaz.lazzloe.com/mcp
# Should see SSE event stream
```

**Step 5.2:** Test asset serving:
```bash
curl -I https://pizzaz.lazzloe.com/pizzaz-HASH.html
# Should return 200 OK
```

**Step 5.3:** Run the MCP protocol tests:
```bash
MCP_URL=https://pizzaz.lazzloe.com/mcp pnpm exec tsx test-mcp.ts
```

**Step 5.4:** Test in ChatGPT:
1. Go to ChatGPT → Actions
2. Add MCP server: `https://pizzaz.lazzloe.com/mcp`
3. Invoke a pizza tool
4. Verify widget renders correctly

## Troubleshooting

### SSH Tunnel Not Working

Check the tunnel status:
```bash
sudo systemctl status pizzaz-tunnel
sudo journalctl -u pizzaz-tunnel -f
```

Ensure ports 8080 and 8081 are listening on the VM:
```bash
ssh your-user@your-vm-ip 'ss -tlnp | grep -E "8080|8081"'
```

### nginx Errors

Check nginx logs on the VM:
```bash
ssh your-user@your-vm-ip 'sudo tail -f /var/log/nginx/error.log'
```

Test nginx configuration:
```bash
ssh your-user@your-vm-ip 'sudo nginx -t'
```

### SSL Certificate Issues

Renew certificate manually:
```bash
ssh your-user@your-vm-ip 'sudo certbot renew'
```

### MCP Connection Failing

Verify local servers are running:
```bash
curl http://localhost:8000/mcp
curl http://localhost:4444/
```

Check that widgets were built with correct BASE_URL:
```bash
grep -r "pizzaz.lazzloe.com" assets/
```

## Scaling to Multiple Apps

To add another MCP app (e.g., `otherapp`):

1. Create DNS record: `otherapp.lazzloe.com → VM_IP`
2. Copy and modify nginx config: `nginx-otherapp.conf`
3. Obtain SSL certificate: `certbot --nginx -d otherapp.lazzloe.com`
4. Add ports to SSH tunnel: `-R 8082:localhost:PORT1 -R 8083:localhost:PORT2`
5. Update systemd service with new ports

## Files in This Directory

- `nginx-pizzaz.conf` - nginx configuration for the VM
- `pizzaz-tunnel.service` - systemd service for SSH tunnel
- `vm-setup.sh` - Automated VM setup script
- `README.md` - This file

## Architecture Notes

**Why Two Ports?**
- Port 8080 (→ 8000): MCP server with SSE endpoints
- Port 8081 (→ 4444): Static asset server for JS/CSS/images

**Why SSH Tunnel?**
- Avoids SSE buffering issues with Cloudflare Tunnels
- No additional cost (uses existing VM)
- Full control over configuration
- Easily reproducible for multiple apps

**Security Considerations:**
- SSH tunnel is encrypted
- nginx handles SSL termination
- Local servers only accessible via tunnel
- Let's Encrypt provides free, auto-renewing certificates
