#!/usr/bin/env bash
# =============================================================
# Full dev environment installer for Linux
# Supports: Ubuntu, Debian, Linux Mint, Arch Linux, Alpine Linux
#
# What this installs:
#   - Base CLI tooling (git, ripgrep, fzf, zoxide, btop, lsd, tmux, ...)
#   - zsh, set as the default login shell
#   - Homebrew (+ lazydocker, fd, tldr, posting via brew)
#   - pipx tui-2048
#   - TUIOS
#   - Starship prompt (pastel-powerline preset)
#   - Python + Lua language servers for Helix
#   - Helix editor
#   - Deploys a fixed ~/.zshrc (see ZSHRC_CONTENT below)
#
# What this deliberately does NOT install:
#   - Neovim, Vim, or any Vim-family plugin/language server
#   - Node/NVM (dropped along with bash-language-server, which needed it)
#
# Run:
#   bash linux_dev_setup.sh
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

[[ -n "${BASH_VERSION:-}" ]] || error 'Run this script with bash.'
[[ "$(id -u)" -ne 0 ]] || error 'Do not run this script as root.'
command -v sudo >/dev/null 2>&1 || error 'sudo is not installed or not available.'

USER_NAME="${SUDO_USER:-${USER:-$(id -un)}}"
USER_HOME="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[[ -n "$USER_HOME" && -d "$USER_HOME" ]] || error "Could not determine HOME for user $USER_NAME."

export HOME="$USER_HOME"
export USER="$USER_NAME"

TOOLS_DIR="$HOME/tools"
PACKAGES_DIR="$HOME/packages"
LOCAL_BIN="$HOME/.local/bin"
HELIX_DIR="$TOOLS_DIR/helix"
HELIX_CONFIG_DIR="$HOME/.config/helix"
PY_VENV="$HOME/.local/share/helix/python-venv"
ZSHRC="$HOME/.zshrc"
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
        error 'Could not detect the Linux distribution.'
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
                error "Unsupported distribution: $DISTRO_ID"
            fi
            ;;
    esac

    info "Detected distribution: $DISTRO_ID (treated as $DISTRO)"
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
    section 'Setting zsh as the default shell'

    local zsh_bin current_shell
    zsh_bin="$(command -v zsh || true)"
    [[ -n "$zsh_bin" && -x "$zsh_bin" ]] || error 'zsh was not found.'

    if ! grep -Fxq "$zsh_bin" /etc/shells; then
        printf '%s\n' "$zsh_bin" | sudo tee -a /etc/shells >/dev/null
    fi

    current_shell="$(getent passwd "$USER_NAME" | cut -d: -f7 || true)"
    if [[ "$current_shell" == "$zsh_bin" ]]; then
        info "zsh is already the default shell for $USER_NAME."
    else
        chsh -s "$zsh_bin" "$USER_NAME"
        info 'zsh has been set as the default shell.'
    fi
}

install_homebrew() {
    section 'Installing Homebrew'

    if [[ ! -x "$BREW_BIN" ]]; then
        run_user_bash 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    fi

    [[ -x "$BREW_BIN" ]] || error 'Homebrew could not be installed.'
    BREW_PREFIX="$(run_as_user "$BREW_BIN" --prefix)"
}

brew_install() {
    local package="$1"

    if run_as_user "$BREW_BIN" list "$package" >/dev/null 2>&1; then
        info "$package is already installed via Homebrew."
    else
        run_as_user "$BREW_BIN" install "$package"
    fi
}

install_python_language_server() {
    section 'Installing the Python language server'

    local python_bin
    python_bin="$(command -v python3 || command -v python || true)"
    [[ -n "$python_bin" ]] || error 'Python was not found.'

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
    section 'Installing lua-language-server'

    local lua_dir="$TOOLS_DIR/lua-language-server"
    local version='3.6.11'
    local arch source url

    if [[ -x "$lua_dir/bin/lua-language-server" ]]; then
        info 'lua-language-server is already installed.'
        return
    fi

    case "$(uname -m)" in
        x86_64) arch='linux-x64' ;;
        aarch64|arm64) arch='linux-arm64' ;;
        *) error "Architecture $(uname -m) is not supported for lua-language-server." ;;
    esac

    source="$PACKAGES_DIR/lua-language-server-${version}.tar.gz"
    url="https://github.com/LuaLS/lua-language-server/releases/download/${version}/lua-language-server-${version}-${arch}.tar.gz"

    run_as_user wget -q "$url" -O "$source"
    rm -rf "$lua_dir"
    run_as_user mkdir -p "$lua_dir"
    run_as_user tar -xzf "$source" -C "$lua_dir"
}

