# =============================================================================
# ComfyUI Master Manager v0.1
# Interface: Vertical English | Support: CUDA (dynamic from PyTorch site)
# Features: Smart Dep-Guard, Clean Versioning, Auto-Cache, Torch Protection
# Modules: Init, UI, Env Info, Torch Mgmt, ComfyUI Mgmt, Repair
# =============================================================================

#region MODULE 1 - Initialization

$ScriptVersion      = "0.1"
$ScriptRoot         = Split-Path -Parent $MyInvocation.MyCommand.Definition
$CacheDir           = Join-Path $ScriptRoot ".cache"
if (!(Test-Path $CacheDir)) { New-Item $CacheDir -ItemType Directory | Out-Null }

# --- File Paths ---
$LogFile            = Join-Path $CacheDir "history.log"
$rnFile             = Join-Path $CacheDir "release_notes.log"
$EnvLogFile         = Join-Path $CacheDir "env_state.log"
$SmartFixerPath     = Join-Path $CacheDir "smart_fixer.py"
$ConstFile          = Join-Path $CacheDir "const.txt"

# --- Tool Paths ---
$VenvPython         = Join-Path $ScriptRoot "venv\Scripts\python.exe"
$ComfyDir           = Join-Path $ScriptRoot "ComfyUI"
$SitePackages       = Join-Path $ScriptRoot "venv\Lib\site-packages"

# --- Protected packages: never modified by Module 5 or Module 6 ---
# Only the actual torch CUDA trio — torchsde removed since --extra-index-url handles resolution correctly
$TorchProtected     = @("torch", "torchvision", "torchaudio")

# --- Minimum supported ComfyUI version ---
# Versions below this threshold require Torch 2.9.0+cu128 — user must switch manually via option [1]
$MinComfyVersion    = "v0.13.0"

# --- UI / Behavior ---
$MenuTimeoutSeconds = 300   # 5 minutes before auto-return to main menu
$OutputEncoding     = [System.Text.UTF8Encoding]::new()

# --- Startup Environment Check ---
function Test-Environment {
    $warnings = @()
    if (!(Test-Path $VenvPython))                                { $warnings += "[WARN] Python venv not found: $VenvPython" }
    if (!(Test-Path $ComfyDir))                                  { $warnings += "[WARN] ComfyUI directory not found: $ComfyDir" }
    if (!(Get-Command git        -ErrorAction SilentlyContinue)) { $warnings += "[WARN] git not found in PATH" }
    if (!(Get-Command nvidia-smi -ErrorAction SilentlyContinue)) { $warnings += "[WARN] nvidia-smi not found — GPU info unavailable" }

    if ($warnings.Count -gt 0) {
        Write-Host ""
    Write-Log "--- STARTUP WARNINGS ---" WARN
        foreach ($w in $warnings) {
            Write-Host " $w" -ForegroundColor Yellow
            Write-FileLog $w
        }
        Write-Log "-------------------------" WARN
        Start-Sleep -Seconds 2
    }

    # Deploy smart_fixer.py to .cache on startup so it is always ready
    # Module 6 needs it, but conflicts can also be triggered from Module 4/5
    if (!(Test-Path $SmartFixerPath)) {
        $sourceFixerPath = Join-Path $ScriptRoot "smart_fixer.py"
        if (Test-Path $sourceFixerPath) {
            Copy-Item $sourceFixerPath $SmartFixerPath -Force
            Write-Log "smart_fixer.py deployed to .cache" INFO
        } else {
            Write-Log "smart_fixer.py not found next to script — Module 6 will not work!" WARN
        }
    }
}

# --- Unified console output (matches ComfyUI-Environment.ps1 style) ---
# Levels: OK (green), WARN (yellow), ERROR (red), STEP (cyan),
#         PROCESS (yellow), NET (gray), INFO (darkgray), SUCCESS (green)
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('OK','WARN','ERROR','STEP','PROCESS','NET','INFO','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $prefix = switch ($Level) {
        'OK'      { '[OK]'      }
        'WARN'    { '[WARN]'    }
        'ERROR'   { '[ERROR]'   }
        'STEP'    { '[STEP]'    }
        'PROCESS' { '[PROCESS]' }
        'NET'     { '[NET]'     }
        'SUCCESS' { '[SUCCESS]' }
        default   { '[INFO]'    }
    }
    $color = switch ($Level) {
        'OK'      { 'Green'    }
        'WARN'    { 'Yellow'   }
        'ERROR'   { 'Red'      }
        'STEP'    { 'Cyan'     }
        'PROCESS' { 'Yellow'   }
        'NET'     { 'Gray'     }
        'SUCCESS' { 'Green'    }
        default   { 'DarkGray' }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

# --- File logger with rotation (keeps last 500 lines, triggers above 50 KB) ---
function Write-FileLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
    $line | Add-Content $LogFile

    if ((Get-Item $LogFile -ErrorAction SilentlyContinue).Length -gt 50KB) {
        $lines = Get-Content $LogFile
        if ($lines.Count -gt 500) {
            $lines | Select-Object -Last 500 | Set-Content $LogFile
        }
    }
}

function Write-ReleaseNote([string]$content) {
    $content | Set-Content $rnFile
}

