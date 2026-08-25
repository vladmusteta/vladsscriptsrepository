#!/usr/bin/env bash
# =============================================================
# Helix + development tools installer for Linux
# Supports: Ubuntu, Debian, Linux Mint, Arch Linux, Alpine Linux
#
# IMPORTANT:
#   This script installs Helix only as editor.
#   It contains no Neovim, no Vim and no Vim-related language server.
#
# Run:
#   bash helix_setup_linux_no_vim.sh
# =============================================================
set -Eeuo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { printf '%b[INFO]%b  %s\n' "$GREEN" "$NC" "$*"; }
warn() { printf '%b[WARN]%b  %s\n' "$YELLOW" "$NC" "$*"; }
error() { printf '%b[ERROR]%b %s\n' "$RED" "$NC" "$*" >&2; exit 1; }
section() { printf '\n%b==> %s%b\n' "$CYAN" "$*" "$NC"; }

[[ -n "${BASH_VERSION:-}" ]] || error 'Ruleaza acest script cu bash.'
[[ "$(id -u)" -ne 0 ]] || error 'Nu rula scriptul ca root.'
command -v sudo >/dev/null 2>&1 || error 'sudo nu este instalat sau nu este disponibil.'

USER_NAME="${SUDO_USER:-${USER:-$(id -un)}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || error "Nu pot determina HOME pentru utilizatorul $USER_NAME."

export HOME="$USER_HOME"
export USER="$USER_NAME"

TOOLS_DIR="$HOME/tools"
PACKAGES_DIR="$HOME/packages"
LOCAL_BIN="$HOME/.local/bin"
HELIX_DIR="$TOOLS_DIR/helix"
HELIX_CONFIG_DIR="$HOME/.config/helix"
PY_VENV="$HOME/.local/share/helix/python-venv"
ZSHRC="$HOME/.zshrc"
NVM_DIR="$HOME/.nvm"
BREW_BIN='/home/linuxbrew/.linuxbrew/bin/brew'
BREW_PREFIX=''
DISTRO=''
DISTRO_ID=''
DISTRO_LIKE=''

mkdir -p "$TOOLS_DIR" "$PACKAGES_DIR" "$LOCAL_BIN" "$HELIX_CONFIG_DIR"

run_as_user() {
    if [[ "$(id -un)" == "$USER_NAME" ]]; then
        "$@"
    else
        sudo -u "$USER_NAME" -H env HOME="$HOME" USER="$USER_NAME" "$@"
    fi
}

run_user_bash() {
    if [[ "$(id -un)" == "$USER_NAME" ]]; then
        bash -c "$1"
    else
        sudo -u "$USER_NAME" -H env HOME="$HOME" USER="$USER_NAME" bash -c "$1"
    fi
}

# NVM can reference unset internal variables when Bash nounset is active.
run_nvm_command() {
    local command_string="$1"
    set +u
    run_user_bash "export NVM_DIR='$NVM_DIR'; source '$NVM_DIR/nvm.sh'; $command_string"
    local status=$?
    set -u
    return "$status"
}

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
        ubuntu|debian|linuxmint|pop|elementary|zorin) DISTRO='debian' ;;
        arch|manjaro|endeavouros|garuda) DISTRO='arch' ;;
        alpine) DISTRO='alpine' ;;
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
        arch) sudo pacman -Sy --noconfirm ;;
        alpine) sudo apk update -q ;;
    esac
}

pkg_install() {
    case "$DISTRO" in
        debian) sudo apt-get install -y "$@" ;;
        arch) sudo pacman -S --noconfirm --needed "$@" ;;
        alpine) sudo apk add --no-cache "$@" ;;
    esac
}