install_helix() {
    section 'Installing Helix'

    local arch version source url

    if [[ -n "$BREW_PREFIX" ]]; then
        brew_install helix
        return
    fi

    case "$(uname -m)" in
        x86_64) arch='x86_64' ;;
        aarch64|arm64) arch='aarch64' ;;
        *) error "Architecture $(uname -m) is not supported for Helix." ;;
    esac

    version="$(curl -fsSL https://api.github.com/repos/helix-editor/helix/releases/latest | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": "([^"]+)".*/\1/')"
    [[ -n "$version" ]] || error 'Could not determine the Helix version.'

    source="$PACKAGES_DIR/helix.tar.xz"
    url="https://github.com/helix-editor/helix/releases/download/${version}/helix-${version#v}-${arch}-linux.tar.xz"

    run_as_user wget -q "$url" -O "$source"
    rm -rf "$HELIX_DIR"
    run_as_user mkdir -p "$HELIX_DIR"
    run_as_user tar -xJf "$source" --strip-components=1 -C "$HELIX_DIR"
    run_as_user ln -sfn "$HELIX_DIR/hx" "$LOCAL_BIN/hx"
}

install_starship() {
    section 'Installing Starship'

    if ! run_as_user bash -c 'command -v starship >/dev/null 2>&1'; then
        run_user_bash 'curl -sS https://starship.rs/install.sh | sh -s -- --yes'
    fi

    run_as_user mkdir -p "$HOME/.config"
    if run_as_user bash -c 'command -v starship >/dev/null 2>&1'; then
        run_as_user starship preset pastel-powerline -o "$HOME/.config/starship.toml" || warn 'Could not generate the Starship preset.'
    fi
}

# The exact ~/.zshrc content the user wants deployed, with two deliberate
# fixes applied on top of the source file: the Neovim PATH entry is dropped
# (no Neovim is ever installed by this script) and the hardcoded
# /home/vladko15 zinit path is made portable via $HOME. The `thefuck --alias`
# eval is guarded so a shell without thefuck installed doesn't fail to start.
read -r -d '' ZSHRC_CONTENT <<'ZSHRC_EOF' || true
# ------------------------------------------------------------
# PATH
# ------------------------------------------------------------
typeset -U PATH path

path=(
  "$HOME/.local/bin"
  "$HOME/tools/nodejs/bin"
  "$HOME/tools/ripgrep"
  "$HOME/tools/ctags/bin"
  "$HOME/tools/lua-language-server/bin"
  "/home/linuxbrew/.linuxbrew/bin/"
  "$path[@]"
)

# ------------------------------------------------------------
# Homebrew
# ------------------------------------------------------------
export BREW="$(brew --prefix)"

if [[ -x "$BREW/bin/brew" ]]; then
  eval "$("$BREW/bin/brew" shellenv)"
fi

# ------------------------------------------------------------
# ZSH History
# ------------------------------------------------------------
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000

setopt INC_APPEND_HISTORY
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS

# Ensure the file exists and is private
touch "$HISTFILE"
chmod 600 "$HISTFILE"

# ------------------------------------------------------------
# Completion
# ------------------------------------------------------------
#autoload -Uz compinit
#compinit

# ------------------------------------------------------------
# Oh-my-posh
# ------------------------------------------------------------
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config "$BREW/opt/oh-my-posh/themes/unicorn.omp.json")"
fi

# ------------------------------------------------------------
# Rust / Cargo
# ------------------------------------------------------------
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# ------------------------------------------------------------
# Colors & less
# ------------------------------------------------------------
[ -x /usr/bin/lesspipe ] && eval "$(SHELL="$SHELL" lesspipe)"

if [ -x /usr/bin/dircolors ]; then
  test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

# ------------------------------------------------------------
# fzf
# ------------------------------------------------------------
# Shell integration (priority: brew > direct install)
FZF_BREW_PREFIX="$(brew --prefix fzf 2>/dev/null)"
if [ -n "$FZF_BREW_PREFIX" ]; then
  [ -f "$FZF_BREW_PREFIX/shell/key-bindings.zsh" ] && \
      source "$FZF_BREW_PREFIX/shell/key-bindings.zsh"
  [ -f "$FZF_BREW_PREFIX/shell/completion.zsh" ] && \
      source "$FZF_BREW_PREFIX/shell/completion.zsh"
elif [ -f ~/.fzf.zsh ]; then
  source <(fzf --zsh)
fi

# Global options
export FZF_DEFAULT_OPTS="
  --height 40%
  --layout=reverse
  --border
  --info=inline
  --bind 'ctrl-/:toggle-preview'
"

