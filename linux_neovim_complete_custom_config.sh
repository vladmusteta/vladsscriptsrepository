#!/bin/bash
# =============================================================
# Neovim + dependencies installer for Linux
# Suporta: Ubuntu, Debian, Arch Linux, Alpine Linux
# Ruleaza cu: bash nvim_setup_linux.sh
# =============================================================
set -euo pipefail

# ------------------------------------------------------------
# Culori pentru output
# ------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}==> $*${NC}"; }

# ------------------------------------------------------------
# Detecteaza distributia
# ------------------------------------------------------------
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_LIKE="${ID_LIKE,,}"
    elif [ -f /etc/arch-release ]; then
        DISTRO_ID="arch"
        DISTRO_LIKE="arch"
    elif [ -f /etc/alpine-release ]; then
        DISTRO_ID="alpine"
        DISTRO_LIKE="alpine"
    else
        error "Nu pot detecta distributia Linux."
    fi

    # Normalizeaza
    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|elementary|zorin)
            DISTRO="debian"
            ;;
        arch|manjaro|endeavouros|garuda)
            DISTRO="arch"
            ;;
        alpine)
            DISTRO="alpine"
            ;;
        *)
            if [[ "${DISTRO_LIKE:-}" == *"debian"* ]] || [[ "${DISTRO_LIKE:-}" == *"ubuntu"* ]]; then
                DISTRO="debian"
            elif [[ "${DISTRO_LIKE:-}" == *"arch"* ]]; then
                DISTRO="arch"
            else
                error "Distributie nesuportata: $DISTRO_ID. Suportate: Ubuntu/Debian, Arch, Alpine."
            fi
            ;;
    esac

    info "Distributie detectata: $DISTRO_ID (tratata ca $DISTRO)"
}

# ------------------------------------------------------------
# Instaleaza pachete sistem
# ------------------------------------------------------------
pkg_install() {
    case "$DISTRO" in
        debian) sudo apt-get install -y "$@" ;;
        arch)   sudo pacman -S --noconfirm --needed "$@" ;;
        alpine) sudo apk add --no-cache "$@" ;;
    esac
}

pkg_update() {
    case "$DISTRO" in
        debian) sudo apt-get update -qq ;;
        arch)   sudo pacman -Sy --noconfirm ;;
        alpine) sudo apk update -q ;;
    esac
}

# ------------------------------------------------------------
# Directoare de lucru
# ------------------------------------------------------------
TOOLS_DIR="$HOME/tools"
PACKAGES_DIR="$HOME/packages"
mkdir -p "$TOOLS_DIR" "$PACKAGES_DIR"

# ------------------------------------------------------------
# Detecteaza distro
# ------------------------------------------------------------
detect_distro

# ------------------------------------------------------------
# 1. Curata instalari vechi de nvim
# ------------------------------------------------------------
section "Curatare instalari vechi de nvim"
rm -rf "$TOOLS_DIR/nvim"
rm -rf "$HOME/.config/nvim" "$HOME/.config/nvim.backup"
rm -rf "$HOME/.local/share/nvim" "$HOME/.local/state/nvim" "$HOME/.cache/nvim"
info "Curat."

# ------------------------------------------------------------
# 2. Dependente sistem
# ------------------------------------------------------------
section "Instalare dependente sistem"
pkg_update

case "$DISTRO" in
    debian)
        pkg_install \
            git curl wget unzip tar \
            build-essential autoconf automake pkg-config \
            libpcre2-dev python3 python3-pip \
            universal-ctags ripgrep
        ;;
    arch)
        pkg_install \
            git curl wget unzip tar \
            base-devel autoconf automake pkgconf \
            pcre2 python python-pip \
            ctags ripgrep
        ;;
    alpine)
        pkg_install \
            git curl wget unzip tar \
            build-base autoconf automake pkgconf \
            pcre2-dev python3 py3-pip \
            ctags ripgrep
        ;;
esac

# ------------------------------------------------------------
# 3. Node.js via NVM
# ------------------------------------------------------------
section "Instalare Node.js via NVM"
export NVM_DIR="$HOME/.nvm"

if ! command -v node &>/dev/null && [ ! -d "$NVM_DIR" ]; then
    info "Instalare NVM..."
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm use --lts
    info "Node.js instalat: $(node --version)"
else
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    info "Node.js deja disponibil: $(node --version 2>/dev/null || echo 'reload shell dupa instalare')"
fi

# ------------------------------------------------------------
# 4. Language servers via npm
# ------------------------------------------------------------
section "Instalare language servers npm"
if command -v npm &>/dev/null; then
    npm install -g vim-language-server bash-language-server
    info "vim-language-server si bash-language-server instalate."
else
    warn "npm nu e disponibil inca — ruleaza manual dupa restart."
fi

# ------------------------------------------------------------
# 5. Python packages
# ------------------------------------------------------------
section "Instalare pachete Python"
PYTHON_BIN=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || true)
[ -z "$PYTHON_BIN" ] && error "Python3 nu a fost gasit dupa instalare!"

PY_PACKAGES=(
    pynvim
    'python-lsp-server[all]'
    pylsp-mypy
    python-lsp-isort
    python-lsp-black
    vim-vint
)

case "$DISTRO" in
    debian)
        "$PYTHON_BIN" -m pip install --break-system-packages --user "${PY_PACKAGES[@]}" 2>/dev/null || \
        "$PYTHON_BIN" -m pip install --user "${PY_PACKAGES[@]}"
        ;;
    arch|alpine)
        "$PYTHON_BIN" -m pip install --user "${PY_PACKAGES[@]}"
        ;;
esac
info "Pachete Python instalate."

