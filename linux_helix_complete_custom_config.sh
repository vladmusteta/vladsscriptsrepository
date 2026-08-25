#!/usr/bin/env bash
# =============================================================
# Helix + dependencies installer for Linux
# Supports: Ubuntu, Debian, Arch Linux, Alpine Linux
#
# Run:
#   bash helix_setup_linux.sh
#
# Installs Helix, language servers and dependencies, configures
# ~/.config/helix, configures ~/.zshrc, and sets zsh as the
# default login shell.
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

pkg_install() {
    case "$DISTRO" in
        debian) sudo apt-get install -y "$@" ;;
        arch)   sudo pacman -S --noconfirm --needed "$@" ;;
        alpine) sudo apk add --no-cache "$@" ;;
    esac
}

# ------------------------------------------------------------
# Directoare
# ------------------------------------------------------------
TOOLS_DIR="$HOME/tools"
PACKAGES_DIR="$HOME/packages"
HELIX_DIR="$TOOLS_DIR/helix"
HELIX_CONFIG_DIR="$HOME/.config/helix"
PY_VENV="$HOME/.local/share/helix/python-venv"
ZSHRC="$HOME/.zshrc"
NVM_DIR="$HOME/.nvm"

mkdir -p "$TOOLS_DIR" "$PACKAGES_DIR" "$HELIX_CONFIG_DIR"

# ------------------------------------------------------------
# Detectare distributie
# ------------------------------------------------------------
detect_distro

# ------------------------------------------------------------
# Dependente sistem
# ------------------------------------------------------------
section 'Instalare dependente sistem'
pkg_update

case "$DISTRO" in
    debian)
        pkg_install \
            git curl wget unzip tar gzip xz-utils \
            build-essential pkg-config \
            python3 python3-pip python3-venv \
            ripgrep fd-find universal-ctags \
            tree bat fzf jq shellcheck zsh
        ;;
    arch)
        pkg_install \
            git curl wget unzip tar gzip xz \
            base-devel pkgconf \
            python python-pip \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh
        ;;
    alpine)
        pkg_install \
            git curl wget unzip tar gzip xz \
            build-base pkgconf \
            python3 py3-pip py3-virtualenv \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh
        ;;
esac

# Debian calls the executable fdfind.
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/bin"
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
fi

# ------------------------------------------------------------
# zsh ca shell implicit
# ------------------------------------------------------------
section 'Configurare zsh ca shell implicit'

ZSH_BIN="$(command -v zsh || true)"
[[ -n "$ZSH_BIN" && -x "$ZSH_BIN" ]] || error 'zsh nu a fost gasit dupa instalare.'

if [[ ! -r /etc/shells ]]; then
    error '/etc/shells nu poate fi citit.'
fi

if ! grep -Fxq "$ZSH_BIN" /etc/shells; then
    info "Adaug $ZSH_BIN in /etc/shells..."
    printf '%s\n' "$ZSH_BIN" | sudo tee -a /etc/shells >/dev/null
fi

CURRENT_LOGIN_SHELL="$(getent passwd "$USER" | cut -d: -f7 || true)"
if [[ "$CURRENT_LOGIN_SHELL" == "$ZSH_BIN" ]]; then
    info "zsh este deja shell-ul implicit pentru utilizatorul $USER."
elif [[ -t 0 ]]; then
    info "Setez zsh ca shell implicit pentru utilizatorul $USER..."
    chsh -s "$ZSH_BIN"
    info 'Schimbarea va deveni activa la urmatoarea autentificare.'
else
    warn 'Sesiunea nu este interactiva; nu pot executa chsh automat.'
    warn "Ruleaza manual: chsh -s '$ZSH_BIN'"
fi

# ------------------------------------------------------------
# bash-language-server pentru Helix
# ------------------------------------------------------------
section 'Instalare bash-language-server pentru Helix'
export NVM_DIR

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    info 'Instalare NVM 0.40.7...'
    curl -fsSL \
        https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh |
        bash
fi

# shellcheck disable=SC1090
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    source "$NVM_DIR/nvm.sh"
fi

if command -v nvm >/dev/null 2>&1; then
    nvm install --lts
    nvm alias default 'lts/*'
    nvm use --lts >/dev/null
    info "Node.js: $(node --version)"

    if command -v bash-language-server >/dev/null 2>&1; then
        info 'bash-language-server este deja instalat.'
    else
        npm install --global bash-language-server
    fi
else
    warn 'NVM nu este disponibil in sesiunea curenta.'
fi

# ------------------------------------------------------------
# Pachete Python in mediu virtual izolat
# ------------------------------------------------------------
section 'Instalare pachete Python'
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
        x86_64)
            LUA_LS_ARCH='linux-x64'
            ;;
        aarch64|arm64)
            LUA_LS_ARCH='linux-arm64'
            ;;
        *)
            error "Arhitectura $(uname -m) nu este suportata pentru lua-language-server."
            ;;
    esac

    LUA_LS_SRC="$PACKAGES_DIR/lua-language-server-${LUA_LS_VERSION}.tar.gz"
    LUA_LS_URL="https://github.com/LuaLS/lua-language-server/releases/download/${LUA_LS_VERSION}/lua-language-server-${LUA_LS_VERSION}-${LUA_LS_ARCH}.tar.gz"

    info "Descarcare lua-language-server ${LUA_LS_VERSION}..."
    wget -q "$LUA_LS_URL" -O "$LUA_LS_SRC"
    rm -rf "$LUA_LS_DIR"
    mkdir -p "$LUA_LS_DIR"
    tar -xzf "$LUA_LS_SRC" -C "$LUA_LS_DIR"
