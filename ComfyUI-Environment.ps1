# ==============================================================================
# ComfyUI Runtime Environment Manager
# ==============================================================================
$SCRIPT_VERSION = "0.1"
# ==============================================================================

#region CONFIG
# --- Elevation check: restart as admin if needed ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs -WorkingDirectory "$PSScriptRoot"
    exit
}

Set-Location -Path "$PSScriptRoot"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ProgressPreference = 'Continue'

# --- Paths ---
$DIR_COMFYUI  = "ComfyUI"
$DIR_VENV     = "venv"

# --- Runtime state ---
$script:Report = @()
#endregion CONFIG

# ==============================================================================

#region HELPERS

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

function Add-Report {
    param([string]$Level, [string]$Component, [string]$Message)
    $prefix = switch ($Level) {
        'OK'    { '[+]' }
        'Warn'  { '[~]' }
        'Error' { '[!]' }
        default { '[V]' }
    }
    $script:Report += [PSCustomObject]@{
        Prefix    = $prefix
        Component = $Component.PadRight(18)
        Message   = $Message
        Level     = $Level
    }
}

function Refresh-EnvPath {
    # Reload PATH from registry so newly installed tools are available immediately
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Compare-SemVer {
    # Returns: -1 (v1 older), 0 (equal), 1 (v1 newer)
    # Strips Windows-specific suffix: "2.47.1.windows.1" -> "2.47.1"
    param([string]$v1, [string]$v2)
    $clean = { ($args[0] -split '\.windows')[0].Trim() }
    try {
        $a = [System.Version](& $clean $v1)
        $b = [System.Version](& $clean $v2)
        return $a.CompareTo($b)
    } catch {
        return [string]::Compare((& $clean $v1), (& $clean $v2))
    }
}

function Get-VenvPythonBranch {
    # Reads the Python branch (e.g. "3.12") from venv\pyvenv.cfg
    # Returns $null if venv does not exist or version line is missing
    $cfg = "$PSScriptRoot\$DIR_VENV\pyvenv.cfg"
    if (-not (Test-Path $cfg)) { return $null }
    $line = Get-Content $cfg -Encoding UTF8 | Where-Object { $_ -match '^\s*version\s*=' }
    if (-not $line) { return $null }
    $full = ($line -split '=')[1].Trim()               # e.g. "3.12.10"
    if ($full -match '^(3\.\d+)') { return $Matches[1] }  # return "3.12"
    return $null
}

#endregion HELPERS

# ==============================================================================

#region MENU

function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  ComfyUI Runtime Environment Manager  v$SCRIPT_VERSION" -ForegroundColor Cyan
    Write-Host "  ---------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    # --- Current state summary ---
    $stateVenv   = if (Test-Path $DIR_VENV)    { "EXISTS"   } else { "missing" }
    $stateComfy  = if (Test-Path $DIR_COMFYUI) { "EXISTS"   } else { "missing" }
    $stateBranch = if ($stateVenv -eq "EXISTS") {
        $b = Get-VenvPythonBranch
        if ($b) { $b } else { "unknown" }
    } else { "no venv" }

    $colorVenv  = if ($stateVenv  -eq "EXISTS") { "Green" } else { "DarkYellow" }
    $colorComfy = if ($stateComfy -eq "EXISTS") { "Green" } else { "DarkYellow" }

    Write-Host "  Current state:" -ForegroundColor DarkGray
    Write-Host "    venv      : " -NoNewline -ForegroundColor DarkGray
    Write-Host $stateVenv          -ForegroundColor $colorVenv
    Write-Host "    ComfyUI   : " -NoNewline -ForegroundColor DarkGray
    Write-Host $stateComfy         -ForegroundColor $colorComfy
    Write-Host "    Py branch : " -NoNewline -ForegroundColor DarkGray
    Write-Host $stateBranch        -ForegroundColor Gray
    Write-Host ""
}