# --- Venv artifact cleanup ---
function Cleanup-Venv {
    if (!(Test-Path $SitePackages)) { return }

    # Remove pip temp artifacts (~*)
    Get-ChildItem $SitePackages -Filter "~*" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Remove orphaned .dist-info directories (metadata without matching package)
    # Uses "pip show" as the authority — reliable for all packages regardless of folder naming
    # (e.g. PyYAML dist-info -> yaml folder, Pillow -> PIL, scikit-learn -> sklearn)
    Get-ChildItem $SitePackages -Filter "*.dist-info" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        # Strip version + local suffix (e.g. -2.10.0+cu130.dist-info -> torch)
        $pkgName  = $_.Name -replace '-[\d\.]+[^-]*\.dist-info$', ''
        $pipCheck = & $VenvPython -m pip show $pkgName 2>$null
        if (!$pipCheck) {
            Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Remove __pycache__ folders inside site-packages
    Get-ChildItem $SitePackages -Filter "__pycache__" -Directory -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Apply const.txt as pip constraint ---
function Apply-ConstConstraints {
    if (Test-Path $ConstFile) {
        $env:PIP_CONSTRAINT = $ConstFile
        Write-Log "pip constraints loaded from const.txt" INFO
    } else {
        $env:PIP_CONSTRAINT = ""
    }
}


#endregion

#region MODULE 2 - UI Engine

function Read-Choice([string]$Prompt, [int[]]$Allowed, [bool]$AllowTimeout = $false) {
    $deadline = (Get-Date).AddSeconds($MenuTimeoutSeconds)

    while ($true) {
        if ($AllowTimeout) {
            $remaining = [int]($deadline - (Get-Date)).TotalSeconds
            if ($remaining -le 0) {
                Write-Host ""; Write-Log "No input detected. Returning to main menu..." INFO
                return -1
            }
            $timerDisplay = if ($remaining -le 30) { " (auto-exit in ${remaining}s)" } else { "" }
            $fullPrompt   = "$Prompt$timerDisplay"
        } else {
            $fullPrompt = $Prompt
        }

        if ($AllowTimeout) {
            Write-Host -NoNewline "`r$fullPrompt : "
            if ([Console]::KeyAvailable) {
                $input = Read-Host
            } else {
                Start-Sleep -Milliseconds 500
                continue
            }
        } else {
            $input = Read-Host $fullPrompt
        }

        if ($input -match '^\d+$' -and $Allowed -contains [int]$input) { return [int]$input }
        Write-Host "[!] Error: Invalid selection. Use one of: $($Allowed -join ', ')" -ForegroundColor Red

        # Reset countdown on invalid input
        if ($AllowTimeout) { $deadline = (Get-Date).AddSeconds($MenuTimeoutSeconds) }
    }
}


#endregion

#region MODULE 3 - Show Environment Info

function Show-Info {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    Write-Host ""
    Write-Host "  --- System Environment Info ---" -ForegroundColor Cyan

    $reportContent = ""

    # --- ComfyUI version (git tag + short commit hash) ---
    if (Test-Path $ComfyDir) {
        Push-Location $ComfyDir
        $comfyTag    = git describe --tags --abbrev=0 2>$null
        $comfyCommit = git rev-parse --short HEAD 2>$null
        Pop-Location

        if ($comfyTag -and $comfyCommit) {
            $comfyLine = "  ComfyUI:         $comfyTag ($comfyCommit)"
        } elseif ($comfyCommit) {
            $comfyLine = "  ComfyUI:         (no tag) $comfyCommit"
        } else {
            $comfyLine = "  ComfyUI:         Not found or git error"
        }
    } else {
        $comfyLine = "  ComfyUI:         Directory not found"
    }
    Write-Host $comfyLine -ForegroundColor Cyan
    $reportContent += "$comfyLine`n"

    # --- GPU info via nvidia-smi ---
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $smi      = nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv,noheader,nounits
        $cudaVer  = (nvidia-smi | Select-String "CUDA Version: (\d+\.\d+)").Matches.Groups[1].Value
        $smiParts = $smi -split ','
        $vram     = [Math]::Round([float]$smiParts[2] / 1024, 2)
        $gpuLine  = "  GPU / CUDA:      $($smiParts[1].Trim()) ($vram GB VRAM, Driver $($smiParts[0].Trim()), CUDA $cudaVer)"
        Write-Host $gpuLine -ForegroundColor Cyan
        $reportContent += "$gpuLine`n"
    } else {
        $gpuLine = "  GPU / CUDA:      NVIDIA-SMI not found (Check Drivers)"
        Write-Host $gpuLine -ForegroundColor Red
        $reportContent += "$gpuLine`n"
    }

    # --- CPU, RAM, Python and package versions via venv Python ---
    $pythonCode = @'
import subprocess, sys, platform, importlib
from importlib.metadata import version, PackageNotFoundError

def install_if_needed(package):
    try:
        importlib.import_module(package)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", package],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

install_if_needed("psutil")
install_if_needed("py-cpuinfo")
import psutil, cpuinfo

def get_cpu():
    try:
        i = cpuinfo.get_cpu_info()
        brand   = i.get('brand_raw', 'Unknown')
        cores   = psutil.cpu_count(logical=False)
        threads = psutil.cpu_count()
        return f"{brand} ({cores}C/{threads}T)"
    except:
        return "Unknown"

def gv(package_name):
    aliases = {
        "triton":        ["triton-windows", "triton"],
        "flash-attn":    ["flash-attn", "flash_attn"],
        "sageattention": ["sageattention", "sage-attention"],
        "sageattn3":     ["sageattn3", "sage-attn3"]
    }
    search_names = aliases.get(package_name.lower(), [package_name])
    for name in search_names:
        try: return version(name)
        except PackageNotFoundError: continue
    try:
        mod = importlib.import_module(package_name.replace("-", "_"))
        return getattr(mod, "__version__", "Installed")
    except:
        return "Not installed"

ram_gb = round(psutil.virtual_memory().total / (1024**3), 2)
print(f" CPU Info:        {get_cpu()}")
print(f" RAM Size:        {ram_gb} GB")
print(f" Python Version:  {platform.python_version()}")
print(f" Torch:           {gv('torch')}")
print(f" Torchaudio:      {gv('torchaudio')}")
print(f" Torchvision:     {gv('torchvision')}")
print(f" Triton:          {gv('triton')}")
print(f" Xformers:        {gv('xformers')}")
print(f" Flash-Attn:      {gv('flash-attn')}")
print(f" Sage-Attn 2:     {gv('sageattention')}")
print(f" Sage-Attn 3:     {gv('sageattn3')}")
'@

    $rawOutput = if (Test-Path $VenvPython) {
        $pythonCode | & $VenvPython - 2>&1
    } else {
        "Venv Python not found!"
    }

    foreach ($line in $rawOutput) {
        if ($line -match "Not installed") {
            Write-Host " $line" -ForegroundColor DarkGray
        } else {
            Write-Host " $line" -ForegroundColor Cyan
        }
        $reportContent += "$line`n"
    }

    # --- Pip cache status ---
    Write-Host ""
    Write-Log "Pip cache status:" INFO
    $cacheInfo = ""
    if (Test-Path $VenvPython) {
        $cacheData = & $VenvPython -m pip cache info 2>$null
        foreach ($line in $cacheData) {
            if ($line -match "Location:|Total size:|Size:") {
                Write-Host "  $line" -ForegroundColor Yellow
                $cacheInfo += "`n$line"
            }
        }
    }

    # --- Save snapshot to env_state.log (path defined in Module 1) ---
    try {
        $logHeader  = "Scan Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        $logContent = $logHeader + $reportContent + "`n--- Pip Cache ---" + $cacheInfo
        $logContent | Out-File -FilePath $EnvLogFile -Encoding UTF8 -Force
        Write-Log "Snapshot saved to .cache\env_state.log" INFO
    } catch {
        Write-Log "Could not save env_state.log." WARN
    }

    Write-Host "  ---" -ForegroundColor DarkGray
    $null = Read-Choice "Enter [0] to return to menu" @(0)
}


#endregion

#region MODULE 4 - Torch Stack Management
# Install and switch torch/torchvision/torchaudio for a selected CUDA version.
# CUDA version list is fetched dynamically from the PyTorch website.
# ComfyUI requirements.txt is synced afterwards (torch trio excluded).

function Get-SupportedCudaVersions {
    Write-Host ""; Write-Log "Fetching supported CUDA versions from PyTorch..." NET
    try {
        $data         = Invoke-WebRequest "https://docs.pytorch.org/assets/quick-start-module.js" -UseBasicParsing -TimeoutSec 10
        $releaseBlock = [regex]::Match($data.Content, '"release":\s*{([^}]*)}').Groups[1].Value
        $cu           = [regex]::Matches($releaseBlock, '"cuda\.\w+":\s*\["cuda",\s*"([\d\.]+)"\]') |
                        ForEach-Object { $_.Groups[1].Value } |
                        Sort-Object { [version]$_ } -Descending |
                        ForEach-Object { $_ -replace '\.', '' }

        if ($cu -and $cu.Count -gt 0) { return $cu }
        Write-Log "PyTorch returned an empty CUDA list." WARN
    } catch {
        Write-Log "Could not reach PyTorch site: $($_.Exception.Message)" WARN
    }

    # Fallback: manual entry
    Write-Host ""; Write-Log "Enter CUDA version manually (e.g. 126, 128, 130):" STEP
    while ($true) {
        $manual = Read-Host "CUDA version"
        if ($manual -match '^\d{3}$') { return @($manual) }
        Write-Log "Invalid format. Use 3 digits, e.g. 128" ERROR
    }
}

function Get-TorchConflictsWithComfyUI {
    # Reads ComfyUI requirements.txt and checks whether installed torch versions satisfy them.
    # Returns warning strings for any mismatch — does NOT modify anything.
    $reqFile = Join-Path $ComfyDir "requirements.txt"
    if (!(Test-Path $reqFile)) { return @() }

    $conflicts       = @()
    $currentVersions = @{}

    foreach ($pkg in $TorchProtected) {
        $ver = (& $VenvPython -c "import importlib.metadata; print(importlib.metadata.version('$pkg'))" 2>$null)
        if ($ver) { $currentVersions[$pkg] = $ver }
    }

    foreach ($line in Get-Content $reqFile) {
        $line    = $line.Trim()
        if (!$line -or $line.StartsWith('#')) { continue }
        $pkgName = ($line -split '[>=<!]')[0].Trim().ToLower()
        if ($TorchProtected -notcontains $pkgName) { continue }

        if ($line -match '[>=<!]+(.+)') {
            $reqVer  = $Matches[1].Trim()
            $op      = [regex]::Match($line, '[>=<!]+').Value
            $currVer = $currentVersions[$pkgName]
            if ($currVer) {
                $conflicts += "[!] $pkgName : installed=$currVer, ComfyUI requires $op$reqVer"
            }
        }
    }
    return $conflicts
}

function Change-Torch {
    Cleanup-Venv
    if (!(Test-Path $VenvPython)) {
        Write-Log "venv not found!" ERROR
        return
    }

    $currentTorch = (& $VenvPython -c "import torch; print(torch.__version__)" 2>$null)
    Write-Host "`n--- Torch Stack Configuration (NVIDIA CUDA) ---" -ForegroundColor Cyan
    Write-Host " Current Torch: " -NoNewline -ForegroundColor Gray
    Write-Host $currentTorch -ForegroundColor Cyan

    # --- Dynamic CUDA list ---
    $cu = Get-SupportedCudaVersions

    Write-Host "`nSelect CUDA version:" -ForegroundColor White
    for ($i = 0; $i -lt $cu.Count; $i++) { Write-Host " [$($i + 1)] cu$($cu[$i])" }
    Write-Host " [0] Back"

    $cuChoice = Read-Choice "Choice" ((1..$cu.Count) + 0)
    if ($cuChoice -eq 0) { return }

    $selectedCu = $cu[$cuChoice - 1]
    $indexUrl   = "https://download.pytorch.org/whl/cu$selectedCu"

    # --- Fetch available torch versions from PyTorch index ---
    # Uses direct PowerShell process (not cmd /c) to avoid quoting and CRLF issues.
    Write-Host ""; Write-Log "Fetching available Torch versions for cu$selectedCu..." NET
    $rawLines = & $VenvPython -m pip install "torch==0.0.0" --index-url $indexUrl 2>&1
    $raw      = $rawLines -join " "

    if ($raw -notmatch "from versions:\s*([\d\.\+a-z ,cu]+)\)") {
        Write-Log "Could not fetch version list from PyTorch index." ERROR
        Write-Log "Response: $($raw | Select-Object -Last 3)" INFO
        Read-Host "Press Enter to return"
        return
    }

    $versions = $Matches[1].Split(',') |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ -match '^\d+\.\d+\.\d+' } |
                Select-Object  -Unique |
                Sort-Object    { [version]($_ -replace '\+.*', '') } -Descending |
                Select-Object  -First 5

    Write-Host "`nSelect Torch version:" -ForegroundColor White
    for ($i = 0; $i -lt $versions.Count; $i++) {
        $cleanName = $versions[$i] -replace '\+.*', ''
        $mark      = if ($currentTorch -and $cleanName -eq $currentTorch) { " (current)" } else { "" }
        Write-Host " [$($i + 1)] $cleanName$mark"
    }
    Write-Host " [0] Back"

    $vIndex = Read-Choice "Choice" ((1..$versions.Count) + 0)
    if ($vIndex -eq 0) { return }
    $target = $versions[$vIndex - 1]

    # --- Install torch trio ---
    Write-Host ""; Write-Log "Installing Torch Stack ($target, cu$selectedCu)..." PROCESS
    & $VenvPython -m pip install "torch==$target" torchvision "torchaudio==$target" `
        --index-url $indexUrl --upgrade --prefer-binary --force-reinstall

    # --- Sync ComfyUI requirements (torch stack excluded) ---
    # Uses --no-deps first pass to prevent torch CUDA builds being replaced.
    # torch+cu* versions are not resolvable from PyPI — any constraint causes ResolutionImpossible.
    $reqFile = Join-Path $ComfyDir "requirements.txt"
    if (Test-Path $reqFile) {
        Write-Log "Syncing ComfyUI requirements (Torch stack excluded)..." PROCESS

        $filteredReq = "$CacheDir\requirements_filtered.tmp"
        Get-Content $reqFile | Where-Object {
            $pkgName = ($_ -split '[>=<!]')[0].Trim().ToLower()
            $TorchProtected -notcontains $pkgName
        } | Set-Content $filteredReq -Encoding UTF8

        # Use --extra-index-url so pip can resolve torch+cu* versions from PyTorch index
        # This allows full dependency resolution without --no-deps костилі
        # CUDA index is read from const.txt written by Module 4 after torch install
        $cudaIndex = ""
        if (Test-Path $ConstFile) {
            $torchLine = Get-Content $ConstFile | Where-Object { $_ -match "^torch==" } | Select-Object -First 1
            if ($torchLine -match "\+cu(\d+)") { $cudaIndex = "https://download.pytorch.org/whl/cu$($Matches[1])" }
        }

        if ($cudaIndex) {
            Write-Log "Installing with PyTorch index (cu$($Matches[1]))..." PROCESS
            & $VenvPython -m pip install -r $filteredReq --prefer-binary --extra-index-url $cudaIndex
        } else {
            Write-Log "Installing dependencies (no CUDA index found)..." PROCESS
            & $VenvPython -m pip install -r $filteredReq --prefer-binary
        }

        Remove-Item $filteredReq -Force -ErrorAction SilentlyContinue
    }

    # --- Compatibility check: new torch trio vs current ComfyUI ---
    Write-Host ""; Write-Log "Checking Torch compatibility with current ComfyUI..." STEP
    $torchConflicts = Get-TorchConflictsWithComfyUI
    if ($torchConflicts.Count -gt 0) {
        Write-Host ""; Write-Log "WARNING: New Torch stack may conflict with current ComfyUI requirements:" WARN
        foreach ($c in $torchConflicts) { Write-Host "    $c" -ForegroundColor Yellow }
        Write-Log "Use option [1] Change Torch Stack from the main menu to update it." INFO
    } else {
        Write-Log "Torch stack is compatible with current ComfyUI." OK
    }

    # --- Custom nodes warning ---
    $customNodesDir = Join-Path $ComfyDir "custom_nodes"
    if (Test-Path $customNodesDir) {
        $nodeCount = (Get-ChildItem $customNodesDir -Directory |
                      Where-Object { $_.Name -ne "__pycache__" }).Count
        if ($nodeCount -gt 0) {
            Write-Host ""; Write-Log "WARNING: $nodeCount custom node(s) detected." WARN
            Write-Log "  They may not work with the new Torch stack." WARN
        }
    }

    # --- Dependency consistency check ---
    # Filter false positives: CUDA local version suffix (+cu130) confuses pip check metadata lookup
    Write-Host ""; Write-Log "Running dependency consistency check..." STEP
    $checkResult   = & $VenvPython -m pip check 2>&1
    $realConflicts = $checkResult | Where-Object {
        $_ -and
        $_ -notmatch "requires torch" -and
        $_ -notmatch "requires torchvision" -and
        $_ -notmatch "requires torchaudio" -and
        $_ -notmatch "requires torchsde" -and
        $_ -notmatch "No broken requirements"
    }
    if ($realConflicts -and $realConflicts.Count -gt 0) {
        Write-Host ""; Write-Log "CRITICAL: Dependency conflicts detected!" ERROR
        $realConflicts | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
        Write-Host ""; Write-Log "Run Deep Repair Tool (Module 6) now?" WARN
        Write-Host " [1] Yes, Repair Now`n [0] No, fix manually"
        if ((Read-Choice "Select" @(1, 0)) -eq 1) { Repair-Environment -CalledFromModule }
    } else {
        Write-Log "No dependency conflicts found." SUCCESS
    }

    # --- Save torch snapshot for restore capability ---
    # Writes torch version + cuda index to const.txt so Module 5 can restore if needed
    $installedTorch = (& $VenvPython -c "import torch; print(torch.__version__)" 2>$null)
    if ($installedTorch) {
        $torchSnap  = "torch==$installedTorch  # cu$selectedCu index"
        $tvSnap     = (& $VenvPython -c "import torchvision; print(torchvision.__version__)" 2>$null)
        $taSnap     = (& $VenvPython -c "import torchaudio; print(torchaudio.__version__)" 2>$null)
        $snapLines  = @(
            "# ComfyUI Master Manager — Torch Snapshot",
            "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
            "# CUDA index: cu$selectedCu",
            "# DO NOT EDIT MANUALLY",
            "",
            "torch==$installedTorch",
            "torchvision==$tvSnap",
            "torchaudio==$taSnap"
        )
        $snapLines | Set-Content $ConstFile -Encoding UTF8
        Write-Log "Torch snapshot saved to const.txt" INFO
    }

    Write-FileLog "Torch switched: $currentTorch -> $($target -replace '\+.*','') (cu$selectedCu)"
    Write-Host ""; Write-Log "Torch stack updated to $($target -replace '\+.*','') (cu$selectedCu)" SUCCESS
    Read-Host "Press Enter to continue"
}


