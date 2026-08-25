#!/usr/bin/env bash
# =============================================================
# Helix + development tools installer for Linux
# Supports: Ubuntu, Debian, Linux Mint, Arch Linux, Alpine Linux
#
# Run:
#   bash helix_setup_linux_complete.sh
#
# Installs Helix, zsh, language servers, Homebrew tools, Starship,
# TUI tools and configures ~/.config/helix and ~/.zshrc.
# =============================================================
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { printf '%b[INFO]%b  %s\n' "$GREEN" "$NC" "$*"; }
warn()    { printf '%b[WARN]%b  %s\n' "$YELLOW" "$NC" "$*"; }
error()   { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
section() { printf '\n%b==> %s%b\n' "$CYAN" "$*" "$NC"; }

[[ -n "${BASH_VERSION:-}" ]] || error 'Ruleaza acest script cu bash.'
[[ "$(id -u)" -ne 0 ]] || error 'Nu rula scriptul ca root; este necesar sudo pentru pachetele sistem.'
command -v sudo >/dev/null 2>&1 || error 'sudo nu este instalat sau nu este disponibil.'

DISTRO_ID=''
DISTRO_LIKE=''
DISTRO=''

# ------------------------------------------------------------
# Detectare distributie
# ------------------------------------------------------------
detect_distro() {
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID,,}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_LIKE="${DISTRO_LIKE,,}"
    elif [[ -r /etc/arch-release ]]; then
        DISTRO_ID='arch'
        DISTRO_LIKE='arch'
    elif [[ -r /etc/alpine-release ]]; then
        DISTRO_ID='alpine'
        DISTRO_LIKE='alpine'
    else
        error 'Nu pot detecta distributia Linux.'
    fi

    case "$DISTRO_ID" in
        ubuntu|debian|linuxmint|pop|elementary|zorin)
            DISTRO='debian'
            ;;
        arch|manjaro|endeavouros|garuda)
            DISTRO='arch'
            ;;
        alpine)
            DISTRO='alpine'
            ;;
        *)
            if [[ "$DISTRO_LIKE" == *debian* || "$DISTRO_LIKE" == *ubuntu* ]]; then
                DISTRO='debian'
            elif [[ "$DISTRO_LIKE" == *arch* ]]; then
                DISTRO='arch'
            else
                error "Distributie nesuportata: $DISTRO_ID"
            fi
            ;;
    esac

    info "Distributie detectata: $DISTRO_ID (tratata ca $DISTRO)"
}

pkg_update() {
    case "$DISTRO" in
        debian) sudo apt-get update -qq ;;
        arch)   sudo pacman -Sy --noconfirm ;;
        alpine) sudo apk update -q ;;
    esac
}

pkg_upgrade() {
    case "$DISTRO" in
        debian) sudo apt-get upgrade -y ;;
        arch)   sudo pacman -Su --noconfirm ;;
        alpine) sudo apk upgrade ;;
    esac
}

pkg_install() {
    case "$DISTRO" in
        debian) sudo apt-get install -y "$@" ;;
        arch)   sudo pacman -S --noconfirm --needed "$@" ;;
        alpine) sudo apk add --no-cache "$@" ;;
    esac
}

install_optional_pipx_package() {
    local package="$1"

    if command -v pipx >/dev/null 2>&1; then
        if pipx list 2>/dev/null | grep -q "package $package "; then
            info "$package este deja instalat prin pipx."
        else
            pipx install "$package"
        fi
    else
        warn "pipx nu este disponibil; sar peste $package."
    fi
}

# ------------------------------------------------------------
# Directoare si variabile
# ------------------------------------------------------------
detect_distro

TOOLS_DIR="$HOME/tools"
PACKAGES_DIR="$HOME/packages"
HELIX_DIR="$TOOLS_DIR/helix"
HELIX_CONFIG_DIR="$HOME/.config/helix"
PY_VENV="$HOME/.local/share/helix/python-venv"
ZSHRC="$HOME/.zshrc"
NVM_DIR="$HOME/.nvm"
LOCAL_BIN="$HOME/.local/bin"
BREW_BIN='/home/linuxbrew/.linuxbrew/bin/brew'
BREW_PREFIX=''

mkdir -p "$TOOLS_DIR" "$PACKAGES_DIR" "$HELIX_CONFIG_DIR" "$LOCAL_BIN"

