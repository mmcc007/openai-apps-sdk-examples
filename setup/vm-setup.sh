#!/bin/bash
# VM Setup Script for Pizzaz MCP Server
# Run this script on your VM (pizzaz.lazzloe.com)

set -e

echo "==================================================="
echo "Pizzaz MCP Server - VM Setup"
echo "==================================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "Step 1: Installing nginx and certbot..."
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx

echo ""
echo "Step 2: Copying nginx configuration..."
# Assuming nginx-pizzaz.conf was uploaded to /tmp/
if [ -f /tmp/nginx-pizzaz.conf ]; then
    cp /tmp/nginx-pizzaz.conf /etc/nginx/sites-available/pizzaz.lazzloe.com
    ln -sf /etc/nginx/sites-available/pizzaz.lazzloe.com /etc/nginx/sites-enabled/
else
    echo "ERROR: nginx-pizzaz.conf not found in /tmp/"
    echo "Please upload setup/nginx-pizzaz.conf to the VM first"
    exit 1
fi

echo ""
echo "Step 3: Testing nginx configuration..."
nginx -t

echo ""
echo "Step 4: Starting nginx..."
systemctl enable nginx
systemctl restart nginx

echo ""
echo "Step 5: Obtaining Let's Encrypt SSL certificate..."
echo "This will request a certificate for pizzaz.lazzloe.com"
echo ""
certbot --nginx -d pizzaz.lazzloe.com --non-interactive --agree-tos --email mmcc007@gmail.com

echo ""
echo "==================================================="
echo "VM Setup Complete!"
echo "==================================================="
echo ""
echo "Next steps:"
echo "1. Ensure DNS A record points pizzaz.lazzloe.com to this VM"
echo "2. On your local machine, set up the SSH reverse tunnel"
echo "3. Start your MCP and asset servers locally"
echo ""
