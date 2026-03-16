#!/bin/bash

# AUTOMATIC SETUP SCRIPT
# Installs all essential dev tools
# Compatible with: Ubuntu, Debian, Linux Mint
# Supports: bash and zsh

set -e

echo "=========================================="
echo "AUTOMATIC DEVELOPMENT SETUP"
echo "=========================================="
echo ""

# ============================================
# DETECT SHELL
# ============================================
CURRENT_SHELL=$(basename $SHELL)
echo "Detected shell: $CURRENT_SHELL"
echo ""

# Determină fișierele de configurare
if [ "$CURRENT_SHELL" = "zsh" ]; then
    SHELL_RC_FILE="$HOME/.zshrc"
    SHELL_NAME="zsh"
elif [ "$CURRENT_SHELL" = "bash" ]; then
    SHELL_RC_FILE="$HOME/.bashrc"
    SHELL_NAME="bash"
else
    echo "Warning: Unsupported shell detected. Defaulting to bash config."
    SHELL_RC_FILE="$HOME/.bashrc"
    SHELL_NAME="bash"
fi
echo "Configuration file: $SHELL_RC_FILE"
echo ""

# ============================================
# STEP 1: UPDATE SYSTEM
# ============================================
echo "[1/6] Updating system packages..."
sudo apt update -y
sudo apt upgrade -y
echo "Done."
echo ""

# ============================================
# STEP 2: INSTALL APT PACKAGES
# ============================================
echo "[2/6] Installing APT packages..."

packages=(
    "wget"
    "curl"
    "dnsutils"
    "btop"
    "lsd"
    "hx"
    "duf"
    "fzf"
    "zoxide"
    "python3-pip"
    "pipx"
    "tmux"
    "git"
    "build-essential"
)

for package in "${packages[@]}"; do
    if ! command -v "$package" &> /dev/null && ! dpkg -l | grep -q "^ii.*$package"; then
        echo "  Installing $package..."
        sudo apt install -y "$package" || true
    else
        echo "  $package already installed"
    fi
done

echo "Done."
echo ""

# ============================================
# STEP 3: INSTALL PIPX PACKAGES
# ============================================
echo "[3/6] Installing PIPX packages..."

sudo apt install git -y
sudo apt install pip -y
sudo apt install pipx -y

echo "  Installing tui-2048..."
pipx install tui-2048

echo "Done."
echo ""

# ============================================
# STEP 4: INSTALL TUIOS
# ============================================
echo "[4/6] Installing TUIOS..."

if ! command -v tuios &> /dev/null; then
    curl -fsSL https://raw.githubusercontent.com/Gaurav-Gosain/tuios/main/install.sh | bash
    echo "TUIOS installed"
else
    echo "TUIOS already installed"
fi
echo ""

# ============================================
# STEP 5: INSTALL HOMEBREW
# ============================================
echo "[5/6] Installing Homebrew..."

if ! command -v brew &> /dev/null; then
    # Instalează Homebrew în mod neinteractiv
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Adaug Homebrew la fișierul de configurare (bash sau zsh)
    if [ -f "$SHELL_RC_FILE" ]; then
        if ! grep -q "linuxbrew" "$SHELL_RC_FILE"; then
            echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> "$SHELL_RC_FILE"
        fi
    fi

    # Setez variabilele pentru sesiunea curentă
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
    echo "Homebrew installed"
else
    echo "Homebrew already installed"
fi
echo ""

# ============================================
# STEP 6: INSTALL BREW PACKAGES
# ============================================
echo "[6/6] Installing Homebrew packages..."

brew_packages=(
    "lazydocker"
    "fd"
    "tldr"
    "posting"
)

for package in "${brew_packages[@]}"; do
    if ! brew list "$package" &> /dev/null; then
        echo "  Installing $package..."
        brew install "$package"
    else
        echo "  $package already installed"
    fi
done

echo "Done."
echo ""

# ============================================
# INSTALL STARSHIP
# ============================================
echo "Installing Starship prompt..."
curl -sS https://starship.rs/install.sh | sh -s -- --yes

# Creez directorul dacă nu există
mkdir -p ~/.config

# Generez configurația Starship
starship preset pastel-powerline -o ~/.config/starship.toml

# Adaug Starship init la fișierul de configurare (bash sau zsh) AUTOMAT
if [ -f "$SHELL_RC_FILE" ]; then
    if [ "$SHELL_NAME" = "zsh" ]; then
        if ! grep -q "starship init zsh" "$SHELL_RC_FILE"; then
            echo 'eval "$(starship init zsh)"' >> "$SHELL_RC_FILE"
        fi
    else
        if ! grep -q "starship init bash" "$SHELL_RC_FILE"; then
            echo 'eval "$(starship init bash)"' >> "$SHELL_RC_FILE"
        fi
    fi
fi

# ============================================
# FINAL
# ============================================
echo "=========================================="
echo "SETUP COMPLETE ✓"
echo "=========================================="
echo ""
echo "Schimbări aplicate automat:"
echo "  ✓ Homebrew adăugat la $SHELL_RC_FILE"
echo "  ✓ Starship init ($SHELL_NAME) adăugat la $SHELL_RC_FILE"
echo ""
echo "Următorii pași:"
echo "1. Deschide o nouă sesiune de Terminal"
echo "   (sau rulează: source $SHELL_RC_FILE)"
echo ""
echo "2. Verifică instalările:"
echo "   btop --version"
echo "   lsd --version"
echo "   hx --version"
echo "   brew --version"
echo ""
echo "Instrumente disponibile:"
echo "  btop           - System monitor"
echo "  lsd            - Modern ls"
echo "  hx             - Helix editor"
echo "  duf            - Disk usage"
echo "  fzf            - Fuzzy finder"
echo "  zoxide         - Smart cd"
echo "  tmux           - Terminal multiplexer"
echo "  tui-2048       - 2048 game"
echo "  lazydocker     - Docker UI"
echo "  starship       - Shell prompt"
echo "  tldr           - Quick docs"
echo "  posting        - HTTP client"
echo ""
