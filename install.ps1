<#
.SYNOPSIS
  ag-math-render - Install script (Windows / PowerShell port of install.sh)
  Patches Antigravity AI IDE to render LaTeX math in chat.

.USAGE
  powershell -ExecutionPolicy Bypass -File .\install.ps1
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -AppPath "C:\Path\To\Antigravity"

  -AppPath is the Antigravity install folder (the one containing Antigravity.exe
  and a "resources" folder).

.NOTES
  1. Copies math-patch.js + KaTeX into the Antigravity install
  2. Wraps katex.min.js with AMD suspension (so it sets window.katex)
  3. Injects static <link> and <script> tags into the HTML files
  4. Removes checksums from product.json
  Idempotent: safe to run multiple times. Close Antigravity first.
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
    Write-Host "  Usage: .\install.ps1 -AppPath 'C:\path\to\Antigravity'"
    exit 1
}

$Resources   = Join-Path $AppPath 'resources\app'
$ProductJson = Join-Path $Resources 'product.json'
$PayloadDir  = Join-Path $PSScriptRoot 'payload'

# Workbench folder name differs between VS Code versions; try both.
$WorkbenchDir = $null
foreach ($sub in @('out\vs\code\electron-browser\workbench', 'out\vs\code\electron-sandbox\workbench')) {
    $p = Join-Path $Resources $sub
    if (Test-Path -LiteralPath (Join-Path $p 'workbench.html')) {
        $WorkbenchDir = $p
        break
    }
}
if (-not $WorkbenchDir) {
    Write-Err "x Could not find workbench.html under: $Resources\out\vs\code\"
    exit 1
}

$HtmlFiles = @(
    (Join-Path $WorkbenchDir 'workbench.html'),
    (Join-Path $WorkbenchDir 'workbench-jetski-agent.html')
)

# Checksum keys in product.json use forward slashes
$ChecksumKeys = @(
    'vs/code/electron-browser/workbench/workbench.html',
    'vs/code/electron-browser/workbench/workbench-jetski-agent.html',
    'vs/code/electron-sandbox/workbench/workbench.html',
    'vs/code/electron-sandbox/workbench/workbench-jetski-agent.html'
)

# -- Preflight ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $PayloadDir)) {
    Write-Err "x payload\ directory not found. Run from the project root."
    exit 1
}

if (Get-Process -Name 'Antigravity*' -ErrorAction SilentlyContinue) {
    Write-Warn "! Antigravity appears to be running. Close it first for a clean patch."
}

Write-Ok "ag-math-render installer"
Write-Host "  Antigravity: $AppPath"
Write-Host ""

# -- Step 1: Copy payload -------------------------------------------------

$DstJs    = Join-Path $WorkbenchDir 'math-patch.js'
$DstKatex = Join-Path $WorkbenchDir 'katex'

Write-Host -NoNewline "  [1/4] Copying payload... "
Copy-Item -LiteralPath (Join-Path $PayloadDir 'math-patch.js') -Destination $DstJs -Force
if (Test-Path -LiteralPath $DstKatex) { Remove-Item -LiteralPath $DstKatex -Recurse -Force }
Copy-Item -LiteralPath (Join-Path $PayloadDir 'katex') -Destination $DstKatex -Recurse -Force
Write-Ok "done"

# -- Step 2: Wrap KaTeX with AMD suspension -------------------------------

Write-Host -NoNewline "  [2/4] Wrapping KaTeX for AMD compatibility... "
$KatexJs   = Join-Path $DstKatex 'katex.min.js'
$KatexOrig = Join-Path $DstKatex 'katex.min.original.js'

if (-not (Test-Path -LiteralPath $KatexOrig)) {
    Copy-Item -LiteralPath $KatexJs -Destination $KatexOrig
}

$orig = [System.IO.File]::ReadAllText($KatexOrig, $Utf8NoBom)
$wrapped = @(
    '/* ag-math-render: AMD suspension wrapper */',
    '(function(){var _d=window.define;if(_d&&_d.amd){try{window.define=undefined}catch(e){}}',
    $orig,
    ';if(typeof _d!=="undefined"){try{window.define=_d}catch(e){}}})();'
) -join "`n"
[System.IO.File]::WriteAllText($KatexJs, $wrapped, $Utf8NoBom)
Write-Ok "done"

# -- Step 3: Inject tags into HTML files ----------------------------------

$Marker = 'ag-math-render'
$InjectBlock = "<!-- $Marker --><link rel=`"stylesheet`" href=`"./katex/katex.min.css`"><script src=`"./katex/katex.min.js`"></script><script src=`"./math-patch.js`" type=`"module`"></script>"

Write-Host "  [3/4] Patching HTML files..."

foreach ($htmlFile in $HtmlFiles) {
    $fname = Split-Path $htmlFile -Leaf
    Write-Host -NoNewline "         $fname... "

    if (-not (Test-Path -LiteralPath $htmlFile)) {
        Write-Warn "not found, skipping"
        continue
    }

    $content = [System.IO.File]::ReadAllText($htmlFile, $Utf8NoBom)

    # Remove any previous injection (idempotent update)
    if ($content.Contains($Marker)) {
        $content = [regex]::Replace($content, "(?m)^.*$Marker.*(\r?\n)?", '')
    }

    $idx = $content.LastIndexOf('</html>')
    if ($idx -ge 0) {
        $content = $content.Insert($idx, $InjectBlock + "`n")
        [System.IO.File]::WriteAllText($htmlFile, $content, $Utf8NoBom)
        Write-Ok "done"
    } else {
        Write-Err "FAILED - </html> not found"
    }
}

# -- Step 4: Clear checksums ----------------------------------------------

Write-Host -NoNewline "  [4/4] Clearing checksums... "

if (Test-Path -LiteralPath $ProductJson) {
    $raw  = [System.IO.File]::ReadAllText($ProductJson, $Utf8NoBom)
    $data = $raw | ConvertFrom-Json
    $removed = 0

    if ($data.PSObject.Properties.Name -contains 'checksums' -and $data.checksums) {
        foreach ($key in $ChecksumKeys) {
            if ($data.checksums.PSObject.Properties.Name -contains $key) {
                $data.checksums.PSObject.Properties.Remove($key)
                $removed++
            }
        }
    }

    if ($removed -gt 0) {
        $bak = "$ProductJson.ag-math-render.bak"
        if (-not (Test-Path -LiteralPath $bak)) {
            Copy-Item -LiteralPath $ProductJson -Destination $bak
        }
        $json = $data | ConvertTo-Json -Depth 100
        [System.IO.File]::WriteAllText($ProductJson, $json, $Utf8NoBom)
        Write-Host "removed $removed checksum(s)"
    } else {
        Write-Host "already clean"
    }
} else {
    Write-Warn "product.json not found, skipping"
}

# -- Done -----------------------------------------------------------------

Write-Host ""
Write-Ok "Installation complete!"
Write-Host "  Restart Antigravity to see math rendering in chat."
Write-Host "  Works in both Editor sidebar and Agent Manager window."
Write-Host ""
Write-Host "  To uninstall: .\uninstall.ps1 (port uninstall.sh the same way)"