# Ctrl+T — files with bat preview
export FZF_CTRL_T_OPTS="
  --preview 'bat -n --color=always {} 2>/dev/null || cat {}'
  --bind 'ctrl-/:change-preview-window(down|hidden|)'
"

# Alt+C — directories with tree preview
export FZF_ALT_C_OPTS="--preview 'tree -C {} | head -100'"

# Ctrl+R — history with preview
export FZF_CTRL_R_OPTS="
  --preview 'echo {}'
  --preview-window=down:3:wrap
  --bind 'ctrl-/:toggle-preview'
"

# Use fd if available
if command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --hidden --follow --exclude .git'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
  _fzf_compgen_path() { fd --hidden --follow --exclude .git . "$1"; }
  _fzf_compgen_dir()  { fd --type d --hidden --follow --exclude .git . "$1"; }
fi

# ------------------------------------------------------------
# Zoxide
# ------------------------------------------------------------
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init zsh)"
  alias cd='z'
fi

# ------------------------------------------------------------
# Yazi
# ------------------------------------------------------------
y() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  command rm -f -- "$tmp"
}

# ------------------------------------------------------------
# Key bindings
# ------------------------------------------------------------

# Home / End keys (various terminal emulators)
bindkey '\e[1~'  beginning-of-line
bindkey '\e[4~'  end-of-line
bindkey '\e[H'   beginning-of-line
bindkey '\e[F'   end-of-line
bindkey '\eOH'   beginning-of-line
bindkey '\eOF'   end-of-line

# Delete / Backspace family
bindkey '^?'      backward-delete-char  # Backspace / DEL
bindkey "^[[3~"   delete-char           # Standard Delete
bindkey "\e[3~"   delete-char           # Alternative Delete
bindkey "^[[3;5~" kill-word             # Ctrl+Delete (some terminals)

# Optional but very handy: word navigation
bindkey "^[[1;5D" backward-word         # Ctrl+Left
bindkey "^[[1;5C" forward-word          # Ctrl+Right
bindkey '^a'      beginning-of-line     # Ctrl+A
bindkey '^e'      end-of-line           # Ctrl+E
bindkey '^k'      kill-line             # Ctrl+K – kill to end of line
bindkey '^u'      backward-kill-line    # Ctrl+U – kill from start to cursor
bindkey '^w'      backward-kill-word    # Ctrl+W – kill previous word
bindkey '^y'      yank                  # Ctrl+Y – yank last killed text


# ------------------------------------------------------------
# Zinit
# ------------------------------------------------------------
ZINIT_HOME="$HOME/.local/share/zinit/zinit.git"

[[ -r "$ZINIT_HOME/zinit.zsh" ]] &&
  source "$ZINIT_HOME/zinit.zsh"

# ------------------------------------------------------------
# ZSH Plugins
# ------------------------------------------------------------
zinit light-mode for \
    zdharma-continuum/zinit-annex-as-monitor \
    zdharma-continuum/zinit-annex-bin-gem-node \
    zdharma-continuum/zinit-annex-patch-dl \
    zdharma-continuum/zinit-annex-rust \
    zdharma-continuum/fast-syntax-highlighting \
    zsh-users/zsh-autosuggestions

# ============================================================
# Aliases
# ============================================================
# ------------------------------------------------------------
# Aliases EZA
# ------------------------------------------------------------
alias ls='ls --color=auto'
alias ll='eza -alghH --icons --group-directories-first --color=always'
alias lx='eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=always --group-directories-first --icons'
alias la='ls -A'
alias l='ls -CF'

#grep
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# fzf full preview
alias fff='fzf --style full \
  --preview "fzf-preview.sh {}" \
  --bind "focus:transform-header:file --brief {}"'

# ------------------------------------------------------------
# Docker
# ------------------------------------------------------------
alias dcup='docker compose up -d'
alias dcdown='docker compose down -v'
alias dcpull='docker compose pull'
alias dcud='dcup && dcdown'
alias dcdu='dcdown && dcup'
alias dcfull='dcdown && dcpull && dcup'

# Spotify API credentials
export SPOTIFY_CLIENT_ID="9d9dcdbb38b14dcc9136a33315b116cc"
export SPOTIFY_CLIENT_SECRET="ab5890972fc548eba61cbe08cbb7f552"

# ------------------------------------------------------------
# Thefuck
# ------------------------------------------------------------
command -v thefuck &>/dev/null && eval "$(thefuck --alias)"

# ------------------------------------------------------------
# DYNMOTD local user
# ------------------------------------------------------------
alias motd='sudo -n /usr/local/bin/dynmotd'
ZSHRC_EOF