#endregion

#region MODULE 5 - ComfyUI Version Management
# Switch ComfyUI to a specific git tag.
# Torch trio is always excluded from requirements.txt install.
# If requirements.txt references the torch trio, a warning is shown — user decides.

function Get-TorchConflictsFromRequirements([string]$reqFile) {
    # Returns lines from a requirements file that reference the protected torch trio.
    $conflicts = @()
    if (!(Test-Path $reqFile)) { return $conflicts }
    foreach ($line in Get-Content $reqFile) {
        $pkgName = ($line -split '[>=<!]')[0].Trim().ToLower()
        if ($TorchProtected -contains $pkgName) { $conflicts += $line.Trim() }
    }
    return $conflicts
}

function Change-ComfyUI {
    Cleanup-Venv
    if (!(Test-Path $ComfyDir)) {
        Write-Log "ComfyUI directory not found!" ERROR
        return
    }

    Push-Location $ComfyDir

    # --- Show current version ---
    $current       = git describe --tags --abbrev=0 2>$null
    $currentCommit = git rev-parse --short HEAD 2>$null
    Write-Host ""; Write-Host "  Current version: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$current ($currentCommit)" -ForegroundColor Cyan

    # --- Fetch all tags ---
    Write-Log "Fetching tags..." STEP
    git fetch --tags --all --quiet
    $allTags = git tag -l --sort=-v:refname

    # --- Build branch list (unique MAJOR.MINOR, e.g. v0.18) ---
    $branches = $allTags |
        ForEach-Object { if ($_ -match '^(v\d+\.\d+)') { $Matches[1] } } |
        Select-Object -Unique |
        Sort-Object { [version]($_ -replace 'v','') } -Descending |
        Select-Object -First 10

    # --- Level 1: Branch selection ---
    Write-Host "`nAvailable ComfyUI branches:" -ForegroundColor White
    for ($i = 0; $i -lt $branches.Count; $i++) {
        $branchTags  = $allTags | Where-Object { $_ -match "^$([regex]::Escape($branches[$i]))\." -or $_ -eq $branches[$i] }
        $hasCurrent  = $branchTags -contains $current
        $mark        = if ($hasCurrent) { " (current)" } else { "" }
        Write-Host " [$($i + 1)] $($branches[$i])$mark"
    }
    Write-Host " [0] Back to Main Menu"

    $branchChoice = Read-Choice "Select branch" ((1..$branches.Count) + 0)
    if ($branchChoice -eq 0) { Pop-Location; return }

    $selectedBranch = $branches[$branchChoice - 1]

    # --- Release notes (optional, for selected branch) ---
    $branchTags = @($allTags | Where-Object { $_ -match "^$([regex]::Escape($selectedBranch))\." -or $_ -eq $selectedBranch } |
        Sort-Object { [version]($_ -replace 'v','') })

    Write-Host "`nFetch and show release notes for $selectedBranch versions?" -ForegroundColor White
    Write-Host " [1] Yes (Fetch & Display)`n [0] No (Skip)"

    if ((Read-Choice "Select" @(1, 0)) -eq 1) {
        Write-Host ""; Write-Log "Fetching release notes from GitHub..." NET
        "=== ComfyUI Release Notes ($selectedBranch) - Generated $(Get-Date) ===`n" | Set-Content $rnFile

        foreach ($tag in $branchTags) {
            try {
                $res = Invoke-RestMethod "https://api.github.com/repos/Comfy-Org/ComfyUI/releases/tags/$tag" -ErrorAction SilentlyContinue
                if ($res) {
                    $cleanBody = ($res.body -split '## New Contributors' | Select-Object -First 1).Trim()
                    Write-Host "`n--- VERSION: $tag ---" -ForegroundColor Cyan
                    Write-Host $cleanBody -ForegroundColor Gray
                    "--- $tag ---`n$cleanBody`n" | Add-Content $rnFile
                }
            } catch { Write-Log "  Failed to fetch notes for $tag" WARN }
        }
    }

    # --- Level 2: Minor version selection within branch ---
    Write-Host "`nAvailable versions in $selectedBranch :" -ForegroundColor White
    for ($i = 0; $i -lt $branchTags.Count; $i++) {
        $mark = if ($branchTags[$i] -eq $current) { " (current)" } else { "" }
        Write-Host " [$($i + 1)] $($branchTags[$i])$mark"
    }
    Write-Host " [0] Back to Branch Menu"

    $vChoice = Read-Choice "Select version" ((1..$branchTags.Count) + 0)
    if ($vChoice -eq 0) { Pop-Location; return }

    $target = $branchTags[$vChoice - 1]
    if ($target -eq $current) {
        Write-Host ""; Write-Log "$target is already installed." INFO
        Write-Host " Reinstall dependencies for this version?" -ForegroundColor White
        Write-Host " [1] Yes, reinstall`n [0] No, go back"
        if ((Read-Choice "Select" @(1, 0)) -eq 0) { Pop-Location; return }
        # Fall through — runs the full install block below with same $target
    }

    # --- Pre-flight: check if target requirements.txt touches torch trio ---
    Write-Host ""; Write-Log "Checking requirements for $target..." STEP
    git show "$($target):requirements.txt" 2>$null | Out-File "$CacheDir\req_check.tmp" -Encoding UTF8 -Force

    $torchConflicts = Get-TorchConflictsFromRequirements "$CacheDir\req_check.tmp"
    if ($torchConflicts.Count -gt 0) {
        Write-Host ""; Write-Log "WARNING: requirements.txt for $target references the protected Torch stack:" WARN
        foreach ($c in $torchConflicts) { Write-Host "    $c" -ForegroundColor Yellow }

        $currentTorch = (& $VenvPython -c "import torch; print(torch.__version__)" 2>$null)
        Write-Log "Your current Torch: $currentTorch (will NOT be changed)" INFO
        Write-Log "Use option [1] Change Torch Stack from the main menu to update it." INFO

        Write-Host "`n Continue installation anyway?" -ForegroundColor White
        Write-Host " [1] Yes, continue`n [0] Cancel"
        if ((Read-Choice "Select" @(1, 0)) -eq 0) { Pop-Location; return }
    }

    # --- Minimum version check ---
    $minVer    = [version]($MinComfyVersion -replace 'v', '')
    $targetVer = [version]($target -replace 'v', '')
    if ($targetVer -lt $minVer) {
        Write-Host ""; Write-Log "WARNING: $target is below minimum recommended version ($MinComfyVersion)." WARN
        Write-Log "  Very old versions may have compatibility issues with current Torch or Python." WARN
        Write-Log "  If ComfyUI fails to start, try switching Torch via option [1]." INFO
        Write-Host "`n Continue anyway?" -ForegroundColor White
        Write-Host " [1] Yes`n [0] Cancel"
        if ((Read-Choice "Select" @(1, 0)) -eq 0) { Pop-Location; return }
    }

    # --- Database migration check ---
    # When downgrading, ComfyUI's alembic DB may contain newer migrations unknown to the old version.
    # Safest fix: delete the DB and let the target version recreate it from scratch.
    # The DB contains only asset cache and job history — no user workflows or models.
    $dbPath = Join-Path $ComfyDir "user\comfyui.db"
    if (Test-Path $dbPath) {
        $isDowngrade = [version]($target -replace 'v','') -lt [version]($current -replace 'v','')
        if ($isDowngrade) {
            Write-Host ""; Write-Log "DOWNGRADE DETECTED: $current -> $target" WARN
            Write-Log "  Database may contain migrations incompatible with $target." WARN
            Write-Log "  Recommended: delete the database and let ComfyUI recreate it." INFO
            Write-Log "  Database stores only asset cache and job history — no workflows or models." INFO
            Write-Host "`n Delete database automatically?" -ForegroundColor White
            Write-Host " [1] Yes, delete and recreate`n [0] No, keep it (may cause startup errors)"
            if ((Read-Choice "Select" @(1, 0)) -eq 1) {
                Remove-Item $dbPath -Force
                Write-Log "Database removed. ComfyUI will recreate it on next launch." OK
            } else {
                Write-Log "Database kept. If ComfyUI fails to start, delete manually:" WARN
                Write-Log "  $dbPath" INFO
            }
        }
    }

    # --- Switch version ---
    Write-Host ""; Write-Log "Switching to $target..." PROCESS
    git checkout $target --force --quiet

    # --- Install requirements (torch stack fully excluded) ---
    # Uses --no-deps to prevent pip from touching torch stack via transitive dependencies.
    # Torch+CUDA versions use +cu130 suffix which pip cannot resolve from PyPI,
    # so any constraint or resolver attempt causes ResolutionImpossible errors.
    # Strategy: install each requirement individually with --no-deps, then
    # run a second pass without --no-deps for non-torch packages only.
    $reqFile = Join-Path $ComfyDir "requirements.txt"
    if (Test-Path $reqFile) {
        Write-Log "Installing dependencies (Torch stack excluded)..." PROCESS

        $filteredReq = "$CacheDir\requirements_filtered.tmp"
        Get-Content $reqFile | Where-Object {
            $pkgName = ($_ -split '[>=<!]')[0].Trim().ToLower()
            $TorchProtected -notcontains $pkgName
        } | Set-Content $filteredReq -Encoding UTF8

        # Use --extra-index-url so pip resolves torch+cu* from PyTorch index
        # This replaces all --no-deps костилі with clean full dependency resolution
        $cudaIndex = ""
        if (Test-Path $ConstFile) {
            $torchLine = Get-Content $ConstFile | Where-Object { $_ -match "^torch==" } | Select-Object -First 1
            if ($torchLine -match "[+]cu(\d+)") { $cudaIndex = "https://download.pytorch.org/whl/cu$($Matches[1])" }
        }

        if ($cudaIndex) {
            Write-Log "Installing with PyTorch index (cu$($Matches[1]))..." PROCESS
            & $VenvPython -m pip install -r $filteredReq --prefer-binary --extra-index-url $cudaIndex
        } else {
            Write-Log "Installing dependencies (no CUDA index found)..." PROCESS
            & $VenvPython -m pip install -r $filteredReq --prefer-binary
        }

        # Update comfyui-workflow-templates WITH deps to sync its sub-packages
        $workflowPkg = Get-Content $filteredReq | Where-Object { $_ -match "comfyui-workflow-templates==" } | Select-Object -First 1
        if ($workflowPkg) {
            Write-Log "Updating workflow template sub-packages..." PROCESS
            $extraArg = if ($cudaIndex) { "--extra-index-url $cudaIndex" } else { "" }
            & $VenvPython -m pip install $workflowPkg.Trim() --prefer-binary $extraArg
        }

        Remove-Item $filteredReq -Force -ErrorAction SilentlyContinue
    }

    # --- Networking stack ---
    # Install latest versions first, then Module 6 (smart_fixer) will resolve any version conflicts dynamically
    Write-Log "Resolving networking stack..." PROCESS
    # chardet is intentionally excluded — version is managed by Module 6 (smart_fixer)
    & $VenvPython -m pip install requests urllib3 charset-normalizer --upgrade --prefer-binary

    # --- Python 3.14 venv fix ---
    # On Python 3.14, system importlib.metadata can leak into venv causing PackageNotFoundError
    # for packages that ARE installed. Installing importlib-metadata and pyyaml explicitly
    # forces correct metadata resolution inside the venv.
    Write-Log "Applying Python 3.14 metadata fix..." PROCESS
    & $VenvPython -m pip install importlib-metadata pyyaml typing-extensions --upgrade --prefer-binary

    # --- Custom nodes warning ---
    $customNodesDir = Join-Path $ComfyDir "custom_nodes"
    if (Test-Path $customNodesDir) {
        $nodeCount = (Get-ChildItem $customNodesDir -Directory |
                      Where-Object { $_.Name -ne "__pycache__" }).Count
        if ($nodeCount -gt 0) {
            Write-Host ""; Write-Log "WARNING: You have $nodeCount custom node(s) installed." WARN
            Write-Log "  They may be incompatible with $target." WARN
            Write-Log "  Check their status before launching ComfyUI." WARN
        }
    }

    # --- Dependency consistency check ---
    # Filter out false positives: kornia/spandrel/torchsde report torch as missing
    # because pip check cannot resolve +cu130 local version suffix from PyPI metadata.
    Write-Host ""; Write-Log "Running dependency consistency check..." STEP
    $checkResult = & $VenvPython -m pip check 2>&1
    $realConflicts = $checkResult | Where-Object {
        $_ -and
        $_ -notmatch "requires torch" -and
        $_ -notmatch "requires torchvision" -and
        $_ -notmatch "requires torchaudio" -and
        $_ -notmatch "requires torchsde" -and
        $_ -notmatch "No broken requirements"
    }
    if ($realConflicts -and $realConflicts.Count -gt 0) {
        Write-Host ""; Write-Log "CRITICAL: Dependency conflicts detected!" ERROR
        $realConflicts | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
        Write-Host ""; Write-Log "Run Deep Repair Tool (Module 6) now?" WARN
        Write-Host " [1] Yes, Repair Now`n [0] No, fix manually"
        if ((Read-Choice "Select" @(1, 0)) -eq 1) { Repair-Environment -CalledFromModule }
    } else {
        Write-Log "No dependency conflicts found." SUCCESS
    }

    Write-Host ""; Write-Log "ComfyUI switched: $current -> $target" SUCCESS
    Write-FileLog "ComfyUI switched: $current ($currentCommit) -> $target"

    Remove-Item "$CacheDir\req_check.tmp" -Force -ErrorAction SilentlyContinue
    Read-Host "Press Enter to continue"
    Pop-Location
}