function Show-Menu {
    Show-Header

    Write-Host "  Select action:" -ForegroundColor White
    Write-Host ""
    Write-Host "    1  Install    " -NoNewline -ForegroundColor White
    Write-Host "- fresh setup: py launcher, git, vc++, python, venv, ComfyUI" -ForegroundColor DarkGray
    Write-Host "    2  Update     " -NoNewline -ForegroundColor White
    Write-Host "- update git + python minor; venv and ComfyUI not touched"    -ForegroundColor DarkGray
    Write-Host "    3  Swap       " -NoNewline -ForegroundColor White
    Write-Host "- change Python branch; recreates venv, ComfyUI not touched"  -ForegroundColor DarkGray
    Write-Host "    0  Exit"        -ForegroundColor DarkGray
    Write-Host ""

    do {
        $choice = Read-Host "  Enter (0-3)"
    } while ($choice -notmatch '^[0-3]$')

    return $choice
}

#endregion MENU

# ==============================================================================

#region INSTALL

function Install-PyLauncher {
    Write-Log "Checking Python Launcher..." STEP
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        $raw = (py --version 2>&1) | Out-String
        $ver = if ($raw -match '(\d+\.\d+[\.\d]*)') { $Matches[1] } else { "unknown" }
        Add-Report OK "Python Launcher" "already installed ($ver)"
        return
    }

    Write-Log "Installing Python Launcher..." STEP
    try {
        $baseUrl = "https://www.python.org/ftp/python/pymanager/"
        $page    = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        $msiHref = ($page.Links |
                    Where-Object { $_.href -like "python-manager-*.msi" } |
                    Select-Object -Last 1).href
        if (-not $msiHref) { throw "MSI not found on $baseUrl" }

        $msiPath = "$env:TEMP\pymanager.msi"
        Invoke-WebRequest -Uri ($baseUrl + $msiHref) -OutFile $msiPath -ErrorAction Stop
        Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait
        Remove-Item $msiPath -Force
        Refresh-EnvPath
        Add-Report OK "Python Launcher" "installed"
    } catch {
        Write-Log "Python Launcher install failed: $_" ERROR
        Add-Report ERROR "Python Launcher" "FAILED - $_"
    }
}

function Install-Git {
    Write-Log "Checking Git..." STEP
    try {
        $ghResp    = Invoke-WebRequest `
            -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
            -UseBasicParsing -ErrorAction Stop | ConvertFrom-Json
        $latestVer = ($ghResp.tag_name -replace '^v', '' -split '\.windows')[0].Trim()

        if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
            Write-Log "Installing Git $latestVer..." PROCESS
            $asset = $ghResp.assets |
                     Where-Object { $_.name -like "Git-*-64-bit.exe" } |
                     Select-Object -First 1
            Invoke-WebRequest -Uri $asset.browser_download_url `
                -OutFile "$env:TEMP\git_setup.exe" -ErrorAction Stop
            Start-Process "$env:TEMP\git_setup.exe" -ArgumentList "/VERYSILENT /NORESTART" -Wait
            Remove-Item "$env:TEMP\git_setup.exe" -Force
            Refresh-EnvPath
            git config --system core.longpaths true
            Add-Report OK "Git" "installed $latestVer"
        } else {
            Add-Report OK "Git" "already installed - run Update to check for upgrades"
        }
    } catch {
        Write-Log "Git install failed: $_" ERROR
        Add-Report ERROR "Git" "FAILED - $_"
    }
}

function Install-VCRedist {
    Write-Log "Checking Visual C++ Runtime..." STEP
    $vcPaths = @(
        "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x64"
    )
    $found = $vcPaths |
             ForEach-Object { Get-ItemProperty $_ -ErrorAction SilentlyContinue } |
             Where-Object { $_ } |
             Select-Object -First 1

    if ($found) {
        Add-Report OK "Visual C++" "already installed ($($found.Version))"
        return
    }

    Write-Log "Installing Visual C++ Runtime..." STEP
    try {
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
            -OutFile "$env:TEMP\vc_redist.exe" -ErrorAction Stop
        Start-Process "$env:TEMP\vc_redist.exe" -ArgumentList "/install /quiet /norestart" -Wait
        Remove-Item "$env:TEMP\vc_redist.exe" -Force
        Add-Report OK "Visual C++" "installed"
    } catch {
        Write-Log "VC++ install failed: $_" ERROR
        Add-Report ERROR "Visual C++" "FAILED - $_"
    }
}

