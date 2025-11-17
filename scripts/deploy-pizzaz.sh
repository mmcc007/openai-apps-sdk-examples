#!/bin/bash
set -e

# Configuration
VM_HOST="ubuntu@46.224.27.7"
DEPLOY_DIR="/opt/pizzaz-mcp"
BASE_URL="https://pizzaz.lazzloe.com"
PNPM="/home/ubuntu/.local/share/pnpm/pnpm"

echo "🚀 Starting Pizzaz MCP deployment to production..."

# Step 1: Build assets locally
echo ""
echo "📦 Building assets with BASE_URL=$BASE_URL..."
BASE_URL=$BASE_URL pnpm run build

# Step 2: Create deployment directory on VM
echo ""
echo "📁 Creating deployment directory on VM..."
ssh $VM_HOST "sudo mkdir -p $DEPLOY_DIR && sudo chown ubuntu:ubuntu $DEPLOY_DIR"

# Step 3: Copy files to VM
echo ""
echo "📤 Copying files to VM..."
rsync -avz --delete \
  --exclude 'node_modules' \
  --exclude '.git' \
  --exclude 'dist' \
  --exclude '.next' \
  ./ $VM_HOST:$DEPLOY_DIR/

# Step 4: Install dependencies on VM
echo ""
echo "📥 Installing dependencies on VM..."
ssh $VM_HOST "cd $DEPLOY_DIR && $PNPM install"
ssh $VM_HOST "cd $DEPLOY_DIR/pizzaz_server_node && $PNPM install"

# Step 5: Copy and enable systemd services
echo ""
echo "⚙️  Setting up systemd services..."
ssh $VM_HOST "sudo cp $DEPLOY_DIR/setup/pizzaz-mcp.service /etc/systemd/system/"
ssh $VM_HOST "sudo cp $DEPLOY_DIR/setup/pizzaz-assets.service /etc/systemd/system/"
ssh $VM_HOST "sudo systemctl daemon-reload"
ssh $VM_HOST "sudo systemctl enable pizzaz-mcp.service pizzaz-assets.service"

# Step 6: Update nginx configuration
echo ""
echo "🌐 Updating nginx configuration..."
ssh $VM_HOST "sudo cp $DEPLOY_DIR/setup/nginx-pizzaz-production.conf /etc/nginx/sites-available/pizzaz.lazzloe.com"
ssh $VM_HOST "sudo nginx -t"

# Step 7: Stop SSH tunnel service if it exists (switching from dev to prod)
echo ""
echo "🛑 Stopping dev tunnel service (if exists)..."
ssh $VM_HOST "sudo systemctl stop pizzaz-tunnel.service 2>/dev/null || true"
ssh $VM_HOST "sudo systemctl disable pizzaz-tunnel.service 2>/dev/null || true"

# Step 8: Restart services
echo ""
echo "🔄 Restarting services..."
ssh $VM_HOST "sudo systemctl restart pizzaz-mcp.service pizzaz-assets.service"
ssh $VM_HOST "sudo systemctl reload nginx"

# Step 9: Check service status
echo ""
echo "✅ Checking service status..."
ssh $VM_HOST "sudo systemctl status pizzaz-mcp.service --no-pager | head -10"
ssh $VM_HOST "sudo systemctl status pizzaz-assets.service --no-pager | head -10"

# Step 10: Wait and verify health
echo ""
echo "🔍 Verifying deployment..."
sleep 5
HTTP_CODE=$(ssh $VM_HOST "curl -s -o /dev/null -w '%{http_code}' http://localhost:8001/mcp")

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ MCP server responding correctly (HTTP $HTTP_CODE)"
else
    echo "❌ MCP server not responding correctly (HTTP $HTTP_CODE)"
    echo "Check logs with: ssh $VM_HOST sudo journalctl -u pizzaz-mcp.service -n 50"
    exit 1
fi

echo ""
echo "🎉 Deployment complete!"
echo "🌐 MCP endpoint: https://pizzaz.lazzloe.com/mcp"
echo ""
echo "Useful commands:"
echo "  View MCP logs:    ssh $VM_HOST sudo journalctl -u pizzaz-mcp.service -f"
echo "  View Assets logs: ssh $VM_HOST sudo journalctl -u pizzaz-assets.service -f"
echo "  Restart services: ssh $VM_HOST sudo systemctl restart pizzaz-mcp.service pizzaz-assets.service"