#endregion

#region MODULE 6 - Environment Repair
# Smart dependency repair using smart_fixer.py (Auto Dependency Guard).
# Protected: torch, torchvision, torchaudio and all ComfyUI requirements.txt entries.
# When called standalone: warns if conflicts cannot be fully resolved (e.g. bad custom node).
# When called from Module 4/5: same logic, silent on partial failure.

function Deploy-SmartFixer {
    # Copies smart_fixer.py from ScriptRoot to .cache if not already present.
    if (!(Test-Path $SmartFixerPath)) {
        Write-Log "Deploying smart_fixer.py to .cache..." INFO
        $sourceFixerPath = Join-Path $ScriptRoot "smart_fixer.py"
        if (Test-Path $sourceFixerPath) {
            Copy-Item $sourceFixerPath $SmartFixerPath -Force
        } else {
            Write-Log "smart_fixer.py not found next to the script!" ERROR
            return $false
        }
    }
    return $true
}

function Repair-Environment {
    param([switch]$CalledFromModule)

    Write-Host ""
    Write-Host "  --- Environment Repair Tool ---" -ForegroundColor Red

    if ($CalledFromModule) {
        Write-Log "Mode: Conflict resolution (called by installer)" INFO
    } else {
        Write-Log "Mode: Manual repair (standalone)" INFO
        Write-Log "Use this after installing custom nodes that break dependencies." INFO
        Write-Log "Torch stack and ComfyUI core requirements are fully protected." INFO
        Write-Log "NOTE: If a custom node itself is broken or incompatible," INFO
        Write-Log "      this tool cannot fix it. Use ComfyUI-Manager to" INFO
        Write-Log "      disable, remove, or downgrade the problematic node." INFO
    }

    Write-Host "`n Proceed with repair?"
    Write-Host " [1] Yes, start Deep Repair`n [0] Cancel"
    if ((Read-Choice "Select" @(1, 0)) -eq 0) { return }

    if (!(Deploy-SmartFixer)) { return }

    # --- Step 1: Snapshot before repair ---
    Write-Host ""; Write-Log "[1/6] Capturing environment snapshot..." STEP
    $beforeList = & $VenvPython -m pip list --format json 2>$null | ConvertFrom-Json

    # --- Step 2: Clean only broken/corrupted cache entries (NOT torch — it is 2GB+) ---
    Write-Log "[2/6] Cleaning broken cache entries (torch preserved)..." STEP
    foreach ($pkg in @("chardet", "urllib3", "charset-normalizer", "requests", "numpy", "numba")) {
        & $VenvPython -m pip cache remove $pkg 2>$null | Out-Null
    }

    # --- Step 3: Remove broken venv artifacts ---
    Write-Log "[3/6] Removing broken dependency artifacts..." STEP
    Cleanup-Venv

    # --- Step 4: Run Smart Dependency Guard ---
    Write-Log "[4/6] Running Smart Dependency Guard..." STEP
    Write-Log "     Analyzing imports, detecting conflicts, auto-resolving..." INFO

    # Clear pip constraint before fixer runs — it decides what is safe
    $env:PIP_CONSTRAINT = ""

    $fixerResult   = & $VenvPython $SmartFixerPath $VenvPython $ComfyDir $CacheDir
    $fixerExitCode = $LASTEXITCODE

    foreach ($line in $fixerResult) {
        $color = switch -Wildcard ($line) {
            "*[OK]*"      { "Green"    }
            "*[FAIL]*"    { "Red"      }
            "*[FIX]*"     { "Yellow"   }
            "*[WARN]*"    { "Yellow"   }
            "*[SKIP]*"    { "DarkGray" }
            "*[SUMMARY]*" { "Cyan"     }
            default       { "Gray"     }
        }
        Write-Host "  $line" -ForegroundColor $color
    }

    # --- Step 5: Apply const.txt as pip constraint ---
    Write-Host ""; Write-Log "[5/6] Applying stable constraints (const.txt)..." STEP
    if ($fixerExitCode -eq 0) {
        Apply-ConstConstraints
        Write-Log "     Constraints active for future pip operations." INFO
    } else {
        Write-Log "     Skipped — unresolved conflicts remain." WARN
    }

    # --- Step 6: Change summary ---
    Write-Host ""; Write-Log "[6/6] Repair summary..." STEP
    $afterList    = & $VenvPython -m pip list --format json 2>$null | ConvertFrom-Json
    $changesFound = $false

    foreach ($newPkg in $afterList) {
        $oldPkg = $beforeList | Where-Object { $_.name -eq $newPkg.name } | Select-Object -First 1
        if ($oldPkg -and $oldPkg.version -ne $newPkg.version) {
            if ($TorchProtected -contains $newPkg.name.ToLower()) {
                Write-Host " [PROTECTED] " -NoNewline -ForegroundColor Cyan
            } else {
                Write-Host " [MODIFIED]  " -NoNewline -ForegroundColor White
            }
            Write-Host "$($newPkg.name): " -NoNewline
            Write-Host "$($oldPkg.version)" -ForegroundColor Red -NoNewline
            Write-Host " -> " -NoNewline
            Write-Host "$($newPkg.version)" -ForegroundColor Green
            $changesFound = $true
        }
    }

    if (!$changesFound) {
        Write-Log "No packages were changed. Environment was already optimal." INFO
    }

    # --- Final status ---
    if ($fixerExitCode -eq 0) {
        Write-Host ""; Write-Log "Repair complete. const.txt updated." SUCCESS
        Write-FileLog "Repair-Environment: SUCCESS. const.txt updated."
    } else {
        Write-Host ""; Write-Log "Repair finished with unresolved issues." WARN
        Write-Log "Some custom nodes may not work correctly." WARN
        Write-Log "Consider switching to a compatible ComfyUI version (option [2])." INFO
        Write-FileLog "Repair-Environment: PARTIAL. Unresolved conflicts remain."

        if (!$CalledFromModule) {
            Write-Host ""; Write-Log "This tool manages core dependencies only." INFO
            Write-Log "  If the conflict is caused by a custom node:" INFO
            Write-Log "  - Open ComfyUI-Manager and disable/remove the problematic node" INFO
            Write-Log "  - Or try downgrading it to an earlier version via ComfyUI-Manager" INFO
            Write-Log "  - Then run this repair again" INFO
        }
    }

    Read-Host "`nPress Enter to return"
}


#endregion

#region MAIN

Test-Environment

while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  ComfyUI Master Manager  v$ScriptVersion" -ForegroundColor Cyan
    Write-Host "  -----------------------------------" -ForegroundColor DarkGray
    Write-Host " [1] Change Torch Stack (NVIDIA CUDA)"
    Write-Host " [2] Change ComfyUI Version (Tags / Notes)"
    Write-Host " [3] Repair Environment (Deep Clean)"
    Write-Host " [4] Show Environment Info"
    Write-Host " [0] Exit"

    switch (Read-Choice "Select option" @(1,2,3,4,0) -AllowTimeout $true) {
        1  { Change-Torch }
        2  { Change-ComfyUI }
        3  { Repair-Environment }
        4  { Show-Info }
        0  { exit }
        -1 { continue }   # timeout — redraw menu
    }
}
#endregion