# ------------------------------------------------------------
# Update si dependente sistem
# ------------------------------------------------------------
section 'Update sistem si instalare dependente'
pkg_update
pkg_upgrade

case "$DISTRO" in
    debian)
        pkg_install \
            git curl wget unzip tar gzip xz-utils \
            build-essential pkg-config \
            python3 python3-pip python3-venv \
            ripgrep fd-find universal-ctags \
            tree bat fzf jq shellcheck zsh \
            dnsutils btop lsd duf pipx tmux
        ;;
    arch)
        pkg_install \
            git curl wget unzip tar gzip xz \
            base-devel pkgconf \
            python python-pip \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh \
            bind btop lsd duf python-pipx tmux
        ;;
    alpine)
        pkg_install \
            git curl wget unzip tar gzip xz \
            build-base pkgconf \
            python3 py3-pip py3-virtualenv \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh \
            bind-tools btop lsd duf tmux
        ;;
esac

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"
fi

# ------------------------------------------------------------
# zsh ca shell implicit
# ------------------------------------------------------------
section 'Configurare zsh ca shell implicit'
ZSH_BIN="$(command -v zsh || true)"
[[ -n "$ZSH_BIN" && -x "$ZSH_BIN" ]] || error 'zsh nu a fost gasit dupa instalare.'

if ! grep -Fxq "$ZSH_BIN" /etc/shells; then
    printf '%s\n' "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7 || true)"
if [[ "$CURRENT_LOGIN_SHELL" == "$ZSH_BIN" ]]; then
    info "zsh este deja shell-ul implicit pentru $USER."
elif [[ -t 0 ]]; then
    chsh -s "$ZSH_BIN"
    info 'zsh va deveni activ la urmatoarea autentificare.'
else
    warn 'Sesiunea nu este interactiva; ruleaza manual: chsh -s '"$ZSH_BIN"''
fi

# ------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------
section 'Instalare Homebrew'

if [[ ! -x "$BREW_BIN" ]]; then
    NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

[[ -x "$BREW_BIN" ]] || error 'Homebrew nu a putut fi instalat.'
BREW_PREFIX="$($BREW_BIN --prefix)"
eval "$("$BREW_BIN" shellenv)"

# ------------------------------------------------------------
# Pachete Homebrew
# ------------------------------------------------------------
section 'Instalare pachete Homebrew'
for package in lazydocker fd tldr posting; do
    if "$BREW_BIN" list "$package" >/dev/null 2>&1; then
        info "$package este deja instalat."
    else
        "$BREW_BIN" install "$package"
    fi
done

# ------------------------------------------------------------
# pipx
# ------------------------------------------------------------
section 'Instalare aplicatii pipx'
pipx ensurepath >/dev/null 2>&1 || true
install_optional_pipx_package tui-2048

# ------------------------------------------------------------
# TUIOS
# ------------------------------------------------------------
section 'Instalare TUIOS'
if command -v tuios >/dev/null 2>&1; then
    info 'TUIOS este deja instalat.'
else
    curl -fsSL \
        https://raw.githubusercontent.com/Gaurav-Gosain/tuios/main/install.sh |
        bash
fi

# ------------------------------------------------------------
# Starship
# ------------------------------------------------------------
section 'Instalare Starship'
if command -v starship >/dev/null 2>&1; then
    info 'Starship este deja instalat.'
else
    curl -sS https://starship.rs/install.sh | sh -s -- --yes
fi

mkdir -p "$HOME/.config"
if command -v starship >/dev/null 2>&1; then
    starship preset pastel-powerline -o "$HOME/.config/starship.toml"
fi

# ------------------------------------------------------------
# bash-language-server prin NVM
# ------------------------------------------------------------
section 'Instalare bash-language-server pentru Helix'
export NVM_DIR

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    curl -fsSL \
        https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh |
        bash
fi

# shellcheck disable=SC1090
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

if command -v nvm >/dev/null 2>&1; then
    nvm install --lts
    nvm alias default 'lts/*'
    nvm use --lts >/dev/null
    npm install --global bash-language-server
else
    warn 'NVM nu este disponibil; bash-language-server nu a fost instalat.'
fi