configure_zsh_default() {
    section 'Configurare zsh ca shell implicit'

    local zsh_bin current_shell
    zsh_bin="$(command -v zsh || true)"
    [[ -n "$zsh_bin" && -x "$zsh_bin" ]] || error 'zsh nu a fost gasit.'

    if ! grep -Fxq "$zsh_bin" /etc/shells; then
        printf '%s\n' "$zsh_bin" | sudo tee -a /etc/shells >/dev/null
    fi

    current_shell="$(getent passwd "$USER_NAME" | cut -d: -f7 || true)"
    if [[ "$current_shell" == "$zsh_bin" ]]; then
        info "zsh este deja shell-ul implicit pentru $USER_NAME."
    else
        chsh -s "$zsh_bin" "$USER_NAME"
        info 'zsh a fost setat ca shell implicit.'
    fi
}

install_homebrew() {
    section 'Instalare Homebrew'

    if [[ ! -x "$BREW_BIN" ]]; then
        run_user_bash 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    fi

    [[ -x "$BREW_BIN" ]] || error 'Homebrew nu a putut fi instalat.'
    BREW_PREFIX="$(run_as_user "$BREW_BIN" --prefix)"
}

brew_install() {
    local package="$1"

    if run_as_user "$BREW_BIN" list "$package" >/dev/null 2>&1; then
        info "$package este deja instalat prin Homebrew."
    else
        run_as_user "$BREW_BIN" install "$package"
    fi
}

install_bash_language_server() {
    section 'Instalare bash-language-server pentru Helix'

    if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
        info 'Instalare NVM 0.40.7...'
        run_user_bash 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash'
    fi

    [[ -s "$NVM_DIR/nvm.sh" ]] || error 'NVM nu a putut fi instalat.'

    run_nvm_command 'nvm install --lts'
    run_nvm_command "nvm alias default 'lts/*'"
    run_nvm_command 'nvm use --lts >/dev/null'
    run_nvm_command 'npm install --global bash-language-server'
}

install_python_language_server() {
    section 'Instalare language server Python'

    local python_bin
    python_bin="$(command -v python3 || command -v python || true)"
    [[ -n "$python_bin" ]] || error 'Python nu a fost gasit.'

    if [[ ! -x "$PY_VENV/bin/python" ]]; then
        run_as_user "$python_bin" -m venv "$PY_VENV"
    fi

    run_as_user "$PY_VENV/bin/python" -m pip install --upgrade pip
    run_as_user "$PY_VENV/bin/python" -m pip install \
        'python-lsp-server[all]' \
        pylsp-mypy \
        python-lsp-isort \
        python-lsp-black
}

install_lua_language_server() {
    section 'Instalare lua-language-server'

    local lua_dir="$TOOLS_DIR/lua-language-server"
    local version='3.6.11'
    local arch source url

    if [[ -x "$lua_dir/bin/lua-language-server" ]]; then
        info 'lua-language-server este deja instalat.'
        return
    fi

    case "$(uname -m)" in
        x86_64) arch='linux-x64' ;;
        aarch64|arm64) arch='linux-arm64' ;;
        *) error "Arhitectura $(uname -m) nu este suportata pentru lua-language-server." ;;
    esac

    source="$PACKAGES_DIR/lua-language-server-${version}.tar.gz"
    url="https://github.com/LuaLS/lua-language-server/releases/download/${version}/lua-language-server-${version}-${arch}.tar.gz"

    run_as_user wget -q "$url" -O "$source"
    rm -rf "$lua_dir"
    run_as_user mkdir -p "$lua_dir"
    run_as_user tar -xzf "$source" -C "$lua_dir"
}

