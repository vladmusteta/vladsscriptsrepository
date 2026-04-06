# =============================================================
# Neovim + dependencies installer for Windows (PowerShell)
# Testat pe Windows 10/11
# Ruleaza cu Administrator: .\nvim_setup_windows.ps1
# =============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# Culori pentru output
# ------------------------------------------------------------
function Info  { param($msg) Write-Host "[INFO]  $msg" -ForegroundColor Green }
function Warn  { param($msg) Write-Host "[WARN]  $msg" -ForegroundColor Yellow }
function Err   { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# ------------------------------------------------------------
# Verifica Administrator
# ------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Err "Scriptul trebuie rulat ca Administrator! Click dreapta -> Run as Administrator"
}

# ------------------------------------------------------------
# Execution Policy
# ------------------------------------------------------------
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Info "ExecutionPolicy setat."

# ------------------------------------------------------------
# 1. Instaleaza Scoop (daca nu e instalat)
# ------------------------------------------------------------
if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Info "Instalare Scoop..."
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
} else {
    Info "Scoop deja instalat."
}

# Refresheaza PATH
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

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
    "miniconda3",
    "vcredist2022",
    "7zip",
    "neovim"
)

foreach ($pkg in $scoopPackages) {
    if (scoop list $pkg 2>$null | Select-String $pkg) {
        Info "$pkg deja instalat, skip."
    } else {
        Info "Instalare $pkg..."
        scoop install $pkg
    }
}

# Refresheaza PATH dupa instalari
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

# ------------------------------------------------------------
# 3. Language servers via npm
# ------------------------------------------------------------
Info "Instalare vim-language-server si bash-language-server..."
npm install -g vim-language-server
npm install -g bash-language-server

# ------------------------------------------------------------
# 4. Python packages
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
# 5. lua-language-server
# ------------------------------------------------------------
$luaLsInstallDir = "$env:USERPROFILE\tools"
$luaLsDir        = "$luaLsInstallDir\lua-language-server"
$luaLsSrc        = "$luaLsInstallDir\lua-language-server.zip"
$luaLsLink       = "https://github.com/LuaLS/lua-language-server/releases/download/3.6.11/lua-language-server-3.6.11-win32-x64.zip"

if (-not (Test-Path "$luaLsDir\bin\lua-language-server.exe")) {
    Info "Instalare lua-language-server..."
    if (-not (Test-Path $luaLsInstallDir)) { New-Item -ItemType Directory -Path $luaLsInstallDir | Out-Null }
    Invoke-WebRequest $luaLsLink -OutFile $luaLsSrc
    7z x "$luaLsSrc" -o"$luaLsDir" -y | Out-Null
    Info "lua-language-server instalat in $luaLsDir"
} else {
    Info "lua-language-server deja instalat."
}

# Adauga lua-ls in PATH (Machine level)
$machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
if ($machinePath -notlike "*$luaLsDir\bin*") {
    [System.Environment]::SetEnvironmentVariable("Path", $machinePath + ";$luaLsDir\bin", "Machine")
    Info "lua-language-server adaugat in PATH."
}

# ------------------------------------------------------------
# 6. Curata config nvim vechi si cloneaza config jdhao
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
# 7. Instaleaza pluginurile headless
# ------------------------------------------------------------
Info "Instalare pluginuri nvim (poate dura cateva minute)..."
$nvimExe = (Get-Command nvim -ErrorAction SilentlyContinue)?.Source
if ($nvimExe) {
    & $nvimExe --headless -c "autocmd User LazyInstall quitall" -c "lua require('lazy').install()" 2>$null
    Info "Pluginuri instalate."
} else {
    Warn "nvim nu a fost gasit in PATH. Reporneste terminalul si ruleaza 'nvim' manual."
}

# ------------------------------------------------------------
# 8. Instaleaza Treesitter parsers
# ------------------------------------------------------------
Info "Instalare Treesitter parsers..."
if ($nvimExe) {
    & $nvimExe --headless +"TSInstall css html javascript typescript tsx vue scss svelte lua python bash" +qa 2>$null
}

# ------------------------------------------------------------
# Verificare finala
# ------------------------------------------------------------
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Info "Instalare completa!"
Write-Host "============================================" -ForegroundColor Cyan

$checks = @{
    "nvim"   = (Get-Command nvim   -ErrorAction SilentlyContinue)?.Source
    "node"   = (Get-Command node   -ErrorAction SilentlyContinue)?.Source
    "python" = (Get-Command python  -ErrorAction SilentlyContinue)?.Source
    "rg"     = (Get-Command rg     -ErrorAction SilentlyContinue)?.Source
    "ctags"  = (Get-Command ctags  -ErrorAction SilentlyContinue)?.Source
}

foreach ($tool in $checks.GetEnumerator()) {
    if ($tool.Value) {
        Write-Host "  $($tool.Key): " -NoNewline
        Write-Host "OK - $($tool.Value)" -ForegroundColor Green
    } else {
        Write-Host "  $($tool.Key): " -NoNewline
        Write-Host "LIPSA - reporneste terminalul" -ForegroundColor Yellow
    }
}

Write-Host ""
Warn "Reporneste terminalul/PowerShell dupa instalare!"
Warn "Apoi ruleaza 'nvim' pentru a porni."
Write-Host ""
Info "Nerd Font recomandat pentru iconite: https://www.nerdfonts.com/font-downloads"
Info "Instaleaza 'JetBrainsMono Nerd Font' si seteaza-l in terminalul tau."
