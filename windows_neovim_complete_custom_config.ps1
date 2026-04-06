# =============================================================
# Neovim + dependencies installer for Windows (PowerShell)
# Compatibil cu PowerShell 5.x si 7.x
# Testat pe Windows 10/11
# Ruleaza ca user normal (NU ca Administrator):
# irm "https://raw.githubusercontent.com/vladmusteta/vladsscriptsrepository/refs/heads/main/windows_neovim_complete_custom_config.ps1" | iex
# =============================================================

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Culori pentru output
# ------------------------------------------------------------
function Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Warn  { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err   { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

function Get-CommandPath {
    param($name)
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source } else { return $null }
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

# ------------------------------------------------------------
# Verifica ca NU rulezi ca Administrator (Scoop nu vrea admin)
# ------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if ($isAdmin) {
    Err "Nu rula ca Administrator! Deschide PowerShell normal (fara Run as Administrator) si incearca din nou."
}

# ------------------------------------------------------------
# Execution Policy
# ------------------------------------------------------------
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Info "ExecutionPolicy setat."

# ------------------------------------------------------------
# 1. Instaleaza Scoop (daca nu e instalat)
# ------------------------------------------------------------
if (-not (Get-CommandPath "scoop")) {
    Info "Instalare Scoop..."
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
    Refresh-Path
} else {
    Info "Scoop deja instalat."
}

Refresh-Path

# ------------------------------------------------------------
# 2. Dependente via Scoop
# ------------------------------------------------------------
Info "Adaugare bucket extras si versions..."
scoop bucket add extras  2>$null
scoop bucket add versions 2>$null

$scoopPackages = @(
    "git",
    "nodejs",
    "ripgrep",
    "universal-ctags",
    "vcredist2022",
    "7zip",
    "neovim"
)

foreach ($pkg in $scoopPackages) {
    $installed = scoop list $pkg 2>$null | Select-String $pkg
    if ($installed) {
        Info "$pkg deja instalat, skip."
    } else {
        Info "Instalare $pkg..."
        scoop install $pkg
    }
}

Refresh-Path

# ------------------------------------------------------------
# 3. Python 3.11 via Scoop
# (3.12/3.13/3.15 sunt prea noi - ujson si alte pachete nu au
#  wheels precompilate si necesita Visual C++ Build Tools)
# ------------------------------------------------------------
Info "Instalare Python 3.11..."
$installedPy = scoop list python311 2>$null | Select-String "python311"
if (-not $installedPy) {
    scoop install python311
} else {
    Info "Python 3.11 deja instalat, skip."
}

# Seteaza python311 ca default
Info "Setare Python 3.11 ca default..."
scoop reset python311
Refresh-Path

$pyVersion = python --version 2>$null
Info "Python activ: $pyVersion"

if ($pyVersion -notlike "*3.11*") {
    Warn "Python 3.11 nu e activ in PATH curent. Continuam oricum..."
}

# ------------------------------------------------------------
# 4. Language servers via npm
# ------------------------------------------------------------
Info "Instalare vim-language-server si bash-language-server..."
npm install -g vim-language-server
npm install -g bash-language-server

# ------------------------------------------------------------
# 5. Python packages
# ------------------------------------------------------------
Info "Instalare pachete Python pentru nvim..."
$pyPackages = @(
    "pynvim",
    "python-lsp-server[all]",
    "pylsp-mypy",
    "python-lsp-isort",
    "python-lsp-black",
    "vim-vint"
)
foreach ($pkg in $pyPackages) {
    Info "pip install $pkg..."
    pip install -U $pkg
}

# ------------------------------------------------------------
# 6. lua-language-server
# ------------------------------------------------------------
$luaLsInstallDir = "$env:USERPROFILE\tools"
$luaLsDir        = "$luaLsInstallDir\lua-language-server"
$luaLsSrc        = "$luaLsInstallDir\lua-language-server.zip"
$luaLsLink       = "https://github.com/LuaLS/lua-language-server/releases/download/3.6.11/lua-language-server-3.6.11-win32-x64.zip"

if (-not (Test-Path "$luaLsDir\bin\lua-language-server.exe")) {
    Info "Instalare lua-language-server..."
    if (-not (Test-Path $luaLsInstallDir)) {
        New-Item -ItemType Directory -Path $luaLsInstallDir | Out-Null
    }
    Invoke-WebRequest $luaLsLink -OutFile $luaLsSrc
    7z x "$luaLsSrc" -o"$luaLsDir" -y | Out-Null
    Info "lua-language-server instalat in $luaLsDir"
} else {
    Info "lua-language-server deja instalat."
}

# Adauga lua-ls in PATH (User level - nu necesita admin)
$userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$luaLsDir\bin*") {
    [System.Environment]::SetEnvironmentVariable("Path", $userPath + ";$luaLsDir\bin", "User")
    Info "lua-language-server adaugat in PATH."
}

Refresh-Path

# ------------------------------------------------------------
# 7. Curata config nvim vechi si cloneaza config jdhao
# ------------------------------------------------------------
$nvimConfigDir = "$env:LOCALAPPDATA\nvim"

if (Test-Path $nvimConfigDir) {
    Info "Backup config nvim vechi..."
    $backup = "$nvimConfigDir.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Move-Item $nvimConfigDir $backup
    Info "Backup salvat in $backup"
}

Info "Clonare config nvim jdhao..."
git clone --depth=1 https://github.com/jdhao/nvim-config.git $nvimConfigDir

# ------------------------------------------------------------
# 8. Instaleaza pluginurile headless
# ------------------------------------------------------------
Info "Instalare pluginuri nvim (poate dura cateva minute)..."
$nvimExe = Get-CommandPath "nvim"
if ($nvimExe) {
    & $nvimExe --headless -c "autocmd User LazyInstall quitall" -c "lua require('lazy').install()" 2>$null
    Info "Pluginuri instalate."
} else {
    Warn "nvim nu a fost gasit in PATH. Reporneste terminalul si ruleaza 'nvim' manual."
}

# ------------------------------------------------------------
# 9. Instaleaza Treesitter parsers
# ------------------------------------------------------------
Info "Instalare Treesitter parsers..."
if ($nvimExe) {
    & $nvimExe --headless +"TSInstall css html javascript typescript tsx vue scss svelte lua python bash" +qa 2>$null
    Info "Parsers instalati."
}

# ------------------------------------------------------------
# Verificare finala
# ------------------------------------------------------------
Refresh-Path

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Info "Instalare completa!"
Write-Host "============================================" -ForegroundColor Cyan

$toolsToCheck = @("nvim", "node", "python", "rg", "ctags")
foreach ($tool in $toolsToCheck) {
    $path = Get-CommandPath $tool
    if ($path) {
        Write-Host "  $tool`: " -NoNewline
        Write-Host "OK - $path" -ForegroundColor Green
    } else {
        Write-Host "  $tool`: " -NoNewline
        Write-Host "LIPSA - reporneste terminalul" -ForegroundColor Yellow
    }
}

Write-Host ""
Warn "Reporneste terminalul/PowerShell dupa instalare!"
Warn "Apoi ruleaza 'nvim' pentru a porni."
Write-Host ""
Info "Nerd Font recomandat: https://www.nerdfonts.com/font-downloads"
Info "Instaleaza 'JetBrainsMono Nerd Font' si seteaza-l in terminalul tau."