deploy_zshrc() {
    section 'Deploying ~/.zshrc'

    if [[ -f "$ZSHRC" ]]; then
        local backup
        backup="$ZSHRC.backup.$(date +%Y%m%d-%H%M%S)"
        run_as_user cp "$ZSHRC" "$backup"
        info "Backup created: $backup"
    fi

    printf '%s\n' "$ZSHRC_CONTENT" | run_as_user tee "$ZSHRC" >/dev/null
}

configure_helix() {
    section 'Configuring Helix'

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
        info 'config.toml already exists; leaving it untouched.'
    fi

    run_as_user tee "$HELIX_CONFIG_DIR/languages.toml" >/dev/null <<EOF
# Generated by linux_dev_setup.sh

[[language]]
name = "python"
language-servers = ["pylsp"]

[[language]]
name = "lua"
language-servers = ["lua-language-server"]

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

section 'Updating package lists and installing system packages'
pkg_update

case "$DISTRO" in
    debian)
        pkg_install \
            git curl wget unzip tar gzip xz-utils \
            build-essential pkg-config \
            python3 python3-pip python3-venv \
            ripgrep fd-find universal-ctags \
            tree bat fzf jq shellcheck zsh \
            dnsutils btop lsd duf zoxide pipx tmux
        ;;
    arch)
        pkg_install \
            git curl wget unzip tar gzip xz \
            base-devel pkgconf \
            python python-pip python-pipx \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh \
            bind btop lsd duf zoxide tmux
        ;;
    alpine)
        pkg_install \
            git curl wget unzip tar gzip xz \
            build-base pkgconf \
            python3 py3-pip py3-virtualenv \
            ripgrep fd ctags \
            tree bat fzf jq shellcheck zsh \
            bind-tools btop lsd duf zoxide tmux
        ;;
esac

if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sfn "$(command -v fdfind)" "$LOCAL_BIN/fd"
fi

configure_zsh_default
install_homebrew

section 'Installing Homebrew packages'
brew_install lazydocker
brew_install fd
brew_install tldr
brew_install posting

section 'Installing tui-2048 via pipx'
if command -v pipx >/dev/null 2>&1; then
    run_as_user pipx ensurepath >/dev/null 2>&1 || true
    if ! run_as_user pipx list 2>/dev/null | grep -q 'package tui-2048'; then
        run_as_user pipx install tui-2048 || warn 'tui-2048 could not be installed.'
    fi
else
    warn 'pipx is not available; tui-2048 was not installed.'
fi

section 'Installing TUIOS'
if ! run_as_user bash -c 'command -v tuios >/dev/null 2>&1'; then
    run_user_bash 'curl -fsSL https://raw.githubusercontent.com/Gaurav-Gosain/tuios/main/install.sh | bash' || warn 'TUIOS could not be installed.'
else
    info 'TUIOS is already installed.'
fi

install_starship
install_python_language_server
install_lua_language_server
install_helix
deploy_zshrc
configure_helix

section 'Final check'

HX_BIN="$LOCAL_BIN/hx"
HELIX_INFO='missing'
[[ -x "$HX_BIN" ]] && HELIX_INFO="$($HX_BIN --version | head -1)"

printf '  %-24s %s\n' 'helix:' "$HELIX_INFO"
printf '  %-24s %s\n' 'zsh:' "$(zsh --version 2>/dev/null || echo 'missing')"
printf '  %-24s %s\n' 'default shell:' "$(getent passwd "$USER_NAME" | cut -d: -f7 || echo 'unknown')"
printf '  %-24s %s\n' 'python3:' "$(python3 --version 2>/dev/null || echo 'missing')"
printf '  %-24s %s\n' 'ripgrep:' "$(rg --version 2>/dev/null | head -1 || echo 'missing')"
printf '  %-24s %s\n' 'ctags:' "$(ctags --version 2>/dev/null | head -1 || echo 'missing')"
printf '  %-24s %s\n' 'lua-language-server:' "$( [[ -x "$TOOLS_DIR/lua-language-server/bin/lua-language-server" ]] && echo 'installed' || echo 'missing' )"
printf '  %-24s %s\n' 'starship:' "$(run_as_user bash -c 'starship --version 2>/dev/null | head -1' || echo 'missing')"
printf '  %-24s %s\n' 'brew:' "$(run_as_user "$BREW_BIN" --version 2>/dev/null | head -1 || echo 'missing')"
printf '  %-24s %s\n' 'config:' "$HELIX_CONFIG_DIR"
printf '  %-24s %s\n' 'zshrc:' "$ZSHRC"

echo
echo 'Setup complete.'
echo 'Helix is the only editor configured. No Neovim/Vim components were installed.'
echo 'No Node/NVM was installed either.'
echo 'Starting a new zsh session...'

exec zsh -l