function Select-PythonBranch {
    # Returns selected branch string e.g. "3.12"
    # Always shows top 5 from py list --online
    # Marks locally installed versions and current venv branch
    Write-Log "Fetching available Python versions..." STEP

    # Get top 5 available branches from online list (skip header)
    $onlineList = py list --online 2>&1 | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^\s*(3\.\d+)\[-64\]') { $Matches[1] }
    } | Select-Object -Unique | Select-Object -First 5

    if ($onlineList.Count -eq 0) {
        Write-Log "Could not retrieve Python version list." ERROR
        Add-Report ERROR "Python" "version list unavailable - aborted"
        return $null
    }

    # Get locally installed branches (skip header)
    $localList = py list 2>&1 | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^\s*(3\.\d+)\[-64\]') { $Matches[1] }
    } | Select-Object -Unique

    # Get current venv branch
    $currentBranch = Get-VenvPythonBranch

    Write-Host ""
    Write-Host "  Available Python versions:" -ForegroundColor White
    for ($i = 0; $i -lt $onlineList.Count; $i++) {
        $branch = $onlineList[$i]
        $label  = ""
        if ($branch -eq $currentBranch) {
            $label = " (local current)"
            $color = "Green"
        } elseif ($localList -contains $branch) {
            $label = " (local)"
            $color = "Cyan"
        } else {
            $color = "Gray"
        }
        Write-Host "    $($i+1)  Python $branch$label" -ForegroundColor $color
    }
    Write-Host ""

    do {
        $pick = Read-Host "  Select version (1-$($onlineList.Count))"
    } while ($pick -notmatch "^\d+$" -or [int]$pick -lt 1 -or [int]$pick -gt $onlineList.Count)

    $branch = $onlineList[[int]$pick - 1]

    # Install if not already present locally
    if ($localList -notcontains $branch) {
        Write-Log "Installing Python $branch..." STEP
        py install $branch 2>&1 | Out-Null
        Write-Log "Python $branch installed." OK
    }

    return $branch
}

function Install-Python {
    # Select from already-installed versions; returns branch string for use by caller
    $branch = Select-PythonBranch
    if (-not $branch) { return $null }

    $ver = (py -$branch --version 2>&1 | Out-String).Trim()
    Add-Report OK "Python" "$ver (branch $branch)"
    return $branch
}

function New-Venv {
    param([string]$Branch)
    Write-Log "Creating virtual environment (Python $Branch)..." STEP
    py -$Branch -m venv $DIR_VENV 2>&1 | Out-Null

    if (Test-Path "$DIR_VENV\Scripts\python.exe") {
        Add-Report OK "Venv" "created (Python $Branch)"
    } else {
        Write-Log "Venv creation failed" ERROR
        Add-Report ERROR "Venv" "creation FAILED"
    }
}

function Install-ComfyUI {
    if (Test-Path $DIR_COMFYUI) {
        Add-Report OK "ComfyUI" "folder already exists - skipped"
        return
    }
    Write-Log "Cloning ComfyUI..." STEP
    git clone https://github.com/Comfy-Org/ComfyUI.git --quiet
    if ($LASTEXITCODE -eq 0) {
        Add-Report OK "ComfyUI" "cloned"
    } else {
        Add-Report ERROR "ComfyUI" "clone FAILED (exit $LASTEXITCODE)"
    }
}

function Invoke-Install {
    Show-Header
    Write-Log "Starting fresh install..." STEP
    Write-Host ""

    Install-PyLauncher
    Install-Git
    Install-VCRedist

    $branch = Install-Python
    if (-not $branch) {
        Write-Log "Install aborted: no Python version selected." WARN
        return
    }

    New-Venv -Branch $branch
    Install-ComfyUI
    Update-Pip
}

#endregion INSTALL

# ==============================================================================

#region UPDATE