install_helix() {
    section 'Instalare Helix'

    local arch version source url

    if [[ -n "$BREW_PREFIX" ]]; then
        brew_install helix
        return
    fi

    case "$(uname -m)" in
        x86_64) arch='x86_64' ;;
        aarch64|arm64) arch='aarch64' ;;
        *) error "Arhitectura $(uname -m) nu este suportata pentru Helix." ;;
    esac

    version="$(curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')"
    [[ -n "$version" ]] || error 'Nu pot determina versiunea Helix.'

    source="$PACKAGES_DIR/helix.tar.xz"
    url="https://github.com/helix-editor/helix/releases/download/${version}/helix-${version#v}-${arch}-linux.tar.xz"

    run_as_user wget -q "$url" -O "$source"
    rm -rf "$HELIX_DIR"
    run_as_user mkdir -p "$HELIX_DIR"
    run_as_user tar -xJf "$source" --strip-components=1 -C "$HELIX_DIR"
    run_as_user ln -sfn "$HELIX_DIR/hx" "$LOCAL_BIN/hx"
}

install_starship() {
    section 'Instalare Starship'

    if ! run_as_user bash -c 'command -v starship >/dev/null 2>&1'; then
        run_user_bash 'curl -sS https://starship.rs/install.sh | sh -s -- --yes'
    fi

    run_as_user mkdir -p "$HOME/.config"
    if run_as_user bash -c 'command -v starship >/dev/null 2>&1'; then
        run_as_user starship preset pastel-powerline -o "$HOME/.config/starship.toml" || warn 'Presetul Starship nu a putut fi generat.'
    fi
}

configure_zshrc() {
    section 'Configurare ~/.zshrc'

    run_as_user touch "$ZSHRC"
    local backup
    backup="$ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
    run_as_user cp "$ZSHRC" "$backup"
    info "Backup creat: $backup"

    run_as_user python3 - "$ZSHRC" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()

for name in (
    "HELIX_SETUP_PATH",
    "HELIX_SETUP_BREW",
    "HELIX_SETUP_NVM",
    "HELIX_SETUP_STARSHIP",
    "HELIX_SETUP_ENV",
):
    pattern = rf"\n?# >>> {name} >>>.*?\n# <<< {name} <<<\n?"
    text = re.sub(pattern, "\n", text, flags=re.S)

path.write_text(text)
PY

    run_as_user tee -a "$ZSHRC" >/dev/null <<EOF

# >>> HELIX_SETUP_PATH >>>
# Managed by helix_setup_linux_no_vim.sh
typeset -U PATH path
path=(
  "$LOCAL_BIN"
  "$TOOLS_DIR/lua-language-server/bin"
  "$BREW_PREFIX/bin"
  "$BREW_PREFIX/sbin"
  "\$path[@]"
)
# <<< HELIX_SETUP_PATH <<<

# >>> HELIX_SETUP_BREW >>>
# Managed by helix_setup_linux_no_vim.sh
if [[ -x "$BREW_BIN" ]]; then
    eval "\$("$BREW_BIN" shellenv)"
fi
# <<< HELIX_SETUP_BREW <<<

# >>> HELIX_SETUP_NVM >>>
# Managed by helix_setup_linux_no_vim.sh
export NVM_DIR="\$HOME/.nvm"
if [[ -s "\$NVM_DIR/nvm.sh" ]]; then
    set +u
    source "\$NVM_DIR/nvm.sh"
    set -u
fi
# <<< HELIX_SETUP_NVM <<<

# >>> HELIX_SETUP_STARSHIP >>>
# Managed by helix_setup_linux_no_vim.sh
if command -v starship >/dev/null 2>&1; then
    eval "\$(starship init zsh)"
fi
# <<< HELIX_SETUP_STARSHIP <<<

# >>> HELIX_SETUP_ENV >>>
# Managed by helix_setup_linux_no_vim.sh
if [[ -d "\$HOME/tools/helix/runtime" ]]; then
    export HELIX_RUNTIME="\$HOME/tools/helix/runtime"
else
    unset HELIX_RUNTIME
fi
# <<< HELIX_SETUP_ENV <<<
EOF
}