# ------------------------------------------------------------
# 6. lua-language-server
# ------------------------------------------------------------
section "Instalare lua-language-server"
LUA_LS_DIR="$TOOLS_DIR/lua-language-server"
LUA_LS_VERSION="3.6.11"

if [ ! -f "$LUA_LS_DIR/bin/lua-language-server" ]; then
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  LUA_LS_ARCH="linux-x64" ;;
        aarch64) LUA_LS_ARCH="linux-arm64" ;;
        *)        error "Arhitectura $ARCH nu e suportata pentru lua-language-server." ;;
    esac

    LUA_LS_LINK="https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-${LUA_LS_ARCH}.tar.gz"
    LUA_LS_SRC="$PACKAGES_DIR/lua-language-server.tar.gz"

    info "Descarcare lua-language-server ${LUA_LS_VERSION} (${LUA_LS_ARCH})..."
    wget -q "$LUA_LS_LINK" -O "$LUA_LS_SRC"
    mkdir -p "$LUA_LS_DIR"
    tar zxf "$LUA_LS_SRC" -C "$LUA_LS_DIR"
    info "lua-language-server instalat in $LUA_LS_DIR"
else
    info "lua-language-server deja instalat."
fi

# ------------------------------------------------------------
# 7. Neovim (ultima versiune stabila, binar oficial)
# ------------------------------------------------------------
section "Instalare Neovim stable"
NVIM_DIR="$TOOLS_DIR/nvim"
ARCH=$(uname -m)

case "$ARCH" in
    x86_64)  NVIM_ARCH="nvim-linux-x86_64" ;;
    aarch64) NVIM_ARCH="nvim-linux-arm64" ;;
    *)        error "Arhitectura $ARCH nu e suportata pentru binarul Neovim." ;;
esac

mkdir -p "$NVIM_DIR"
NVIM_SRC="$PACKAGES_DIR/nvim.tar.gz"
info "Descarcare Neovim stable (${ARCH})..."
wget -q "https://github.com/neovim/neovim/releases/download/stable/${NVIM_ARCH}.tar.gz" -O "$NVIM_SRC"
tar xzf "$NVIM_SRC" --strip-components 1 -C "$NVIM_DIR"
info "Neovim instalat: $("$NVIM_DIR/bin/nvim" --version | head -1)"

# ------------------------------------------------------------
# 8. Adauga PATH in shell config (fara duplicate)
# ------------------------------------------------------------
section "Configurare PATH"

# Detecteaza shell config file
if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ "$SHELL" = "/bin/bash" ] || [ "$SHELL" = "/usr/bin/bash" ]; then
    SHELL_RC="$HOME/.bashrc"
else
    SHELL_RC="$HOME/.profile"
fi
info "Shell config: $SHELL_RC"
touch "$SHELL_RC"

add_to_rc() {
    local line="$1"
    grep -qxF "$line" "$SHELL_RC" 2>/dev/null || echo "$line" >> "$SHELL_RC"
}

add_to_rc "export PATH=\"\$HOME/tools/nvim/bin:\$PATH\""
add_to_rc "export PATH=\"\$HOME/tools/lua-language-server/bin:\$PATH\""
add_to_rc "export PATH=\"\$HOME/.local/bin:\$PATH\""

# NVM
if [ -d "$HOME/.nvm" ]; then
    grep -q 'NVM_DIR' "$SHELL_RC" 2>/dev/null || cat >> "$SHELL_RC" << 'NVMEOF'

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
NVMEOF
fi

# ------------------------------------------------------------
# 9. Cloneaza config-ul jdhao
# ------------------------------------------------------------
section "Clonare config nvim jdhao"
mkdir -p "$HOME/.config/nvim"
git clone --depth=1 https://github.com/jdhao/nvim-config.git "$HOME/.config/nvim"
info "Config clonat in ~/.config/nvim"

# ------------------------------------------------------------
# 10. Instaleaza pluginurile headless
# ------------------------------------------------------------
section "Instalare pluginuri nvim"
info "Poate dura cateva minute..."
"$NVIM_DIR/bin/nvim" --headless \
    -c "autocmd User LazyInstall quitall" \
    -c "lua require('lazy').install()" 2>/dev/null || true

# ------------------------------------------------------------
# 11. Treesitter parsers
# ------------------------------------------------------------
section "Instalare Treesitter parsers"
"$NVIM_DIR/bin/nvim" --headless \
    +"TSInstall css html javascript typescript tsx vue scss svelte lua python bash" \
    +qa 2>/dev/null || true
info "Parsers instalati."

# ------------------------------------------------------------
# Verificare finala
# ------------------------------------------------------------
echo ""
echo -e "${CYAN}============================================${NC}"
info "Instalare completa!"
echo -e "${CYAN}============================================${NC}"
echo ""
printf "  %-24s %s\n" "nvim:"                "$("$NVIM_DIR/bin/nvim" --version | head -1)"
printf "  %-24s %s\n" "node:"                "$(node --version 2>/dev/null || echo 'restart shell')"
printf "  %-24s %s\n" "python3:"             "$("$PYTHON_BIN" --version)"
printf "  %-24s %s\n" "ripgrep:"             "$(rg --version 2>/dev/null | head -1 || echo 'lipsa')"
printf "  %-24s %s\n" "ctags:"               "$(ctags --version 2>/dev/null | head -1 || echo 'lipsa')"
printf "  %-24s %s\n" "lua-language-server:" "$([ -f "$LUA_LS_DIR/bin/lua-language-server" ] && echo 'instalat' || echo 'lipsa')"
echo ""
warn "Ruleaza: source $SHELL_RC"
warn "Apoi porneste nvim cu: nvim"
