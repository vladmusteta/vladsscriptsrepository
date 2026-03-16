#!/bin/bash

# DOCKER WSL SETUP SCRIPT
# Installs Docker on WSL2 without Docker Desktop
# Compatible with: Ubuntu, Debian, Linux Mint on WSL

set -e

echo "=========================================="
echo "DOCKER WSL SETUP (No Docker Desktop)"
echo "=========================================="
echo ""

# ============================================
# CHECK IF RUNNING ON WSL
# ============================================
echo "[1/7] Checking if running on WSL..."
if grep -qi microsoft /proc/version; then
    echo "✓ WSL detected"
else
    echo "⚠ Warning: This script is optimized for WSL"
    echo "  Continuing anyway..."
fi
echo ""

# ============================================
# UPDATE SYSTEM
# ============================================
echo "[2/7] Updating system packages..."
sudo apt-get update -y
echo "Done."
echo ""

# ============================================
# INSTALL REQUIRED PACKAGES
# ============================================
echo "[3/7] Installing required packages..."
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release
echo "Done."
echo ""

# ============================================
# ADD DOCKER GPG KEY
# ============================================
echo "[4/7] Adding Docker GPG key..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "Done."
echo ""

# ============================================
# ADD DOCKER REPOSITORY
# ============================================
echo "[5/7] Adding Docker repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update -y
echo "Done."
echo ""

# ============================================
# INSTALL DOCKER
# ============================================
echo "[6/7] Installing Docker and related tools..."
sudo apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
echo "Done."
echo ""

# ============================================
# CONFIGURE USER PERMISSIONS
# ============================================
echo "[7/7] Configuring user permissions..."

# Adaug utilizatorul curent la grupul docker
sudo usermod -aG docker $USER

# Verific dacă grupul docker există, dacă nu, îl creez
if ! getent group docker > /dev/null; then
    sudo groupadd docker
    sudo usermod -aG docker $USER
fi

# Setez permisiunile socket-ului Docker
sudo chmod 666 /var/run/docker.sock 2>/dev/null || true

echo "Done."
echo ""

# ============================================
# START DOCKER SERVICE
# ============================================
echo "Starting Docker service..."
sudo service docker start || sudo systemctl start docker 2>/dev/null || true

# Verificare dacă Docker rulează
if sudo service docker status > /dev/null 2>&1 || sudo systemctl is-active --quiet docker 2>/dev/null; then
    echo "✓ Docker service started successfully"
else
    echo "⚠ Warning: Docker service may not be running"
    echo "  You can start it manually with: sudo service docker start"
fi
echo ""

# ============================================
# VERIFY INSTALLATION
# ============================================
echo "Verifying Docker installation..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version)
    echo "✓ $DOCKER_VERSION"
else
    echo "✗ Docker not found in PATH"
fi

if command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version)
    echo "✓ $COMPOSE_VERSION"
else
    echo "✗ Docker Compose not found in PATH"
fi
echo ""

# ============================================
# FINAL INSTRUCTIONS
# ============================================
echo "=========================================="
echo "DOCKER SETUP COMPLETE ✓"
echo "=========================================="
echo ""
echo "Important instructions:"
echo ""
echo "1. Log out and log back in (or restart WSL)"
echo "   This is REQUIRED for group permissions to take effect:"
echo "   wsl.exe --shutdown"
echo "   Then open a new WSL terminal"
echo ""
echo "2. Verify Docker is working:"
echo "   docker run hello-world"
echo ""
echo "3. If you get permission errors:"
echo "   a) Restart WSL (wsl.exe --shutdown)"
echo "   b) Run: sudo usermod -aG docker \$USER"
echo "   c) Then restart again"
echo ""
echo "4. Optional: Configure Docker daemon"
echo "   Edit: sudo nano /etc/docker/daemon.json"
echo "   (Useful for changing storage driver, logging, etc.)"
echo ""
echo "Useful commands:"
echo "  docker --version       - Check Docker version"
echo "  docker run hello-world - Test Docker installation"
echo "  docker ps              - List running containers"
echo "  docker images          - List downloaded images"
echo "  docker-compose --help  - Docker Compose help"
echo ""