fi

# ------------------------------------------------------------
# Helix
# ------------------------------------------------------------
section 'Instalare Helix'
BREW_BIN='/home/linuxbrew/.linuxbrew/bin/brew'
BREW_PREFIX=''

if [[ -x "$BREW_BIN" ]]; then
    BREW_PREFIX="$($BREW_BIN --prefix)"
fi

if [[ -n "$BREW_PREFIX" ]]; then
    if "$BREW_BIN" list helix >/dev/null 2>&1; then
        info 'Helix este deja instalat prin Homebrew.'
    else
        "$BREW_BIN" install helix
    fi
else
    case "$(uname -m)" in
        x86_64)
            HELIX_ARCH='x86_64'
            ;;
        aarch64|arm64)
            HELIX_ARCH='aarch64'
            ;;
        *)
            error "Arhitectura $(uname -m) nu este suportata pentru Helix."
            ;;
    esac

    HELIX_VERSION="$(
        curl -fsSL \
            https://api.github.com/repos/helix-editor/helix/releases/latest |
            grep -m1 '"tag_name"' |
            sed -E 's/.*"tag_name": "([^"]+)".*/\1/'
    )"
    [[ -n "$HELIX_VERSION" ]] || error 'Nu pot determina versiunea Helix.'

    HELIX_SRC="$PACKAGES_DIR/helix.tar.xz"
    HELIX_URL="https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION#v}-${HELIX_ARCH}-linux.tar.xz"

    info "Descarcare Helix ${HELIX_VERSION}..."
    wget -q "$HELIX_URL" -O "$HELIX_SRC"
    rm -rf "$HELIX_DIR"
    mkdir -p "$HELIX_DIR"
    tar -xJf "$HELIX_SRC" --strip-components=1 -C "$HELIX_DIR"

    mkdir -p "$HOME/.local/bin"
    ln -sfn "$HELIX_DIR/hx" "$HOME/.local/bin/hx"
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

for name in ("HELIX_SETUP_PATH", "HELIX_SETUP_NVM", "HELIX_SETUP_ENV"):
    pattern = rf"\n?# >>> {name} >>>.*?\n# <<< {name} <<<\n?"
    text = re.sub(pattern, "\n", text, flags=re.S)

path.write_text(text)
PY

cat >> "$ZSHRC" <<'EOF'

# >>> HELIX_SETUP_PATH >>>
# PATH managed by helix_setup_linux.sh
typeset -U PATH path
path=(
  "$HOME/.local/bin"
  "$HOME/tools/lua-language-server/bin"
  "/home/linuxbrew/.linuxbrew/bin"
  "$path[@]"
)
# <<< HELIX_SETUP_PATH <<<

# >>> HELIX_SETUP_NVM >>>
# NVM managed by helix_setup_linux.sh
export NVM_DIR="$HOME/.nvm"
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
# <<< HELIX_SETUP_NVM <<<

# >>> HELIX_SETUP_ENV >>>
# Helix managed by helix_setup_linux.sh
if [[ -d "$HOME/tools/helix/runtime" ]]; then
    export HELIX_RUNTIME="$HOME/tools/helix/runtime"
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
# Generated by helix_setup_linux.sh

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
if [[ -z "$HX_BIN" ]]; then
    if [[ -x "$HOME/.local/bin/hx" ]]; then
        HX_BIN="$HOME/.local/bin/hx"
    elif [[ -n "$BREW_PREFIX" && -x "$BREW_PREFIX/bin/hx" ]]; then
        HX_BIN="$BREW_PREFIX/bin/hx"
    fi
fi

if [[ -n "$HX_BIN" && -x "$HX_BIN" ]]; then
    HELIX_INFO="$($HX_BIN --version | head -1)"
else
    HELIX_INFO='restart shell'
fi

printf '  %-24s %s\n' 'helix:' "$HELIX_INFO"
printf '  %-24s %s\n' 'zsh:' "$(zsh --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'default shell:' "$(getent passwd "$USER" | cut -d: -f7 || echo 'necunoscut')"
printf '  %-24s %s\n' 'node:' "$(node --version 2>/dev/null || echo 'restart shell')"
printf '  %-24s %s\n' 'bash-language-server:' "$(bash-language-server --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'python3:' "$($PYTHON_BIN --version)"
printf '  %-24s %s\n' 'ripgrep:' "$(rg --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'ctags:' "$(ctags --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'lua-language-server:' "$([[ -x "$LUA_LS_DIR/bin/lua-language-server" ]] && echo 'instalat' || echo 'lipsa')"
printf '  %-24s %s\n' 'config:' "$HELIX_CONFIG_DIR"
printf '  %-24s %s\n' 'zshrc:' "$ZSHRC"

echo
echo 'Instalare completa.'
echo 'Shell implicit: zsh'
echo 'Ruleaza: exec zsh'
echo 'Apoi verifica Helix cu: hx --health'
echo 'Porneste Helix cu: hx'