function Update-Git {
    Write-Log "Checking Git for updates..." STEP
    if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
        Write-Log "Git not found. Run Install first." WARN
        Add-Report WARN "Git" "not installed"
        return
    }
    try {
        $ghResp     = Invoke-WebRequest `
            -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
            -UseBasicParsing -ErrorAction Stop | ConvertFrom-Json
        $latestVer  = ($ghResp.tag_name -replace '^v', '' -split '\.windows')[0].Trim()
        $currentVer = ((git --version) -replace 'git version\s*', '' `
                        -split '\.windows')[0].Trim()

        if ((Compare-SemVer $latestVer $currentVer) -gt 0) {
            Write-Log "Updating Git $currentVer -> $latestVer..." STEP
            $asset = $ghResp.assets |
                     Where-Object { $_.name -like "Git-*-64-bit.exe" } |
                     Select-Object -First 1
            Invoke-WebRequest -Uri $asset.browser_download_url `
                -OutFile "$env:TEMP\git_setup.exe" -ErrorAction Stop
            Start-Process "$env:TEMP\git_setup.exe" -ArgumentList "/VERYSILENT /NORESTART" -Wait
            Remove-Item "$env:TEMP\git_setup.exe" -Force
            git config --system core.longpaths true
            Add-Report OK "Git" "updated $currentVer -> $latestVer"
        } else {
            Add-Report OK "Git" "$currentVer (up to date)"
        }
    } catch {
        Write-Log "Git update check failed: $_" ERROR
        Add-Report ERROR "Git" "update check FAILED - $_"
    }
}

function Update-PythonMinor {
    Write-Log "Checking Python minor updates..." STEP

    $branch = Get-VenvPythonBranch
    if (-not $branch) {
        Write-Log "Cannot determine Python branch: venv missing or pyvenv.cfg unreadable." WARN
        Add-Report WARN "Python" "branch unknown - skipped"
        return
    }

    $verBefore = (py -$branch --version 2>&1 | Out-String).Trim()
    py install $branch --update 2>&1 | Out-Null
    $verAfter  = (py -$branch --version 2>&1 | Out-String).Trim()

    if ($verBefore -ne $verAfter) {
        Add-Report OK "Python" "updated: $verBefore -> $verAfter"
    } else {
        Add-Report OK "Python" "$verAfter (up to date)"
    }
}

function Update-Pip {
    $venvPython = "$PSScriptRoot\$DIR_VENV\Scripts\python.exe"
    if (-not (Test-Path $venvPython)) {
        Add-Report WARN "Pip" "venv not found - skipped"
        return
    }
    Write-Log "Upgrading pip..." STEP
    & $venvPython -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    $pipVer = (& $venvPython -m pip --version 2>&1) -replace 'pip\s+(\S+).*', '$1'
    Add-Report OK "Pip" "$pipVer (up to date)"
}

function Invoke-Update {
    Show-Header
    Write-Log "Starting update..." STEP
    Write-Host ""

    Update-Git
    Update-PythonMinor
    Update-Pip

    Add-Report OK "ComfyUI" "not touched (update manually via git pull)"
    Add-Report OK "Venv" "not touched (pip packages unchanged)"
}

#endregion UPDATE

# ==============================================================================

#region SWAP

function Invoke-Swap {
    Show-Header
    Write-Log "Starting Python version swap..." STEP
    Write-Host ""

    # Remove old venv
    if (Test-Path $DIR_VENV) {
        Write-Log "Removing existing venv..." STEP
        Remove-Item $DIR_VENV -Recurse -Force
        Write-Log "Old venv removed" OK
    }

    # Pick a new branch from already-installed Python versions (no install/uninstall)
    $branch = Select-PythonBranch
    if (-not $branch) {
        Write-Log "Swap aborted: no Python version selected." WARN
        return
    }

    $ver = (py -$branch --version 2>&1 | Out-String).Trim()
    Add-Report OK "Python" "$ver (branch $branch)"

    # Create fresh venv under the selected version
    New-Venv -Branch $branch
    Update-Pip

    Add-Report OK "ComfyUI" "not touched"
    Write-Log "NOTE: all pip packages (torch, etc.) must be reinstalled in the new venv!" WARN
}

#endregion SWAP

# ==============================================================================

#region SUMMARY

function Show-Summary {
    Write-Host ""
    Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Summary" -ForegroundColor White
    Write-Host ""

    foreach ($entry in $script:Report) {
        $color = switch ($entry.Level) {
            'OK'      { 'Green'   }
            'WARN'    { 'Yellow'  }
            'ERROR'   { 'Red'     }
            'SUCCESS' { 'Green'   }
            default   { 'Cyan'    }
        }
        Write-Host "  $($entry.Prefix) $($entry.Component) $($entry.Message)" -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  -----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

#endregion SUMMARY

# ==============================================================================

#region MAIN

$choice = Show-Menu

switch ($choice) {
    '1' { Invoke-Install  }
    '2' { Invoke-Update   }
    '3' { Invoke-Swap     }
    '0' { exit }
}

Show-Summary
pause

#endregion MAIN