# ------------------------------------------------------------
# Pachete Python pentru Helix
# ------------------------------------------------------------
section 'Instalare language server Python'
PYTHON_BIN="$(command -v python3 || command -v python || true)"
[[ -n "$PYTHON_BIN" ]] || error 'Python nu a fost gasit.'

if [[ ! -x "$PY_VENV/bin/python" ]]; then
    "$PYTHON_BIN" -m venv "$PY_VENV"
fi

"$PY_VENV/bin/python" -m pip install --upgrade pip
"$PY_VENV/bin/python" -m pip install \
    'python-lsp-server[all]' \
    pylsp-mypy \
    python-lsp-isort \
    python-lsp-black

# ------------------------------------------------------------
# lua-language-server
# ------------------------------------------------------------
section 'Instalare lua-language-server'
LUA_LS_DIR="$TOOLS_DIR/lua-language-server"
LUA_LS_VERSION='3.6.11'

if [[ ! -x "$LUA_LS_DIR/bin/lua-language-server" ]]; then
    case "$(uname -m)" in
        x86_64) LUA_LS_ARCH='linux-x64' ;;
        aarch64|arm64) LUA_LS_ARCH='linux-arm64' ;;
        *) error "Arhitectura $(uname -m) nu este suportata pentru lua-language-server." ;;
    esac

    LUA_LS_SRC="$PACKAGES_DIR/lua-language-server-${LUA_LS_VERSION}.tar.gz"
    LUA_LS_URL="https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-${LUA_LS_ARCH}.tar.gz"

    wget -q "$LUA_LS_URL" -O "$LUA_LS_SRC"
    rm -rf "$LUA_LS_DIR"
    mkdir -p "$LUA_LS_DIR"
    tar -xzf "$LUA_LS_SRC" -C "$LUA_LS_DIR"
fi

# ------------------------------------------------------------
# Helix
# ------------------------------------------------------------
section 'Instalare Helix'

if [[ -n "$BREW_PREFIX" ]]; then
    if "$BREW_BIN" list helix >/dev/null 2>&1; then
        info 'Helix este deja instalat prin Homebrew.'
    else
        "$BREW_BIN" install helix
    fi
else
    case "$(uname -m)" in
        x86_64) HELIX_ARCH='x86_64' ;;
        aarch64|arm64) HELIX_ARCH='aarch64' ;;
        *) error "Arhitectura $(uname -m) nu este suportata pentru Helix." ;;
    esac

    HELIX_VERSION="$(
        curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest |
        grep -m1 '"tag_name"' |
        sed -E 's/.*"tag_name": "([^"]+)".*/\1/'
    )"
    [[ -n "$HELIX_VERSION" ]] || error 'Nu pot determina versiunea Helix.'

    HELIX_SRC="$PACKAGES_DIR/helix.tar.xz"
    HELIX_URL="https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION#v}-${HELIX_ARCH}-linux.tar.xz"

    wget -q "$HELIX_URL" -O "$HELIX_SRC"
    rm -rf "$HELIX_DIR"
    mkdir -p "$HELIX_DIR"
    tar -xJf "$HELIX_SRC" --strip-components=1 -C "$HELIX_DIR"
    ln -sfn "$HELIX_DIR/hx" "$LOCAL_BIN/hx"
fi

# ------------------------------------------------------------
# Configurare ~/.zshrc
# ------------------------------------------------------------
section 'Configurare ~/.zshrc'
touch "$ZSHRC"
BACKUP="$ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
cp "$ZSHRC" "$BACKUP"
info "Backup creat: $BACKUP"

python3 - "$ZSHRC" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

for name in (
    "HELIX_SETUP_PATH",
    "HELIX_SETUP_NVM",
    "HELIX_SETUP_ENV",
    "HELIX_SETUP_BREW",
    "HELIX_SETUP_STARSHIP",
):
    pattern = rf"\n?# >>> {name} >>>.*?\n# <<< {name} <<<\n?"
    text = re.sub(pattern, "\n", text, flags=re.S)

path.write_text(text)
PY

cat >> "$ZSHRC" <<EOF

# >>> HELIX_SETUP_PATH >>>
# PATH managed by helix_setup_linux_complete.sh
typeset -U PATH path
path=(
  "$LOCAL_BIN"
  "$LUA_LS_DIR/bin"
  "$BREW_PREFIX/bin"
  "$BREW_PREFIX/sbin"
  "\$path[@]"
)
# <<< HELIX_SETUP_PATH <<<

