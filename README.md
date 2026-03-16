# Linux Development Setup Scripts

Two automated bash scripts that set up a complete development environment on WSL2 or Linux (Ubuntu, Debian, Linux Mint).

## 📋 Overview

- **`install_docker_wsl.sh`** – Sets up Docker on WSL2 without Docker Desktop
- **`linux_install_apps.sh`** – Installs development tools and utilities

---

## 🐳 Docker WSL Setup (`install_docker_wsl.sh`)

Installs Docker and essential Docker components directly on WSL2.

### Installed Packages

| Package | Purpose |
|---------|---------|
| **docker-ce** | Docker Community Edition engine |
| **docker-ce-cli** | Docker command-line interface |
| **containerd.io** | Container runtime |
| **docker-buildx-plugin** | Advanced Docker build capabilities |
| **docker-compose-plugin** | Docker Compose for multi-container apps |

### What It Does

1. Verifies WSL2 environment
2. Updates system packages
3. Adds Docker's GPG key and repository
4. Installs Docker and related tools
5. Configures user permissions (adds current user to docker group)
6. Starts the Docker service
7. Verifies installation

### Post-Installation

- Restart WSL: `wsl.exe --shutdown`
- Test Docker: `docker run hello-world`

---

## 🛠️ Development Tools Setup (`linux_install_apps.sh`)

Installs a comprehensive suite of development and terminal utilities.

### APT Packages

| Package | Purpose |
|---------|---------|
| **wget** | Download files from the web |
| **curl** | Transfer data with URLs |
| **dnsutils** | DNS lookup and diagnostics |
| **btop** | Modern system resource monitor |
| **lsd** | Modern `ls` replacement with colors/icons |
| **hx** | Helix text editor |
| **duf** | Disk usage utility with better output |
| **fzf** | Fuzzy file/command finder |
| **zoxide** | Smarter `cd` replacement |
| **python3-pip** | Python package manager |
| **pipx** | Isolated Python tool installer |
| **tmux** | Terminal multiplexer |
| **git** | Version control |
| **build-essential** | C/C++ compiler and build tools |

### Python Tools (via pipx)

| Tool | Purpose |
|------|---------|
| **tui-2048** | Terminal 2048 game |

### Homebrew (Linux) Packages

| Package | Purpose |
|---------|---------|
| **lazydocker** | Docker management UI |
| **fd** | Fast file finder (`find` replacement) |
| **tldr** | Simplified man pages |
| **posting** | HTTP client (like Postman for CLI) |

### Shell Enhancements

| Tool | Purpose |
|------|---------|
| **Starship** | Modern shell prompt with git info |

---

## 🚀 Quick Start

### Install Everything

```bash
# Docker on WSL2
curl -fsSL https://raw.githubusercontent.com/vladmusteta/vladsscriptsrepository/refs/heads/main/linux_apps/install_docker_wsl.sh | bash

# All development tools
curl -fsSL https://raw.githubusercontent.com/vladmusteta/vladsscriptsrepository/refs/heads/main/linux_apps/linux_install_apps.sh | bash
```

### Verify Installations

```bash
# Docker
docker --version
docker run hello-world

# Tools
btop --version
lsd --version
hx --version
brew --version
```

---

## 📝 Features

### Terminal Enhancements
- **Starship** – Beautiful, customizable prompt with git integration
- **Starship Theme** – Pre-configured with "pastel-powerline" theme
- Auto-detects bash/zsh and configures accordingly

### System Monitoring
- **btop** – Colorful system monitor with CPU, memory, disk, network
- **duf** – Clean disk usage breakdown

### Navigation & Searching
- **zoxide** – Smart directory jumping (`z` command)
- **fzf** – Fuzzy finder for files and history
- **lsd** – Beautiful file listing with icons

### Development Tools
- **Git** – Version control
- **Python3 + pip + pipx** – Python development
- **build-essential** – C/C++ compilation
- **tmux** – Session management
- **Helix (hx)** – Modern text editor

### Docker & Containers
- **lazydocker** – TUI for Docker management
- Full Docker Compose support

### Utilities
- **tldr** – Quick command documentation
- **posting** – Test HTTP APIs from terminal
- **fd** – Fast file searching

---

## 🔧 Requirements

- WSL2 (Windows Subsystem for Linux 2) or native Linux
- Ubuntu, Debian, or Linux Mint
- sudo access

---

## 💡 Notes

- Scripts are idempotent – safe to run multiple times
- Automatically skips packages already installed
- Configures permissions for current user
- Supports both **bash** and **zsh** shells
- Docker setup requires WSL restart for group permissions

---

## 📚 Useful Commands After Setup

```bash
# Docker
docker ps              # List running containers
docker images          # List images
docker-compose up      # Start services

# Navigation
z <directory>          # Jump to directory
cd -                   # Go to previous directory

# Finding files
fzf                    # Fuzzy find
fd <pattern>           # Fast find

# System info
btop                   # System monitor
duf                    # Disk usage

# Development
hx <file>              # Edit with Helix
tmux                   # Start session
```

---
