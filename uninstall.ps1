<#
.SYNOPSIS
  ag-math-render - Uninstall script (Windows / PowerShell port of uninstall.sh)
  Removes the math rendering patch from Antigravity.

.USAGE
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
  powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -AppPath "C:\Path\To\Antigravity"
#>

[CmdletBinding()]
param(
    [string]$AppPath
)

$ErrorActionPreference = 'Stop'

function Write-Ok($msg)   { Write-Host $msg -ForegroundColor Green }
function Write-Warn($msg) { Write-Host $msg -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host $msg -ForegroundColor Red }

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

# -- Locate Antigravity ---------------------------------------------------

if (-not $AppPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity IDE'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity'),
        (Join-Path $env:ProgramFiles 'Antigravity IDE'),
        (Join-Path $env:ProgramFiles 'Antigravity'),
        (Join-Path ${env:ProgramFiles(x86)} 'Antigravity')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath (Join-Path $c 'resources\app'))) {
            $AppPath = $c
            break
        }
    }
}

if (-not $AppPath -or -not (Test-Path -LiteralPath $AppPath)) {
    Write-Err "x Antigravity not found."
    Write-Host "  Usage: .\uninstall.ps1 -AppPath 'C:\path\to\Antigravity'"
    exit 1
}

$Resources = Join-Path $AppPath 'resources\app'

# Workbench folder name differs between VS Code versions; try both.
$WorkbenchDir = $null
foreach ($sub in @('out\vs\code\electron-browser\workbench', 'out\vs\code\electron-sandbox\workbench')) {
    $p = Join-Path $Resources $sub
    if ((Test-Path -LiteralPath (Join-Path $p 'workbench.html')) -or
        (Test-Path -LiteralPath (Join-Path $p 'math-patch.js'))) {
        $WorkbenchDir = $p
        break
    }
}
if (-not $WorkbenchDir) {
    Write-Err "x Could not find the workbench folder under: $Resources\out\vs\code\"
    exit 1
}

$HtmlFiles = @(
    (Join-Path $WorkbenchDir 'workbench.html'),
    (Join-Path $WorkbenchDir 'workbench-jetski-agent.html')
)

if (Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue) {
    Write-Warn "! Antigravity appears to be running. Close it first for a clean uninstall."
}

Write-Ok "ag-math-render uninstaller"
Write-Host ""

$Marker = 'ag-math-render'

# -- Step 1: Remove injected tags -----------------------------------------

Write-Host "  [1/3] Removing script tags..."
foreach ($htmlFile in $HtmlFiles) {
    $fname = Split-Path $htmlFile -Leaf
    Write-Host -NoNewline "         $fname... "

    if (-not (Test-Path -LiteralPath $htmlFile)) {
        Write-Warn "not found, skipping"
        continue
    }

    $content = [System.IO.File]::ReadAllText($htmlFile, $Utf8NoBom)
    if ($content.Contains($Marker)) {
        $content = [regex]::Replace($content, "(?m)^.*$Marker.*(\r?\n)?", '')
        [System.IO.File]::WriteAllText($htmlFile, $content, $Utf8NoBom)
        Write-Ok "done"
    } else {
        Write-Warn "not patched"
    }
}

# -- Step 2: Remove math-patch.js -----------------------------------------

Write-Host -NoNewline "  [2/3] Removing math-patch.js... "
$MathPatch = Join-Path $WorkbenchDir 'math-patch.js'
if (Test-Path -LiteralPath $MathPatch) {
    Remove-Item -LiteralPath $MathPatch -Force
    Write-Ok "done"
} else {
    Write-Warn "not found"
}

# -- Step 3: Remove katex directory ---------------------------------------

Write-Host -NoNewline "  [3/3] Removing katex\... "
$KatexDir = Join-Path $WorkbenchDir 'katex'
if (Test-Path -LiteralPath $KatexDir) {
    Remove-Item -LiteralPath $KatexDir -Recurse -Force
    Write-Ok "done"
} else {
    Write-Warn "not found"
}

Write-Host ""
Write-Ok "Uninstall complete!"
Write-Host "  Restart Antigravity to apply changes."