# >>> HELIX_SETUP_BREW >>>
# Homebrew managed by helix_setup_linux_complete.sh
eval "\$("$BREW_BIN" shellenv)"
# <<< HELIX_SETUP_BREW <<<

# >>> HELIX_SETUP_NVM >>>
# NVM managed by helix_setup_linux_complete.sh
export NVM_DIR="\$HOME/.nvm"
[[ -s "\$NVM_DIR/nvm.sh" ]] && source "\$NVM_DIR/nvm.sh"
# <<< HELIX_SETUP_NVM <<<

# >>> HELIX_SETUP_STARSHIP >>>
# Starship managed by helix_setup_linux_complete.sh
eval "\$(starship init zsh)"
# <<< HELIX_SETUP_STARSHIP <<<

# >>> HELIX_SETUP_ENV >>>
# Helix managed by helix_setup_linux_complete.sh
if [[ -d "\$HOME/tools/helix/runtime" ]]; then
    export HELIX_RUNTIME="\$HOME/tools/helix/runtime"
else
    unset HELIX_RUNTIME
fi
# <<< HELIX_SETUP_ENV <<<
EOF

# ------------------------------------------------------------
# Configurare Helix
# ------------------------------------------------------------
section 'Configurare Helix'

if [[ ! -f "$HELIX_CONFIG_DIR/config.toml" ]]; then
    cat > "$HELIX_CONFIG_DIR/config.toml" <<'EOF'
theme = "base16_default_dark"

[editor]
line-number = "relative"
mouse = true
cursorline = true
bufferline = "multiple"
color-modes = true

[editor.indent-guides]
render = true
character = "┊"

[keys.normal]
C-s = ":write"
C-q = ":quit"
EOF
else
    info 'config.toml exista deja; nu il suprascriu.'
fi

cat > "$HELIX_CONFIG_DIR/languages.toml" <<EOF
# Generated by helix_setup_linux_complete.sh

[[language]]
name = "bash"
language-servers = ["bash-language-server"]

[[language]]
name = "python"
language-servers = ["pylsp"]

[[language]]
name = "lua"
language-servers = ["lua-language-server"]

[language-server.bash-language-server]
command = "bash-language-server"
args = ["start"]

[language-server.pylsp]
command = "$PY_VENV/bin/pylsp"

[language-server.lua-language-server]
command = "$LUA_LS_DIR/bin/lua-language-server"
args = ["-E", "$LUA_LS_DIR/main.lua"]
EOF

# ------------------------------------------------------------
# Verificare finala
# ------------------------------------------------------------
section 'Verificare finala'

HX_BIN="$(command -v hx || true)"
if [[ -z "$HX_BIN" && -x "$LOCAL_BIN/hx" ]]; then
    HX_BIN="$LOCAL_BIN/hx"
fi

HELIX_INFO='lipsa'
[[ -n "$HX_BIN" && -x "$HX_BIN" ]] && HELIX_INFO="$($HX_BIN --version | head -1)"

printf '  %-24s %s\n' 'helix:' "$HELIX_INFO"
printf '  %-24s %s\n' 'zsh:' "$(zsh --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'default shell:' "$(getent passwd "$USER" | cut -d: -f7 || echo 'necunoscut')"
printf '  %-24s %s\n' 'node:' "$(node --version 2>/dev/null || echo 'restart shell')"
printf '  %-24s %s\n' 'bash-language-server:' "$(bash-language-server --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'python3:' "$($PYTHON_BIN --version)"
printf '  %-24s %s\n' 'ripgrep:' "$(rg --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'ctags:' "$(ctags --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'lua-language-server:' "$([[ -x "$LUA_LS_DIR/bin/lua-language-server" ]] && echo 'instalat' || echo 'lipsa')"
printf '  %-24s %s\n' 'starship:' "$(starship --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'brew:' "$("$BREW_BIN" --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'config:' "$HELIX_CONFIG_DIR"
printf '  %-24s %s\n' 'zshrc:' "$ZSHRC"

echo
echo 'Instalare completa.'
echo 'Shell implicit: zsh'
echo 'Ruleaza: exec zsh'
echo 'Apoi verifica Helix cu: hx --health'
echo 'Verifica tool-urile cu: brew list, pipx list si command -v tuios'
echo 'Porneste Helix cu: hx'
