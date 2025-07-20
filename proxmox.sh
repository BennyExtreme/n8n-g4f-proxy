#!/bin/bash

# LXC Container Auto-Setup Script for LLM Proxy + G4F
# Run this script in your Proxmox host shell

set -e  # Exit on any error

echo "=== LXC Container Auto-Setup for LLM Proxy + G4F ==="

# Configuration variables
# Find first available LXC ID
echo "Finding first available LXC ID..."
LXC_ID=100
while pct status $LXC_ID >/dev/null 2>&1; do
    LXC_ID=$((LXC_ID + 1))
done
echo "Using LXC ID: $LXC_ID"

LXC_NAME="llm-proxy-stack"
LXC_PASSWORD="R00t123!"  # Password for the root account, useful to log-in with SFTP to upload files (such as cookies or .har)
LXC_MEMORY=4096
LXC_CORES=4
LXC_DISK_SIZE=20
TEMPLATE="local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"

echo "Checking if Ubuntu 22.04 template exists..."
if ! pveam list local | grep -q "ubuntu-22.04-standard"; then
    echo "Ubuntu 22.04 template not found. Downloading..."
    pveam update
    pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst
    echo "Template downloaded successfully."
else
    echo "Ubuntu 22.04 template found."
fi

echo "Creating LXC container with ID: $LXC_ID"

# Create LXC container
pct create $LXC_ID $TEMPLATE \
  --hostname $LXC_NAME \
  --memory $LXC_MEMORY \
  --cores $LXC_CORES \
  --rootfs local-lvm:$LXC_DISK_SIZE \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 \
  --password $LXC_PASSWORD \
  --start 1

echo "Waiting for container to start..."
sleep 10

echo "Installing dependencies inside container..."

# Execute setup commands inside the LXC
pct exec $LXC_ID -- bash << 'EOF'
set -e

echo "Updating system..."
apt update && apt upgrade -y

echo "Installing Python, Node.js, and dependencies..."
apt install -y python3 python3-pip python3-venv curl wget gnupg2 software-properties-common git ffmpeg

echo "Installing Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

echo "Installing g4f..."
pip3 install -U g4f[all]

echo "Cloning the n8n-g4f-proxy project..."
cd /opt
git clone https://github.com/korotovsky/n8n-g4f-proxy.git llm-proxy

cd /opt/llm-proxy

echo "Installing npm dependencies..."
npm install

echo "Building the project..."
npm run build

echo "Creating g4f systemd service..."
cat > /etc/systemd/system/g4f.service << 'SERVICE'
[Unit]
Description=G4F API Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llm-proxy
ExecStart=/bin/bash -c 'PYTHONPATH=/opt/llm-proxy python -m g4f --port 1337'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

echo "Creating llm-proxy systemd service..."
cat > /etc/systemd/system/llm-proxy.service << 'SERVICE'
[Unit]
Description=LLM Proxy Application
After=g4f.service
Wants=g4f.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/llm-proxy
ExecStart=/bin/bash -c 'PORT=11434 LLM_PROXY_PROVIDER=Blackbox LLM_UPSTREAM=http://127.0.0.1:1337 NODE_ENV=production npm run start'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

echo "Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable g4f.service
systemctl enable llm-proxy.service

echo "Starting g4f service..."
systemctl start g4f.service

echo "Waiting for g4f to start..."
sleep 10

echo "Starting llm-proxy service..."
systemctl start llm-proxy.service

echo "Enabling SSH root access..."
sed -i 's/^\s*#\?\s*PermitRootLogin\s\+.*/PermitRootLogin yes/' /etc/ssh/sshd_config

echo "Container setup completed!"
EOF

echo "Getting LXC IP address..."
sleep 5
LXC_IP=$(pct exec $LXC_ID -- hostname -I | awk '{print $1}' | tr -d ' \n')
echo "LXC IP: $LXC_IP"

echo ""
echo "=== SETUP COMPLETED ==="
echo "Container ID: $LXC_ID"
echo "Container Name: $LXC_NAME"
echo "Container IP: $LXC_IP"
echo ""
echo "Services should be running:"
echo "- G4F API: http://$LXC_IP:1337"
echo "- LLM Proxy: http://$LXC_IP:11434"
echo ""
echo "Test the services:"
echo "   curl http://$LXC_IP:1337/v1/models  # Test g4f"
echo "   curl http://$LXC_IP:11434/v1/models  # Test llm-proxy"
echo ""
echo "Check services status:"
ehco "   pct exec $LXC_ID -- systemctl status g4f.service --no-pager"
echo "   pct exec $LXC_ID -- systemctl status llm-proxy.service --no-pager"
echo ""
echo "Check service logs if needed:"
echo "   pct exec $LXC_ID -- journalctl -u g4f.service -f"
echo "   pct exec $LXC_ID -- journalctl -u llm-proxy.service -f"
echo ""
echo "Change root password:"
echo "   pct exec $LXC_ID -- passwd root"
echo ""
echo "Access the container directly:"
echo "   pct enter $LXC_ID"