configure_helix() {
    section 'Configurare Helix'

    if [[ ! -f "$HELIX_CONFIG_DIR/config.toml" ]]; then
        run_as_user tee "$HELIX_CONFIG_DIR/config.toml" >/dev/null <<'EOF'
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

    run_as_user tee "$HELIX_CONFIG_DIR/languages.toml" >/dev/null <<EOF
# Generated by helix_setup_linux_no_vim.sh

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
command = "$TOOLS_DIR/lua-language-server/bin/lua-language-server"
args = ["-E", "$TOOLS_DIR/lua-language-server/main.lua"]
EOF
}

# ------------------------------------------------------------
# Main
# ------------------------------------------------------------
detect_distro

section 'Update si instalare pachete sistem'
pkg_update

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
            python python-pip python-pipx \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh \
            bind btop lsd duf tmux
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

configure_zsh_default
install_homebrew

section 'Instalare pachete Homebrew'
brew_install lazydocker
brew_install fd
brew_install tldr
brew_install posting

section 'Instalare tui-2048 prin pipx'
if command -v pipx >/dev/null 2>&1; then
    run_as_user pipx ensurepath >/dev/null 2>&1 || true
    if ! run_as_user pipx list 2>/dev/null | grep -q 'package tui-2048'; then
        run_as_user pipx install tui-2048 || warn 'tui-2048 nu a putut fi instalat.'
    fi
else
    warn 'pipx nu este disponibil; tui-2048 nu a fost instalat.'
fi

section 'Instalare TUIOS'
if ! run_as_user bash -c 'command -v tuios >/dev/null 2>&1'; then
    run_user_bash 'curl -fsSL https://raw.githubusercontent.com/Gaurav-Gosain/tuios/main/install.sh | bash' || warn 'TUIOS nu a putut fi instalat.'
else
    info 'TUIOS este deja instalat.'
fi

install_starship
install_bash_language_server
install_python_language_server
install_lua_language_server
install_helix
configure_zshrc
configure_helix

section 'Verificare finala'

HX_BIN="$LOCAL_BIN/hx"
HELIX_INFO='lipsa'
[[ -x "$HX_BIN" ]] && HELIX_INFO="$($HX_BIN --version | head -1)"

NODE_INFO='lipsa'
BASH_LS_INFO='lipsa'
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
    NODE_INFO="$(run_nvm_command 'node --version' 2>/dev/null || echo 'lipsa')"
    BASH_LS_INFO="$(run_nvm_command 'bash-language-server --version' 2>/dev/null || echo 'lipsa')"
fi

printf '  %-24s %s\n' 'helix:' "$HELIX_INFO"
printf '  %-24s %s\n' 'zsh:' "$(zsh --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'default shell:' "$(getent passwd "$USER_NAME" | cut -d: -f7 || echo 'necunoscut')"
printf '  %-24s %s\n' 'node:' "$NODE_INFO"
printf '  %-24s %s\n' 'bash-language-server:' "$BASH_LS_INFO"
printf '  %-24s %s\n' 'python3:' "$(python3 --version 2>/dev/null || echo 'lipsa')"
printf '  %-24s %s\n' 'ripgrep:' "$(rg --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'ctags:' "$(ctags --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'lua-language-server:' "$( [[ -x "$TOOLS_DIR/lua-language-server/bin/lua-language-server" ]] && echo 'instalat' || echo 'lipsa' )"
printf '  %-24s %s\n' 'starship:' "$(run_as_user bash -c 'starship --version 2>/dev/null | head -1' || echo 'lipsa')"
printf '  %-24s %s\n' 'brew:' "$(run_as_user "$BREW_BIN" --version 2>/dev/null | head -1 || echo 'lipsa')"
printf '  %-24s %s\n' 'config:' "$HELIX_CONFIG_DIR"
printf '  %-24s %s\n' 'zshrc:' "$ZSHRC"

echo
echo 'Instalare completa.'
echo 'Helix este singurul editor configurat.'
echo 'Nu au fost instalate componente pentru alte editoare.'
echo 'Pornesc o sesiune zsh noua...'

exec zsh -l
