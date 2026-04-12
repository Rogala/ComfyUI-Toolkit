# ==============================================================================
# ComfyUI Toolkit — comfyui.ps1
# Requires: start_comfyui.bat (bootstrapper)
# ==============================================================================
# Regions:
#   CONFIG   — paths, launch modes, behaviour flags
#   I18N     — translation table, language helpers
#   INIT     — cache layout, smart_fixer.py deployment, startup jobs
#   UI       — Write-Log, Show-Header, menu primitives
#   LAUNCHER — ComfyUI launch, venv console, help
#   INSTALL  — Python Manager, Git, VC++, venv, ComfyUI clone  [admin]
#   MANAGER  — Torch stack, ComfyUI version, Repair, Info
#   MAIN     — entry point, main loop, routing
# ==============================================================================

#region CONFIG
# ------------------------------------------------------------------------------

# --- Paths (relative to script location) ---
param(
    [string]$Mode = ""
)

$DIR_VENV    = "venv"
$DIR_COMFYUI = "ComfyUI"
$DIR_OUTPUT  = "output"
$DIR_CACHE   = ".cache"

# --- Language ---
# 'auto' = detect from system locale (Get-Culture)
# Explicit codes: 'en' 'uk'
$LANG_DEFAULT = 'auto'

# --- ComfyUI launch arguments applied to ALL modes ---
# Add any flags that should always be active:
#   --listen              allow connections from other devices on the network
#   --reserve-vram 0.5    keep 0.5 GB VRAM free for the OS
#   --enable-manager      load ComfyUI-Manager on startup
#   --lowvram             for GPUs with limited VRAM
#   --preview-method auto latent previews during generation
#
$COMMON_ARGS = @("--output-directory", ".\$DIR_OUTPUT")

# --- Launch modes shown in the menu ---
# To add a custom mode — append one hashtable here.
# Key   : single character, must not conflict with E U S T V R I C M H L 0
# Label : key in $T (i18n), or a plain string fallback
# Desc  : key in $T (i18n), or a plain string fallback
# Args  : extra arguments appended to $COMMON_ARGS
#
$LAUNCH_MODES = @(
    @{ Key="1"; LabelKey="menu.normal.label"; DescKey="menu.normal.desc"; Args=@() }
    @{ Key="2"; LabelKey="menu.fast.label";   DescKey="menu.fast.desc";   Args=@("--fast") }
    # @{ Key="3"; LabelKey="menu.lowvram.label"; DescKey="menu.lowvram.desc"; Args=@("--lowvram") }
)

# --- Behaviour ---
$MENU_TIMEOUT_SEC  = 300    # idle seconds before auto-return to menu (0 = disabled)
$UPDATE_CHECK      = $true  # check GitHub for new ComfyUI release on startup (async)

#endregion CONFIG

# ==============================================================================

#region I18N
# ------------------------------------------------------------------------------
# Translation table.
# Keys used via: t 'key'  →  returns string in current language.
# Technical log lines ([OK]/[WARN]/[ERROR]/[STEP]) are always English.
# ------------------------------------------------------------------------------

$script:LangCycle = @('en','uk')

$T = @{
  'app.title'            = @{ en='ComfyUI Launcher';                    uk='ComfyUI Launcher'                    }
  'header.update'        = @{ en='Update available';                    uk='Доступне оновлення'                  }
  'section.launch'       = @{ en='Launch';                              uk='Запуск'                              }
  'section.env'          = @{ en='Environment';                         uk='Середовище'                          }
  'section.packages'     = @{ en='Packages';                            uk='Пакети'                              }
  'section.tools'        = @{ en='Tools';                               uk='Інструменти'                         }
  'menu.normal.label'    = @{ en='Normal';                              uk='Звичайний'                           }
  'menu.normal.desc'     = @{ en='Standard launch';                     uk='Стандартний запуск'                  }
  'menu.fast.label'      = @{ en='Fast';                                uk='Швидкий'                             }
  'menu.fast.desc'       = @{ en='Experimental optimizations';          uk='Експериментальні оптимізації'        }
  'menu.install.label'   = @{ en='Install';                             uk='Встановлення'                        }
  'menu.install.desc'    = @{ en='Python Manager, Git, VC++, venv, ComfyUI'; uk='Python Manager, Git, VC++, venv, ComfyUI' }
  'menu.update.label'    = @{ en='Update';                              uk='Оновлення'                           }
  'menu.update.desc'     = @{ en='Git, Python minor, pip';              uk='Git, Python minor, pip'              }
  'menu.swap.label'      = @{ en='Swap Python';                         uk='Swap Python'                         }
  'menu.swap.desc'       = @{ en='Change Python version, recreate venv'; uk='Змінити версію Python, перестворити venv' }
  'menu.torch.label'     = @{ en='Torch';                               uk='Torch'                               }
  'menu.torch.desc'      = @{ en='Change CUDA / PyTorch version';       uk='Змінити CUDA / версію PyTorch'       }
  'menu.comfy.label'     = @{ en='ComfyUI';                             uk='ComfyUI'                             }
  'menu.comfy.desc'      = @{ en='Switch tag / version';                uk='Переключити тег / версію'            }
  'menu.repair.label'    = @{ en='Repair';                              uk='Ремонт'                              }
  'menu.repair.desc'     = @{ en='Auto dependency fix';                 uk='Авторемонт залежностей'              }
  'menu.info.label'      = @{ en='Info';                                uk='Інфо'                                }
  'menu.info.desc'       = @{ en='Environment snapshot';                uk='Знімок середовища'                   }
  'menu.console.label'   = @{ en='Console';                             uk='Консоль'                             }
  'menu.console.desc'    = @{ en='venv shell (manual pip)';             uk='venv консоль (pip вручну)'           }
  'menu.manager.label'   = @{ en='ComfyUI-Manager';                     uk='ComfyUI-Manager'                     }
  'menu.manager.desc'    = @{ en='Install plugin';                      uk='Встановити плагін'                   }
  'menu.help.label'      = @{ en='Help';                                uk='Довідка'                             }
  'menu.help.desc'       = @{ en='ComfyUI --help';                      uk='ComfyUI --help'                      }
  'menu.exit.label'      = @{ en='Exit';                                uk='Вийти'                               }
  'prompt.anykey'        = @{ en='Press any key to return...';          uk='Будь-яка клавіша — повернутись...'  }
  'prompt.confirm.yes'   = @{ en='Yes';                                 uk='Так'                                 }
  'prompt.confirm.no'    = @{ en='No';                                  uk='Ні'                                  }
  'status.first.run'     = @{ en='First run — venv not found';          uk='Перший запуск — venv не знайдено'   }
  'status.setup.prompt'  = @{ en='Launch environment setup now?';       uk='Запустити налаштування зараз?'      }
  'status.admin.note'    = @{ en='Requires administrator rights';       uk='Потребує прав адміністратора'        }
  'lang.name'            = @{ en='English';                             uk='Українська'                          }
  'lang.hint'            = @{ en='Press [L] to change language';        uk='Щоб змінити мову натисни [L]'       }
}

# Language resolution — called once in INIT, result stored in $script:Lang
function Resolve-Language {
    param([string]$Pref)
    if ($Pref -ne 'auto') {
        if ($script:LangCycle -contains $Pref) { return $Pref }
        return 'en'
    }
    $detected = (Get-Culture).Name.Split('-')[0].ToLower()
    if ($script:LangCycle -contains $detected) { return $detected }
    return 'en'
}

# Translate key — returns string in current language, falls back to English
function t([string]$key) {
    if (-not $T.ContainsKey($key)) { return $key }
    $row = $T[$key]
    if ($row.ContainsKey($script:Lang)) { return $row[$script:Lang] }
    if ($row.ContainsKey('en'))         { return $row['en'] }
    return $key
}

# Cycle to next language and persist
function Switch-Language {
    $idx = $script:LangCycle.IndexOf($script:Lang)
    $script:Lang = $script:LangCycle[($idx + 1) % $script:LangCycle.Count]
    Save-Settings
}

#endregion I18N

# ==============================================================================

#region INIT
# ------------------------------------------------------------------------------

# --- Derived paths (set after $PSScriptRoot is available) ---
$script:Root         = $PSScriptRoot
$script:VenvPython   = Join-Path $script:Root "$DIR_VENV\Scripts\python.exe"
$script:VenvActivate = Join-Path $script:Root "$DIR_VENV\Scripts\Activate.ps1"
$script:MainPy       = Join-Path $script:Root "$DIR_COMFYUI\main.py"
$script:CacheDir     = Join-Path $script:Root $DIR_CACHE
$script:ConstFile    = Join-Path $script:CacheDir "const.txt"
$script:SettingsFile = Join-Path $script:CacheDir "settings.json"
$script:SmartFixer   = Join-Path $script:CacheDir "smart_fixer.py"
$script:EnvLog       = Join-Path $script:CacheDir "env_state.log"
$script:HistoryLog   = Join-Path $script:CacheDir "history.log"

# --- Runtime state ---
$script:Lang         = 'en'   # set by Resolve-Language in Initialize
$script:TorchVer     = $null  # cached at startup
$script:ComfyTag     = $null  # cached at startup
$script:LatestTag    = $null  # filled by background update-check job
$script:UpdateJob    = $null  # Start-Job handle

# --- Settings (persisted to .cache/settings.json) ---
function Load-Settings {
    if (Test-Path $script:SettingsFile) {
        try {
            $s = Get-Content $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($s.lang) { return $s.lang }
        } catch {}
    }
    return $LANG_DEFAULT
}

function Save-Settings {
    try {
        @{ lang = $script:Lang } | ConvertTo-Json | Set-Content $script:SettingsFile -Encoding UTF8
    } catch {}
}

# --- Cache directory layout ---
function Initialize-Cache {
    # Create .cache and subdirs if missing
    if (-not (Test-Path $script:CacheDir)) {
        New-Item $script:CacheDir -ItemType Directory -Force | Out-Null
    }

    # Deploy smart_fixer.py from embedded here-string
    # Redeploys if file is missing; existing file is preserved (may be newer patched version)
    if (-not (Test-Path $script:SmartFixer)) {
        Write-Log "Deploying smart_fixer.py to .cache..." INFO
        $smartFixerSource = @'
﻿# =============================================================================
# smart_fixer.py — Auto Dependency Guard
# Part of: ComfyUI Toolkit
# Location: .cache/smart_fixer.py  (deployed automatically on startup)
#
# Usage: python smart_fixer.py <venv_python> <comfy_dir> <cache_dir>
#
# Logic:
#   1. Reads CHECK_LIST dynamically from ComfyUI requirements.txt
#   2. Imports each package in a subprocess, captures stderr
#   3. If DependencyWarning detected — parses conflicting package + version
#   4. Installs a satisfying version of the conflicting package
#   5. Retries import (up to MAX_FIX_ITERATIONS per package)
#   6. If all clean — writes stable versions to const.txt
#   7. Protected packages (torch stack) are NEVER modified
# =============================================================================

import subprocess
import sys
import re
import os

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

VENV_PYTHON = sys.argv[1]
COMFY_DIR   = sys.argv[2]
CACHE_DIR   = sys.argv[3]

CONST_FILE  = os.path.join(CACHE_DIR, "const.txt")
REQ_FILE    = os.path.join(COMFY_DIR, "requirements.txt")

# These packages are never touched — managed exclusively by Torch management
PROTECTED = {"torch", "torchvision", "torchaudio", "torchsde", "comfyui-workflow-templates"}

# Import name aliases — pip name != importable name for some packages
IMPORT_ALIASES = {
    "pillow":          "PIL",
    "pyyaml":          "yaml",
    "opencv-python":   "cv2",
    "scikit-learn":    "sklearn",
}

MAX_FIX_ITERATIONS = 5


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def pip(args):
    """Run a pip command using the venv Python and return CompletedProcess."""
    return subprocess.run(
        [VENV_PYTHON, "-m", "pip"] + args,
        capture_output=True, text=True
    )


def get_installed_version(pkg):
    """Return installed version string for a package, or None."""
    r = pip(["show", pkg])
    m = re.search(r"Version:\s*([\d\.]+)", r.stdout)
    return m.group(1) if m else None


def get_package_requires(pkg):
    """
    Returns dict of {dep_name: version_spec} from pip show Requires-Dist.
    Used to find what version of a dependency a package actually needs.
    """
    r = pip(["show", pkg])
    requires = {}
    for line in r.stdout.splitlines():
        if line.startswith("Requires-Dist:"):
            dep = line.replace("Requires-Dist:", "").strip()
            # Strip environment markers (e.g. '; python_version >= "3.8"')
            dep = dep.split(";")[0].strip()
            m = re.match(r"([\w\-]+)\s*([><=!].*)?", dep)
            if m:
                name = m.group(1).lower()
                spec = m.group(2).strip() if m.group(2) else ""
                requires[name] = spec
    return requires


def get_check_list():
    """
    Build the list of packages to check from ComfyUI requirements.txt.
    Skips comments, blank lines, and the protected torch stack.
    """
    if not os.path.exists(REQ_FILE):
        return []
    pkgs = []
    with open(REQ_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name = re.split(r"[>=<!]", line)[0].strip().lower()
            if name and name not in PROTECTED:
                pkgs.append(name)
    return pkgs


def check_import(pkg_name):
    """
    Run 'import <pkg>' in a subprocess with all warnings enabled.
    Uses IMPORT_ALIASES for packages whose import name differs from pip name.
    Returns (stderr: str, returncode: int).
    """
    import_name = IMPORT_ALIASES.get(pkg_name.lower(), pkg_name.replace("-", "_"))
    r = subprocess.run(
        [VENV_PYTHON, "-W", "all", "-c", f"import {import_name}"],
        capture_output=True, text=True
    )
    # Filter out irrelevant DeprecationWarnings from C extensions
    stderr = "\n".join(l for l in r.stderr.splitlines()
                       if "SwigPy" not in l and "swigvarlink" not in l and "frozen importlib" not in l)
    return stderr, r.returncode


def parse_conflict(stderr):
    """
    Extract conflicting dependency requirements from pip check or warning text.
    Primary source: pip check output (stable, machine-readable format).
    Fallback: DependencyWarning patterns from import stderr.
    Returns dict {dep_name: version_spec} or None.
    Protected packages are always excluded.
    """
    results = {}

    # pip check format (most reliable):
    # "requests 2.32.3 has requirement urllib3<3,>=1.21.1, but you have urllib3 3.0.0."
    pip_check_pattern = r"^\S+ [\d\.]+ has requirement (\S+?)((?:[><=!]+[\d\.]+)+(?:,(?:[><=!]+[\d\.]+))*)?, but you"
    for m in re.finditer(pip_check_pattern, stderr, re.MULTILINE | re.IGNORECASE):
        dep_name = m.group(1).lower()
        dep_spec = m.group(2) or ""
        if dep_name not in PROTECTED:
            results[dep_name] = dep_spec.strip()

    # "package X.Y requires dep, which is not installed"
    missing_pattern = r"^(\S+) [\d\.]+ requires ([\w\-]+), which is not installed"
    for m in re.finditer(missing_pattern, stderr, re.MULTILINE | re.IGNORECASE):
        parent_name = m.group(1).lower()
        dep_name = m.group(2).lower()
        if parent_name in PROTECTED:
            continue
        if dep_name not in PROTECTED and dep_name not in results:
            # Extract required version from the spec if present in the line
            ver_match = re.search(r'==([^\s,]+)', m.group(0))
            results[dep_name] = f"=={ver_match.group(1)}" if ver_match else ""

    # Fallback: import -W all DependencyWarning patterns
    if not results:
        patterns = [
            r"[\w\-]+ [\d\.]+ requires ([\w\-]+)([><=!]+[\d\.]+(?:,\s*[><=!]+[\d\.]+)?)",
            r"requires ([\w\-]+)\s+([><=!]+[\d\.]+)",
        ]
        for pattern in patterns:
            for m in re.finditer(pattern, stderr, re.IGNORECASE):
                dep_name = m.group(1).lower()
                dep_spec = m.group(2).strip() if m.group(2) else ""
                if dep_name not in PROTECTED:
                    results[dep_name] = dep_spec

    # RequestsDependencyWarning special case
    if "doesn't match a supported version" in stderr:
        rdw_pkgs = re.findall(r"([\w\-]+)\s+\([\d\.]+\)", stderr)
        for p in rdw_pkgs:
            p_lower = p.lower()
            if p_lower not in PROTECTED and p_lower not in results:
                results[p_lower] = ""

    return results if results else None


def resolve_version(pkg, spec):
    """
    Find the latest available version of pkg that satisfies spec.
    Falls back to plain package name if resolution fails.
    """
    r = pip(["index", "versions", pkg])
    m = re.search(r"Available versions:\s*(.+)", r.stdout)
    if not m:
        return pkg

    raw_versions = [v.strip() for v in m.group(1).split(",")]
    versions = [v for v in raw_versions if re.match(r"^\d+\.\d+\.?\d*$", v.strip())]
    conditions = re.findall(r"([><=!]+)([\d\.]+)", spec)

    def satisfies(ver_str):
        try:
            from packaging.version import Version
            v = Version(ver_str)
            for op, req in conditions:
                rv = Version(req)
                if op == ">=" and not (v >= rv): return False
                if op == "<=" and not (v <= rv): return False
                if op == ">"  and not (v >  rv): return False
                if op == "<"  and not (v <  rv): return False
                if op == "==" and not (v == rv): return False
                if op == "!=" and not (v != rv): return False
        except Exception:
            return False
        return True

    for ver in versions:
        if satisfies(ver):
            return f"{pkg}=={ver}"

    return pkg


def write_const(check_list):
    """Write a stable dependency snapshot to const.txt."""
    lines = []

    for pkg in ["torch", "torchvision", "torchaudio", "torchsde"]:
        v = get_installed_version(pkg)
        if v:
            lines.append(f"{pkg}=={v}  # protected — managed by Torch Stack")

    for pkg in check_list:
        v = get_installed_version(pkg)
        if v:
            lines.append(f"{pkg}=={v}")

    from datetime import datetime
    header = (
        "# ComfyUI Toolkit — Stable Dependency Snapshot\n"
        f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        "# DO NOT EDIT MANUALLY — regenerated after each repair.\n\n"
    )

    with open(CONST_FILE, "w", encoding="utf-8") as f:
        f.write(header)
        f.write("\n".join(lines))

    print(f"[CONST] Stable snapshot saved to const.txt ({len(lines)} packages)")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("[SMART FIXER] Starting Auto Dependency Guard...")

    # Run pip check first — most reliable source of conflict info
    pip_check = subprocess.run(
        [VENV_PYTHON, "-m", "pip", "check"],
        capture_output=True, text=True
    )

    check_list = get_check_list()
    if not check_list:
        print("[WARN] requirements.txt not found or empty. Nothing to check.")
        return 0

    print(f"[INFO] Checking {len(check_list)} package(s) from ComfyUI requirements.txt...")

    # If pip check is already clean — skip import loop
    # Filter out known false positives (torch CUDA local version suffix)
    pip_check_lines = [
        l for l in pip_check.stdout.splitlines()
        if l and not any(x in l for x in [
            "requires torch", "requires torchvision",
            "requires torchaudio", "requires torchsde",
            "No broken requirements"
        ])
    ]

    if pip_check.returncode == 0 and not pip_check_lines:
        print("[OK] pip check: no conflicts found.")
        write_const(check_list)
        return 0

    failed_packages  = []
    fixed_packages   = []
    skipped_packages = []

    for pkg in check_list:
        stderr, returncode = check_import(pkg)

        if returncode != 0 and "ModuleNotFoundError" in stderr:
            skipped_packages.append(pkg)
            continue

        # Also inject pip check output for this package as additional signal
        pkg_pip_lines = [l for l in pip_check_lines if pkg.lower() in l.lower()]
        if pkg_pip_lines:
            stderr = stderr + "\n" + "\n".join(pkg_pip_lines)

        if "warning" not in stderr.lower() and not pkg_pip_lines:
            continue

        print(f"\n[!] Conflict detected in: {pkg}")

        fixed = False
        for attempt in range(1, MAX_FIX_ITERATIONS + 1):
            conflicts = parse_conflict(stderr)
            if not conflicts:
                # No recognisable conflict pattern — check if warnings still present
                if "warning" not in stderr.lower() and not pkg_pip_lines:
                    fixed = True
                else:
                    print(f"    [WARN] Unrecognized warning format — cannot auto-fix")
                break

            print(f"    Attempt {attempt}/{MAX_FIX_ITERATIONS}: {conflicts}")

            for dep_pkg, dep_spec in conflicts.items():
                if dep_pkg in PROTECTED:
                    print(f"    [SKIP] {dep_pkg} is protected (torch stack)")
                    continue

                if dep_spec:
                    install_target = resolve_version(dep_pkg, dep_spec)
                else:
                    parent_req = get_package_requires(pkg)
                    if dep_pkg in parent_req and parent_req[dep_pkg]:
                        install_target = resolve_version(dep_pkg, parent_req[dep_pkg])
                        print(f"    [INFO] {pkg} requires {dep_pkg}{parent_req[dep_pkg]}")
                    else:
                        install_target = dep_pkg

                print(f"    [FIX] Installing: {install_target}")
                pip(["install", install_target, "--prefer-binary", "--quiet"])

            stderr, returncode = check_import(pkg)
            # Re-run pip check for this package
            recheck = subprocess.run(
                [VENV_PYTHON, "-m", "pip", "check"],
                capture_output=True, text=True
            )
            pkg_pip_lines = [l for l in recheck.stdout.splitlines()
                             if pkg.lower() in l.lower() and
                             not any(x in l for x in ["requires torch","requires torchvision","requires torchaudio","requires torchsde"])]
            if "warning" not in stderr.lower() and not pkg_pip_lines:
                fixed = True
                break

        if fixed:
            print(f"    [OK] {pkg} resolved successfully.")
            fixed_packages.append(pkg)
        else:
            print(f"    [FAIL] Could not resolve {pkg} after {MAX_FIX_ITERATIONS} attempt(s).")
            failed_packages.append(pkg)

    print(f"\n[SUMMARY]")
    print(f"  Fixed:   {len(fixed_packages)} package(s): {', '.join(fixed_packages) or 'none'}")
    print(f"  Failed:  {len(failed_packages)} package(s): {', '.join(failed_packages) or 'none'}")
    print(f"  Skipped: {len(skipped_packages)} package(s) (ModuleNotFoundError)")

    if failed_packages:
        print(f"\n[WARN] Unresolved conflicts: {', '.join(failed_packages)}")
        print(f"[WARN] This may be caused by an incompatible custom node.")
        print(f"[WARN] const.txt will NOT be updated until all conflicts are resolved.")
        return 1

    write_const(check_list)
    return 0


if __name__ == "__main__":
    sys.exit(main())

'@
        try {
            [System.IO.File]::WriteAllText($script:SmartFixer, $smartFixerSource, [System.Text.UTF8Encoding]::new($false))
            Write-Log "smart_fixer.py deployed to .cache" OK
        } catch {
            Write-Log "Failed to deploy smart_fixer.py: $_" WARN
        }
    }
}

# --- Startup cache of slow values ---
function Initialize-RuntimeCache {
    # Python version — subprocess, most accurate
    if (Test-Path $script:VenvPython) {
        try {
            $raw = & $script:VenvPython --version 2>&1 | Out-String
            # "Python 3.12.10" -> "3.12.10"
            if ($raw -match 'Python\s+([\d\.]+)') {
                $script:PythonVer = $Matches[1]
            }
        } catch { $script:PythonVer = $null }
    } else { $script:PythonVer = $null }

    # PyTorch version
    if (Test-Path $script:VenvPython) {
        try {
            $tv = & $script:VenvPython -c "import torch; print(torch.__version__)" 2>$null
            $script:TorchVer = if ($tv) { $tv.Trim() } else { $null }
        } catch { $script:TorchVer = $null }
    } else { $script:TorchVer = $null }

    # ComfyUI git tag
    $comfyPath = Join-Path $script:Root $DIR_COMFYUI
    if (Test-Path $comfyPath) {
        Push-Location $comfyPath
        try {
            $tag = git describe --tags --abbrev=0 2>$null
            $script:ComfyTag = if ($tag) { $tag.Trim() } else { $null }
        } catch { $script:ComfyTag = $null }
        Pop-Location
    } else { $script:ComfyTag = $null }
}

# --- Async update check ---
function Start-UpdateCheck {
    if (-not $UPDATE_CHECK) { return }
    $script:UpdateJob = Start-Job -ScriptBlock {
        try {
            $r = Invoke-RestMethod `
                'https://api.github.com/repos/Comfy-Org/ComfyUI/releases/latest' `
                -TimeoutSec 8 -ErrorAction Stop
            return $r.tag_name
        } catch { return $null }
    }
}

function Poll-UpdateJob {
    if (-not $script:UpdateJob) { return }
    if ($script:UpdateJob.State -eq 'Completed') {
        $script:LatestTag = Receive-Job $script:UpdateJob
        Remove-Job $script:UpdateJob -Force
        $script:UpdateJob = $null
    }
}

# --- File logger ---
function Write-FileLog([string]$msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $msg"
    $line | Add-Content $script:HistoryLog -Encoding UTF8
    # Rotate: keep last 500 lines if file exceeds 50 KB
    if ((Get-Item $script:HistoryLog -ErrorAction SilentlyContinue).Length -gt 50KB) {
        $lines = Get-Content $script:HistoryLog -Encoding UTF8
        if ($lines.Count -gt 500) {
            $lines | Select-Object -Last 500 | Set-Content $script:HistoryLog -Encoding UTF8
        }
    }
}

#endregion INIT

# ==============================================================================

#region UI
# ------------------------------------------------------------------------------

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('OK','WARN','ERROR','STEP','PROCESS','INFO','SUCCESS')]
        [string]$Level = 'INFO'
    )
    $prefix, $color = switch ($Level) {
        'OK'      { '[OK]',      'Green'    }
        'WARN'    { '[WARN]',    'Yellow'   }
        'ERROR'   { '[ERROR]',   'Red'      }
        'STEP'    { '[STEP]',    'Cyan'     }
        'PROCESS' { '[PROCESS]', 'Yellow'   }
        'SUCCESS' { '[SUCCESS]', 'Green'    }
        default   { '[INFO]',    'DarkGray' }
    }
    Write-Host "$prefix $Message" -ForegroundColor $color
}

function Write-Div {
    param([string]$Color = 'DarkGray')
    Write-Host ("  " + "─" * 54) -ForegroundColor $Color
}

function Show-Header {
    Poll-UpdateJob

    Clear-Host
    Write-Host ""

    # --- Title line ---
    $langBadge = "[$($script:Lang.ToUpper())]"
    $titleLine = "    $(t 'app.title')"
    $pad = " " * ([Math]::Max(1, 60 - $titleLine.Length - $langBadge.Length))
    $divider = "  " + "=" * 62

    Write-Host $divider -ForegroundColor DarkCyan
    Write-Host "$titleLine$pad$langBadge" -ForegroundColor Cyan
    Write-Host $divider -ForegroundColor DarkCyan
    Write-Host ""

    # --- Status badges ---
    Write-Host "  " -NoNewline
    if ($script:PythonVer) {
        Write-Host " Python $($script:PythonVer) " -NoNewline -ForegroundColor Black -BackgroundColor DarkGreen
    } else {
        Write-Host " Python — " -NoNewline -ForegroundColor White -BackgroundColor DarkRed
    }
    Write-Host "   " -NoNewline
    if ($script:ComfyTag) {
        Write-Host " ComfyUI $($script:ComfyTag) " -NoNewline -ForegroundColor Black -BackgroundColor DarkGreen
    } else {
        Write-Host " ComfyUI — " -NoNewline -ForegroundColor White -BackgroundColor DarkRed
    }
    Write-Host "   " -NoNewline
    if ($script:TorchVer) {
        Write-Host " PyTorch $($script:TorchVer) " -ForegroundColor Black -BackgroundColor DarkCyan
    } else {
        Write-Host " PyTorch — " -ForegroundColor White -BackgroundColor DarkRed
    }
    Write-Host ""

    # --- Update badge ---
    if ($script:LatestTag -and $script:ComfyTag) {
        try { $showUpdate = [version]($script:LatestTag -replace "v","") -gt [version]($script:ComfyTag -replace "v","") } catch { $showUpdate = $false }
        if ($showUpdate) {
        Write-Host ""
        Write-Host "  " -NoNewline
        Write-Host " * $(t 'header.update'): $($script:LatestTag) " -ForegroundColor Yellow
    }
        }

    Write-Host ""
    Write-Host "  $(t 'lang.hint') Language (EN UK)" -ForegroundColor DarkGray
    Write-Host ""
}

# --- Menu section header ---
function Write-Section([string]$labelKey) {
    Write-Div
    Write-Host "  $(t $labelKey)" -ForegroundColor Gray
    Write-Div
}

# --- Single menu item ---
function Write-MenuItem {
    param([string]$Key, [string]$Label, [string]$Desc, [string]$KeyColor = 'Cyan', [switch]$AdminBadge)
    Write-Host "  [" -NoNewline -ForegroundColor DarkGray
    Write-Host $Key  -NoNewline -ForegroundColor $KeyColor
    Write-Host "] "  -NoNewline -ForegroundColor DarkGray
    Write-Host $Label.PadRight(18) -NoNewline -ForegroundColor White
    if ($AdminBadge) {
        Write-Host "[A] " -NoNewline -ForegroundColor DarkYellow
    }
    Write-Host $Desc -ForegroundColor DarkGray
}

# --- Input primitives ---
function Read-Key {
    $k = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $vk = $k.VirtualKeyCode
    if ($vk -ge 65 -and $vk -le 90) { return [char]$vk -as [string] }
    if ($vk -ge 48 -and $vk -le 57) { return [char]$vk -as [string] }
    return $k.Character.ToString().ToUpper()
}

function Wait-Key {
    param([string]$Msg)
    if (-not $Msg) { $Msg = t 'prompt.anykey' }
    Write-Host ""
    Write-Host "  $Msg" -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function Confirm-Action {
    param([string]$Prompt)
    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor White
    Write-Host "  [Y] $(t 'prompt.confirm.yes')   [N] $(t 'prompt.confirm.no')" -ForegroundColor DarkGray
    do { $k = Read-Key } while ($k -notin @('Y','N'))
    return $k -eq 'Y'
}

# --- Main menu ---
function Show-Menu {
    Show-Header

    # Launch modes (dynamic from $LAUNCH_MODES)
    Write-Section 'section.launch'
    foreach ($mode in $LAUNCH_MODES) {
        $label = if ($T.ContainsKey($mode.LabelKey)) { t $mode.LabelKey } else { $mode.LabelKey }
        $desc  = if ($T.ContainsKey($mode.DescKey))  { t $mode.DescKey  } else { $mode.DescKey  }
        Write-MenuItem -Key $mode.Key -Label $label -Desc $desc
    }

    # Environment
    Write-Host ""
    Write-Section 'section.env'
    Write-MenuItem 'E' (t 'menu.install.label') (t 'menu.install.desc') -AdminBadge
    Write-MenuItem 'U' (t 'menu.update.label')  (t 'menu.update.desc')
    Write-MenuItem 'S' (t 'menu.swap.label')    (t 'menu.swap.desc')

    # Packages
    Write-Host ""
    Write-Section 'section.packages'
    Write-MenuItem 'T' (t 'menu.torch.label')   (t 'menu.torch.desc')
    Write-MenuItem 'V' (t 'menu.comfy.label')   (t 'menu.comfy.desc')
    Write-MenuItem 'R' (t 'menu.repair.label')  (t 'menu.repair.desc')

    # Tools
    Write-Host ""
    Write-Section 'section.tools'
    Write-MenuItem 'I' (t 'menu.info.label')    (t 'menu.info.desc')
    Write-MenuItem 'C' (t 'menu.console.label') (t 'menu.console.desc')
    Write-MenuItem 'M' (t 'menu.manager.label') (t 'menu.manager.desc')
    Write-MenuItem 'H' (t 'menu.help.label')    (t 'menu.help.desc')

    Write-Host ""
    Write-Div
    Write-MenuItem 'L' "Language / Мова" "$($script:Lang.ToUpper()) → next" 'DarkGray'
    Write-MenuItem '0' (t 'menu.exit.label') '' 'Red'
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host (t 'prompt.anykey' | ForEach-Object { $_ -replace 'return\.\.\.','key...' }) -ForegroundColor DarkGray
    Write-Host "  $(t 'status.admin.note') = [A]" -ForegroundColor DarkGray
    Write-Host ""
}

#endregion UI

# ==============================================================================

#region LAUNCHER
# ------------------------------------------------------------------------------

function Invoke-ComfyUI {
    param([hashtable]$Mode)

    Show-Header
    Write-Div 'Cyan'
    $label   = if ($T.ContainsKey($Mode.LabelKey)) { t $Mode.LabelKey } else { $Mode.LabelKey }
    $allArgs = $COMMON_ARGS + $Mode.Args
    Write-Host "  $(t 'section.launch'): " -NoNewline -ForegroundColor DarkGray
    Write-Host $label -ForegroundColor White
    Write-Host "  Args: $($allArgs -join ' ')" -ForegroundColor DarkGray
    Write-Div 'Cyan'
    Write-Host ""

    if (-not (Test-Path $script:MainPy)) {
        Write-Log "ComfyUI not found: $($script:MainPy)" ERROR
        Wait-Key; return
    }

    # Ensure output directory exists
    $outPath = Join-Path $script:Root $DIR_OUTPUT
    if (-not (Test-Path $outPath)) {
        New-Item $outPath -ItemType Directory -Force | Out-Null
        Write-Log "Output directory created: $DIR_OUTPUT" OK
    }

    if (Test-Path $script:VenvActivate) { & $script:VenvActivate }
    & $script:VenvPython $script:MainPy @allArgs

    Write-Log "ComfyUI exited." INFO
    # Refresh cached values after ComfyUI run (may have updated packages)
    Initialize-RuntimeCache
    Wait-Key
}

function Open-VenvConsole {
    Show-Header
    Write-Host "  $(t 'menu.console.label')" -ForegroundColor White
    Write-Div
    Write-Host ""
    Write-Host "  venv is active — all pip commands install into venv only." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  pip list                    list installed packages"   -ForegroundColor DarkGray
    Write-Host "  pip install <package>       install a package"         -ForegroundColor DarkGray
    Write-Host "  pip uninstall <package>     remove a package"          -ForegroundColor DarkGray
    Write-Host "  pip install --upgrade <p>   upgrade a package"         -ForegroundColor DarkGray
    Write-Host "  python --version            show Python version"       -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  Type " -NoNewline -ForegroundColor DarkGray
    Write-Host "exit" -NoNewline -ForegroundColor Yellow
    Write-Host " and press Enter to return." -ForegroundColor DarkGray
    Write-Div
    Write-Host ""

    if (-not (Test-Path $script:VenvActivate)) {
        Write-Log "venv not found." ERROR; Wait-Key; return
    }

    $activateCmd = ". '$($script:VenvActivate)'"
    if (Test-Path $script:ConstFile) {
        $activateCmd += "; Write-Host '  [INFO] pip-safe available: pip install <pkg> -c .cache\const.txt' -ForegroundColor DarkGray"
    }
    powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command $activateCmd
}

function Show-ComfyHelp {
    Show-Header
    Write-Log "ComfyUI --help" STEP
    Write-Host ""
    if (Test-Path $script:VenvActivate) { & $script:VenvActivate }
    & $script:VenvPython $script:MainPy --help 2>&1
    Wait-Key
}

function Install-ComfyUIManager {
    Show-Header
    Write-Host "  $(t 'menu.manager.label')" -ForegroundColor White
    Write-Div
    Write-Host ""

    $comfyPath   = Join-Path $script:Root $DIR_COMFYUI
    $nodesPath   = Join-Path $comfyPath "custom_nodes"
    $managerPath = Join-Path $nodesPath "ComfyUI-Manager"

    if (-not (Test-Path $comfyPath)) {
        Write-Log "ComfyUI directory not found." ERROR
        Write-Log "Run [E] Install first." INFO
        Wait-Key; return
    }

    if (Test-Path $managerPath) {
        Write-Log "ComfyUI-Manager is already installed." OK
        Write-Host "  Location: $managerPath" -ForegroundColor DarkGray
        Wait-Key; return
    }

    if (-not (Test-Path $nodesPath)) {
        New-Item $nodesPath -ItemType Directory -Force | Out-Null
    }

    Write-Log "Cloning ComfyUI-Manager..." PROCESS
    git clone https://github.com/Comfy-Org/ComfyUI-Manager.git $managerPath --quiet

    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $managerPath)) {
        Write-Log "Clone failed. Check internet connection and git." ERROR
    } else {
        Write-Log "ComfyUI-Manager installed successfully." SUCCESS
        Write-FileLog "ComfyUI-Manager installed"
    }
    Wait-Key
}

#endregion LAUNCHER

# ==============================================================================

#region INSTALL
# ------------------------------------------------------------------------------
# Functions that require administrator rights are called in an elevated
# subprocess via Start-Process -Verb RunAs.
# Only three operations need admin:
#   - Install-PyManager  (MSI installer, writes to system PATH)
#   - Install-Git        (EXE installer, writes to system PATH)
#   - Install-VCRedist   (writes to system registry)
# Everything else (venv, clone, pip) runs as the current user.
# ------------------------------------------------------------------------------

function Request-Elevation {
    # Re-runs comfyui.ps1 with -Mode AdminInstall as administrator.
    # The elevated window performs admin-only steps, then closes.
    # The calling (user-level) window continues after -Wait.
    param([string]$Mode)
    Write-Log "Requesting administrator rights..." STEP
    $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Mode $Mode"
    $proc = Start-Process powershell -ArgumentList $args -Verb RunAs -Wait -PassThru 2>$null
    if ($null -eq $proc) {
        Write-Log "Elevation was cancelled by user." WARN
        return $false
    }
    return $proc.ExitCode -eq 0
}

function Install-PyManager {
    Write-Log "Checking Python Manager (pymanager)..." STEP
    if (Get-Command "py" -ErrorAction SilentlyContinue) {
        # Distinguish Python Manager from legacy Python Launcher
        $pyHelp = (py --help 2>&1) | Out-String
        if ($pyHelp -match 'install|list|python manager' ) {
            $ver = ((py --version 2>&1) | Out-String).Trim()
            Write-Log "Python Manager already installed ($ver)" OK
            return $true
        }
    }

    Write-Log "Installing Python Manager..." PROCESS
    try {
        $baseUrl = "https://www.python.org/ftp/python/pymanager/"
        $page    = Invoke-WebRequest -Uri $baseUrl -UseBasicParsing -ErrorAction Stop
        $msiHref = ($page.Links |
                    Where-Object { $_.href -like "python-manager-*.msi" } |
                    Select-Object -Last 1).href
        if (-not $msiHref) { throw "MSI not found at $baseUrl" }

        $msiPath = "$env:TEMP\pymanager.msi"
        Invoke-WebRequest -Uri ($baseUrl + $msiHref) -OutFile $msiPath -ErrorAction Stop
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /quiet /norestart" -Wait -PassThru
        Remove-Item $msiPath -Force -ErrorAction SilentlyContinue

        if ($p.ExitCode -ne 0) { throw "MSI exited with code $($p.ExitCode)" }

        # Reload PATH so py.exe is available immediately
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        Write-Log "Python Manager installed." OK
        return $true
    } catch {
        Write-Log "Python Manager install failed: $_" ERROR
        return $false
    }
}

function Install-Git {
    Write-Log "Checking Git..." STEP
    try {
        $ghResp    = Invoke-WebRequest `
            -Uri "https://api.github.com/repos/git-for-windows/git/releases/latest" `
            -UseBasicParsing -ErrorAction Stop | ConvertFrom-Json
        $latestVer = ($ghResp.tag_name -replace '^v','' -split '\.windows')[0].Trim()

        if (Get-Command "git" -ErrorAction SilentlyContinue) {
            $currentVer = ((git --version) -replace 'git version\s*','' `
                            -split '\.windows')[0].Trim()
            # Normalise to X.Y.Z for comparison
            $norm = { param($v) if ($v -match '^\d+\.\d+$') { "$v.0" } else { $v } }
            try {
                $a = [System.Version](& $norm $currentVer)
                $b = [System.Version](& $norm $latestVer)
                if ($a.CompareTo($b) -ge 0) {
                    Write-Log "Git $currentVer (up to date)" OK
                    return $true
                }
                Write-Log "Updating Git $currentVer → $latestVer..." PROCESS
            } catch {
                Write-Log "Git already installed ($currentVer)" OK
                return $true
            }
        } else {
            Write-Log "Installing Git $latestVer..." PROCESS
        }

        $asset = $ghResp.assets |
                 Where-Object { $_.name -like "Git-*-64-bit.exe" } |
                 Select-Object -First 1
        Invoke-WebRequest -Uri $asset.browser_download_url `
            -OutFile "$env:TEMP\git_setup.exe" -ErrorAction Stop
        Start-Process "$env:TEMP\git_setup.exe" -ArgumentList "/VERYSILENT /NORESTART" -Wait
        Remove-Item "$env:TEMP\git_setup.exe" -Force -ErrorAction SilentlyContinue

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")
        git config --system core.longpaths true
        Write-Log "Git installed/updated." OK
        return $true
    } catch {
        Write-Log "Git install failed: $_" ERROR
        return $false
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
             Where-Object { $_ } | Select-Object -First 1
    if ($found) {
        Write-Log "Visual C++ Runtime already installed ($($found.Version))" OK
        return $true
    }

    Write-Log "Installing Visual C++ Runtime..." PROCESS
    try {
        Invoke-WebRequest -Uri "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
            -OutFile "$env:TEMP\vc_redist.exe" -ErrorAction Stop
        $p = Start-Process "$env:TEMP\vc_redist.exe" `
            -ArgumentList "/install /quiet /norestart" -Wait -PassThru
        Remove-Item "$env:TEMP\vc_redist.exe" -Force -ErrorAction SilentlyContinue
        if ($p.ExitCode -notin @(0, 3010)) { throw "Exited with $($p.ExitCode)" }
        Write-Log "Visual C++ Runtime installed." OK
        return $true
    } catch {
        Write-Log "VC++ install failed: $_" ERROR
        return $false
    }
}

function Select-PythonBranch {
    Write-Log "Fetching available Python versions..." STEP

    # py list --online — Python Manager format
    $onlineRaw = py list --online 2>&1 | Select-Object -Skip 1
    $onlineList = $onlineRaw | ForEach-Object {
        if ($_ -match '^\s*(3\.\d+)' -and $_ -notmatch 'dev|alpha|beta|a\d|b\d|rc') { $Matches[1] }
    } | Select-Object -Unique | Select-Object -First 5

    if (-not $onlineList -or $onlineList.Count -eq 0) {
        Write-Log "Could not retrieve Python version list." ERROR
        Write-Log "Ensure Python Manager (pymanager) is installed and the legacy Python Launcher is removed." WARN
        return $null
    }

    $localList     = py list 2>&1 | Select-Object -Skip 1 | ForEach-Object {
        if ($_ -match '^\s*(3\.\d+)' -and $_ -notmatch 'dev|alpha|beta|a\d|b\d|rc') { $Matches[1] }
    } | Select-Object -Unique

    $currentBranch = $null
    $cfg = Join-Path $script:Root "$DIR_VENV\pyvenv.cfg"
    if (Test-Path $cfg) {
        $line = Get-Content $cfg -Encoding UTF8 | Where-Object { $_ -match '^\s*version\s*=' }
        if ($line -and ($line -split '=')[1].Trim() -match '^(3\.\d+)') {
            $currentBranch = $Matches[1]
        }
    }

    Write-Host ""
    Write-Host "  Available Python versions:" -ForegroundColor White
    for ($i = 0; $i -lt $onlineList.Count; $i++) {
        $branch = $onlineList[$i]
        $note   = if ($branch -eq $currentBranch) { " (current venv)" }
                  elseif ($localList -contains $branch) { " (installed)" }
                  else { "" }
        $color  = if ($branch -eq $currentBranch) { "Green" }
                  elseif ($localList -contains $branch) { "Cyan" }
                  else { "Gray" }
        Write-Host "    [$($i+1)] Python $branch$note" -ForegroundColor $color
    }
    Write-Host "    [0] Cancel" -ForegroundColor DarkGray
    Write-Host ""

    do {
        $raw = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $pick = $raw.Character.ToString()
    } while ($pick -notmatch '^\d$' -or ([int]$pick -lt 0) -or ([int]$pick -gt $onlineList.Count))

    Write-Host "  $pick" -ForegroundColor Cyan
    if ($pick -eq '0') { return $null }

    $branch = $onlineList[[int]$pick - 1]
    if ($localList -notcontains $branch) {
        Write-Log "Installing Python $branch..." STEP
        py install $branch 2>&1 | Out-Null
    }
    return $branch
}

function New-Venv {
    param([string]$Branch)
    Write-Log "Creating venv (Python $Branch)..." STEP

    $venvPath = Join-Path $script:Root $DIR_VENV
    # Clean up partial venv if python.exe is missing
    if ((Test-Path $venvPath) -and -not (Test-Path $script:VenvPython)) {
        Write-Log "Removing incomplete venv..." WARN
        Remove-Item $venvPath -Recurse -Force
    }

    py -$Branch -m venv $venvPath 2>&1 | Out-Null

    if (Test-Path $script:VenvPython) {
        Write-Log "venv created (Python $Branch)" OK
        return $true
    } else {
        Write-Log "venv creation failed." ERROR
        return $false
    }
}

function Update-Pip {
    if (-not (Test-Path $script:VenvPython)) {
        Write-Log "venv not found — pip upgrade skipped." WARN; return
    }
    Write-Log "Upgrading pip..." STEP
    & $script:VenvPython -m pip install --upgrade pip --quiet 2>&1 | Out-Null
    $pipVer = (& $script:VenvPython -m pip --version 2>&1) -replace 'pip\s+(\S+).*','$1'
    Write-Log "pip $pipVer" OK
}

function Clone-ComfyUI {
    $comfyPath = Join-Path $script:Root $DIR_COMFYUI
    if (Test-Path $comfyPath) {
        Write-Log "ComfyUI folder already exists — skipped." OK
        return $true
    }
    Write-Log "Cloning ComfyUI..." STEP
    Push-Location $script:Root
    git clone https://github.com/Comfy-Org/ComfyUI.git $DIR_COMFYUI --quiet
    $ok = $LASTEXITCODE -eq 0
    Pop-Location
    if ($ok) { Write-Log "ComfyUI cloned." OK }
    else      { Write-Log "Clone failed (exit $LASTEXITCODE)." ERROR }
    return $ok
}

# --- Install flow (called in elevated window) ---
function Invoke-AdminInstall {
    # This runs in a separate elevated PS window
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Set-Location $script:Root

    Write-Host ""
    Write-Host "  ComfyUI Toolkit — Administrator Setup" -ForegroundColor Cyan
    Write-Host "  Installing system components..." -ForegroundColor DarkGray
    Write-Host ""

    $ok = $true
    $ok = (Install-PyManager) -and $ok
    $ok = (Install-Git)       -and $ok
    $ok = (Install-VCRedist)  -and $ok

    Write-Host ""
    if ($ok) { Write-Log "System components installed successfully." SUCCESS }
    else      { Write-Log "Some components failed. Check output above." WARN }

    Write-Host ""
    Write-Host "  Press any key to close this window..." -ForegroundColor DarkGray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    if ($ok) { exit 0 } else { exit 1 }
}

# --- Full install (user-level steps after admin window closes) ---
function Invoke-Install {
    Show-Header
    Write-Host "  $(t 'menu.install.label')" -ForegroundColor White
    Write-Div

    Write-Host ""
    Write-Log "Step 1/5 — System components ($(t 'status.admin.note'))..." STEP
    $adminOk = Request-Elevation -Mode AdminInstall
    if (-not $adminOk) {
        Write-Log "Admin setup did not complete successfully." WARN
        if (-not (Confirm-Action "Continue with user-level steps anyway?")) {
            Wait-Key; return
        }
    }

    # Reload PATH after admin install
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    Write-Host ""
    Write-Log "Step 2/5 — Select Python version..." STEP
    $branch = Select-PythonBranch
    if (-not $branch) { Write-Log "Install aborted — no Python selected." WARN; Wait-Key; return }

    Write-Host ""
    Write-Log "Step 3/5 — Creating venv (Python $branch)..." STEP
    if (-not (New-Venv -Branch $branch)) { Wait-Key; return }

    Write-Host ""
    Write-Log "Step 4/5 — Upgrading pip..." STEP
    Update-Pip

    Write-Host ""
    Write-Log "Step 5/5 — Cloning ComfyUI..." STEP
    Clone-ComfyUI

    Write-Host ""
    Write-Log "Install complete." SUCCESS
    Write-Log "Next: press [T] to install PyTorch, then [V] to select ComfyUI version." INFO
    Write-FileLog "Install completed (Python $branch)"
    Initialize-RuntimeCache
    Wait-Key
}

# --- Update (git + python minor + pip, no admin needed) ---
function Invoke-Update {
    Show-Header
    Write-Host "  $(t 'menu.update.label')" -ForegroundColor White
    Write-Div
    Write-Host ""

    # Git
    Write-Log "Checking Git..." STEP
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $ghResp    = Invoke-WebRequest `
                "https://api.github.com/repos/git-for-windows/git/releases/latest" `
                -UseBasicParsing -ErrorAction Stop | ConvertFrom-Json
            $latestVer = ($ghResp.tag_name -replace '^v','' -split '\.windows')[0].Trim()
            $currentVer= ((git --version) -replace 'git version\s*','' -split '\.windows')[0].Trim()
            $norm = { param($v) if ($v -match '^\d+\.\d+$') {"$v.0"} else {$v} }
            try {
                $a = [System.Version](& $norm $currentVer)
                $b = [System.Version](& $norm $latestVer)
                if ($a.CompareTo($b) -lt 0) {
                    Write-Log "Git update available ($currentVer → $latestVer)." WARN
                    Write-Log "Admin rights needed to update Git. Use [E] Install to update system tools." INFO
                } else {
                    Write-Log "Git $currentVer (up to date)" OK
                }
            } catch { Write-Log "Git $currentVer" OK }
        } catch { Write-Log "Could not check Git version." WARN }
    } else { Write-Log "Git not found." WARN }

    # Python minor
    Write-Log "Checking Python minor update..." STEP
    $cfg = Join-Path $script:Root "$DIR_VENV\pyvenv.cfg"
    if (Test-Path $cfg) {
        $line = Get-Content $cfg -Encoding UTF8 | Where-Object { $_ -match '^\s*version\s*=' }
        if ($line -and ($line -split '=')[1].Trim() -match '^(3\.\d+)') {
            $branch    = $Matches[1]
            $verBefore = (py -$branch --version 2>&1 | Out-String).Trim()
            py install $branch --update 2>&1 | Out-Null
            $verAfter  = (py -$branch --version 2>&1 | Out-String).Trim()
            if ($verBefore -ne $verAfter) { Write-Log "Python updated: $verBefore → $verAfter" OK }
            else                          { Write-Log "Python $verAfter (up to date)" OK }
        }
    } else { Write-Log "venv not found — Python update skipped." WARN }

    # pip
    Update-Pip

    Write-Log "Update complete. ComfyUI and venv packages not touched." INFO
    Write-FileLog "Update completed"
    Initialize-RuntimeCache
    Wait-Key
}

# --- Swap Python (user-level: pick new version, delete venv, recreate) ---
function Invoke-SwapPython {
    Show-Header
    Write-Host "  $(t 'menu.swap.label')" -ForegroundColor White
    Write-Div
    Write-Host ""
    Write-Log "This will DELETE the existing venv and recreate it under a new Python version." WARN
    Write-Log "The ComfyUI folder will NOT be touched." INFO
    Write-Log "PyTorch and all pip packages must be reinstalled afterwards." WARN
    Write-Host ""

    # Pick branch FIRST — before any destructive action
    $branch = Select-PythonBranch
    if (-not $branch) { Write-Log "Swap cancelled." INFO; Wait-Key; return }

    Write-Host ""
    if (-not (Confirm-Action "Delete venv and recreate with Python $branch?")) {
        Write-Log "Swap cancelled." INFO; Wait-Key; return
    }

    # NOW delete old venv
    $venvPath = Join-Path $script:Root $DIR_VENV
    if (Test-Path $venvPath) {
        Write-Log "Removing existing venv..." STEP
        Remove-Item $venvPath -Recurse -Force
        Write-Log "Old venv removed." OK
    }

    if (-not (New-Venv -Branch $branch)) { Wait-Key; return }
    Update-Pip

    Write-Host ""
    Write-Log "Swap complete. Use [T] to reinstall PyTorch." SUCCESS
    Write-FileLog "Python swap: $branch"
    Initialize-RuntimeCache
    Wait-Key
}

#endregion INSTALL

# ==============================================================================

#region MANAGER
# ------------------------------------------------------------------------------
# Torch stack, ComfyUI version switching, Repair, Info.
# All user-level — no admin required.
# ------------------------------------------------------------------------------

$TorchProtected = @("torch", "torchvision", "torchaudio", "torchsde")

function Apply-ConstConstraints {
    if (Test-Path $script:ConstFile) {
        $env:PIP_CONSTRAINT = $script:ConstFile
        Write-Log "pip constraints loaded from const.txt" INFO
    } else {
        $env:PIP_CONSTRAINT = ""
    }
}

function Cleanup-Venv {
    $sitePackages = Join-Path $script:Root "$DIR_VENV\Lib\site-packages"
    if (-not (Test-Path $sitePackages)) { return }

    # Remove pip temp artifacts
    Get-ChildItem $sitePackages -Filter "~*" -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Remove orphaned .dist-info — use pip list as authority (one call, not N calls)
    Write-Log "Scanning for orphaned .dist-info..." INFO
    $installedNames = (& $script:VenvPython -m pip list --format json 2>$null |
        ConvertFrom-Json).name | ForEach-Object { $_.ToLower() }
    $installedSet = [System.Collections.Generic.HashSet[string]]($installedNames)

    Get-ChildItem $sitePackages -Filter "*.dist-info" -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            $pkgName = ($_.Name -replace '-[\d\.]+[^-]*\.dist-info$', '').ToLower()
            if (-not $installedSet.Contains($pkgName)) {
				Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

    # Remove __pycache__
    Get-ChildItem $sitePackages -Filter "__pycache__" -Directory -Recurse -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

# --- TORCH ---

function Get-SupportedCudaVersions {
    Write-Host ""; Write-Log "Fetching CUDA versions from pytorch.org..." INFO
    try {
        $data  = Invoke-WebRequest "https://docs.pytorch.org/assets/quick-start-module.js" `
                    -UseBasicParsing -TimeoutSec 10
        $block = [regex]::Match($data.Content, '"release":\s*{([^}]*)}').Groups[1].Value
        $cu    = [regex]::Matches($block, '"cuda\.\w+":\s*\["cuda",\s*"([\d\.]+)"\]') |
                 ForEach-Object { $_.Groups[1].Value } |
                 Sort-Object { [version]$_ } -Descending |
                 ForEach-Object { $_ -replace '\.', '' }
        if ($cu -and $cu.Count -gt 0) { return $cu }
    } catch { Write-Log "Could not reach pytorch.org: $($_.Exception.Message)" WARN }

    # Fallback: manual entry
    Write-Host ""; Write-Log "Enter CUDA version manually (e.g. 126, 128, 130):" STEP
    while ($true) {
        $manual = Read-Host "CUDA version"
        if ($manual -match '^\d{3}$') { return @($manual) }
        Write-Log "Invalid format. Use 3 digits, e.g. 128" ERROR
    }
}

function Change-Torch {
    Show-Header
    Write-Host "  $(t 'menu.torch.label')" -ForegroundColor White
    Write-Div
    Cleanup-Venv

    if (-not (Test-Path $script:VenvPython)) {
        Write-Log "venv not found." ERROR; Wait-Key; return
    }

    $currentTorch = (& $script:VenvPython -c "import torch; print(torch.__version__)" 2>$null)
    Write-Host ""
    Write-Host "  Current PyTorch: " -NoNewline -ForegroundColor DarkGray
    Write-Host $(if ($currentTorch) { $currentTorch } else { "not installed" }) -ForegroundColor Cyan

    $cu = Get-SupportedCudaVersions
    Write-Host ""; Write-Host "  Select CUDA version:" -ForegroundColor White
    for ($i = 0; $i -lt $cu.Count; $i++) { Write-Host "  [$($i+1)] cu$($cu[$i])" -ForegroundColor Gray }
    Write-Host "  [0] Back" -ForegroundColor DarkGray

    do { $k = Read-Key } while ($k -notmatch '^\d$' -or ([int]$k -gt $cu.Count))
    Write-Host "  $k" -ForegroundColor Cyan
    if ($k -eq '0') { return }
    $selectedCu = $cu[[int]$k - 1]
    $indexUrl   = "https://download.pytorch.org/whl/cu$selectedCu"

    Write-Host ""; Write-Log "Fetching available PyTorch versions for cu$selectedCu..." INFO
    # Use pip index versions (stable, documented)
    $rawIndex = & $script:VenvPython -m pip index versions torch --index-url $indexUrl 2>&1
    $raw      = $rawIndex -join " "

    if ($raw -notmatch "Available versions:\s*([\d\.\+a-z ,cu]+)") {
        Write-Log "Could not fetch version list from PyTorch index." ERROR
        Wait-Key; return
    }

    $versions = $Matches[1].Split(',') |
                ForEach-Object { $_.Trim() } |
                Where-Object   { $_ -match '^\d+\.\d+\.\d+' } |
                Select-Object  -Unique |
                Sort-Object    { [version]($_ -replace '\+.*','') } -Descending |
                Select-Object  -First 5

    Write-Host ""; Write-Host "  Select PyTorch version:" -ForegroundColor White
    for ($i = 0; $i -lt $versions.Count; $i++) {
        $clean = $versions[$i] -replace '\+.*',''
        $mark  = if ($currentTorch -and $clean -eq $currentTorch) { " (current)" } else { "" }
        Write-Host "  [$($i+1)] $clean$mark" -ForegroundColor Gray
    }
    Write-Host "  [0] Back" -ForegroundColor DarkGray

    do { $k = Read-Key } while ($k -notmatch '^\d$' -or ([int]$k -gt $versions.Count))
    Write-Host "  $k" -ForegroundColor Cyan
    if ($k -eq '0') { return }
    $target = $versions[[int]$k - 1]

    Write-Host ""; Write-Log "Installing PyTorch $target (cu$selectedCu)..." PROCESS
    $env:PIP_CONSTRAINT = ""  # clear constraints during torch install
    & $script:VenvPython -m pip install `
        "torch==$target" "torchvision" "torchaudio==$target" `
        --index-url $indexUrl --upgrade --prefer-binary --force-reinstall
	Write-Log "Installing torchsde..." PROCESS
    & $script:VenvPython -m pip install torchsde --prefer-binary --quiet

    Write-Log "Installing torchsde..." PROCESS
    & $script:VenvPython -m pip install torchsde --prefer-binary --quiet

    # Sync ComfyUI requirements (torch stack excluded)
    $reqFile = Join-Path $script:Root "$DIR_COMFYUI\requirements.txt"
    if (Test-Path $reqFile) {
        Write-Log "Syncing ComfyUI requirements (torch excluded)..." PROCESS
        $filteredReq = Join-Path $script:CacheDir "requirements_filtered.tmp"
        Get-Content $reqFile | Where-Object {
            ($TorchProtected + @("comfyui-workflow-templates")) -notcontains (($_ -split '[>=<!]')[0].Trim().ToLower())
        } | Set-Content $filteredReq -Encoding UTF8

        & $script:VenvPython -m pip install -r $filteredReq `
            --prefer-binary --extra-index-url $indexUrl
        Remove-Item $filteredReq -Force -ErrorAction SilentlyContinue
    }

    # Save torch snapshot to const.txt
    $tv = (& $script:VenvPython -c "import torch; print(torch.__version__)" 2>$null)
    $tvv= (& $script:VenvPython -c "import torchvision; print(torchvision.__version__)" 2>$null)
    $tva= (& $script:VenvPython -c "import torchaudio; print(torchaudio.__version__)" 2>$null)
    @(
        "# ComfyUI Toolkit — Torch Snapshot"
        "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "# CUDA index: cu$selectedCu"
        "# DO NOT EDIT MANUALLY"
        ""
        "torch==$tv"
        "torchvision==$tvv"
        "torchaudio==$tva"
    ) | Set-Content $script:ConstFile -Encoding UTF8

    Write-Host ""; Write-Log "Running Repair to resolve any dependency conflicts..." STEP
    Repair-Environment -CalledFromModule

    Write-Log "PyTorch $($target -replace '\+.*','') (cu$selectedCu) installed." SUCCESS
    Write-FileLog "Torch switched: $currentTorch → $($target -replace '\+.*','') (cu$selectedCu)"
    Initialize-RuntimeCache
    Wait-Key
}

# --- COMFYUI VERSION ---

$MinComfyVersion = "v0.13.0"

function Change-ComfyUI {
    $comfyPath = Join-Path $script:Root $DIR_COMFYUI
    if (-not (Test-Path $comfyPath)) {
        Show-Header; Write-Log "ComfyUI directory not found." ERROR; Wait-Key; return
    }
    Cleanup-Venv
    Push-Location $comfyPath

    $current       = git describe --tags --abbrev=0 2>$null
    $currentCommit = git rev-parse --short HEAD 2>$null

    Show-Header
    Write-Host "  $(t 'menu.comfy.label')" -ForegroundColor White
    Write-Div
    Write-Host ""
    Write-Host "  Current: " -NoNewline -ForegroundColor DarkGray
    Write-Host "$current ($currentCommit)" -ForegroundColor Cyan

    Write-Log "Fetching tags..." STEP
    git fetch --tags --all --quiet

    $allTags = git tag -l --sort=-v:refname
    $branches = $allTags |
        ForEach-Object { if ($_ -match '^(v\d+\.\d+)') { $Matches[1] } } |
        Select-Object -Unique |
        Sort-Object { [version]($_ -replace 'v','') } -Descending |
        Select-Object -First 10

    Write-Host ""; Write-Host "  Branch:" -ForegroundColor White
    for ($i = 0; $i -lt $branches.Count; $i++) {
        $branchTags = $allTags | Where-Object { $_ -match "^$([regex]::Escape($branches[$i]))\." }
        $mark = if ($branchTags -contains $current) { " (current)" } else { "" }
        Write-Host "  [$($i+1)] $($branches[$i])$mark" -ForegroundColor Gray
    }
    Write-Host "  [0] Back" -ForegroundColor DarkGray

    do { $k = Read-Key } while ($k -notmatch '^\d$' -or ([int]$k -gt $branches.Count))
    Write-Host "  $k" -ForegroundColor Cyan
    if ($k -eq '0') { Pop-Location; return }

    $selectedBranch = $branches[[int]$k - 1]
    $branchTags = @($allTags | Where-Object { $_ -match "^$([regex]::Escape($selectedBranch))\." } |
        Sort-Object { [version]($_ -replace 'v','') })

    # Optional release notes
    Write-Host ""; Write-Host "  Show release notes for $selectedBranch?" -ForegroundColor White
    Write-Host "  [Y] Yes   [N] No" -ForegroundColor DarkGray
    if ((Read-Key) -eq 'Y') {
        Write-Host ""; Write-Log "Fetching release notes from GitHub..." INFO
        foreach ($tag in $branchTags) {
            try {
                $res = Invoke-RestMethod `
                    "https://api.github.com/repos/Comfy-Org/ComfyUI/releases/tags/$tag" `
                    -ErrorAction SilentlyContinue
                if ($res) {
                    Write-Host ""; Write-Host "  --- $tag ---" -ForegroundColor Cyan
                    $clean = ($res.body -split '## New Contributors' | Select-Object -First 1).Trim()
                    Write-Host $clean -ForegroundColor DarkGray
                    "--- $tag ---`n$clean`n" | Add-Content (Join-Path $script:CacheDir "release_notes.log") -Encoding UTF8
                }
            } catch {}
        }
        Wait-Key
    }

    # Version selection
    Write-Host ""; Write-Host "  Version in ${selectedBranch}:" -ForegroundColor White
    for ($i = 0; $i -lt $branchTags.Count; $i++) {
        $mark = if ($branchTags[$i] -eq $current) { " (current)" } else { "" }
        Write-Host "  [$($i+1)] $($branchTags[$i])$mark" -ForegroundColor Gray
    }
    Write-Host "  [0] Back" -ForegroundColor DarkGray

    do { $k = Read-Key } while ($k -notmatch '^\d$' -or ([int]$k -gt $branchTags.Count))
    Write-Host "  $k" -ForegroundColor Cyan
    if ($k -eq '0') { Pop-Location; return }
    $target = $branchTags[[int]$k - 1]

    # Minimum version check
    $minVer    = [version]($MinComfyVersion -replace 'v','')
    $targetVer = [version]($target -replace 'v','')
    if ($targetVer -lt $minVer) {
        Write-Host ""; Write-Log "WARNING: $target is below minimum recommended ($MinComfyVersion)." WARN
        if (-not (Confirm-Action "Continue anyway?")) { Pop-Location; return }
    }

    # Downgrade DB check
    $dbPath = Join-Path $comfyPath "user\comfyui.db"
    if ((Test-Path $dbPath) -and $current) {
        try {
            $isDowngrade = [version]($target -replace 'v','') -lt [version]($current -replace 'v','')
            if ($isDowngrade) {
                Write-Host ""; Write-Log "DOWNGRADE detected: $current → $target" WARN
                Write-Log "Database may have incompatible migrations." WARN
                Write-Log "Database stores only asset cache and job history — no workflows or models." INFO
                if (Confirm-Action "Delete database and let ComfyUI recreate it?") {
                    Remove-Item $dbPath -Force
                    Write-Log "Database removed. ComfyUI will recreate it on next launch." OK
                }
            }
        } catch {}
    }

    # Switch version
    Write-Host ""; Write-Log "Switching to $target..." PROCESS
    git checkout $target --force --quiet
    if ($LASTEXITCODE -ne 0) {
        Write-Log "git checkout failed." ERROR; Pop-Location; Wait-Key; return
    }

    # Install requirements (torch stack excluded)
    $reqFile = Join-Path $comfyPath "requirements.txt"
    if (Test-Path $reqFile) {
        Write-Log "Installing dependencies (torch excluded)..." PROCESS
        $filteredReq = Join-Path $script:CacheDir "requirements_filtered.tmp"
        Get-Content $reqFile | Where-Object {
            ($TorchProtected + @("comfyui-workflow-templates")) -notcontains (($_ -split '[>=<!]')[0].Trim().ToLower())
        } | Set-Content $filteredReq -Encoding UTF8

        $cudaIndex = ""
        if (Test-Path $script:ConstFile) {
            $tl = Get-Content $script:ConstFile | Where-Object { $_ -match "^torch==" } | Select-Object -First 1
            if ($tl -match '\+cu(\d+)') { $cudaIndex = "https://download.pytorch.org/whl/cu$($Matches[1])" }
        }

        $env:PIP_CONSTRAINT = ""  # clear during install
        try {
            if ($cudaIndex) {
                & $script:VenvPython -m pip install -r $filteredReq --prefer-binary --extra-index-url $cudaIndex
            } else {
                & $script:VenvPython -m pip install -r $filteredReq --prefer-binary
            }
        } catch {
            Write-Log "pip install error: $_" WARN
        }
        Remove-Item $filteredReq -Force -ErrorAction SilentlyContinue
    }


   # Networking stack refresh
    Write-Log "Updating comfyui-workflow-templates..." PROCESS
    & $script:VenvPython -m pip install comfyui-workflow-templates comfyui-workflow-templates-core comfyui-workflow-templates-media-api comfyui-workflow-templates-media-image comfyui-workflow-templates-media-other comfyui-workflow-templates-media-video --upgrade --prefer-binary -c NUL
    Write-Log "comfyui-workflow-templates exit: $LASTEXITCODE" INFO
    Write-Log "Refreshing networking stack..." PROCESS
    & $script:VenvPython -m pip install requests urllib3 charset-normalizer --upgrade --prefer-binary

    Write-Host ""; Write-Log "Running Repair to resolve any dependency conflicts..." STEP
    Repair-Environment -CalledFromModule

    Write-Log "ComfyUI switched: $current → $target" SUCCESS
    Write-FileLog "ComfyUI switched: $current → $target"
    Pop-Location
    Initialize-RuntimeCache
    Wait-Key
}

# --- REPAIR ---

function Repair-Environment {
    param([switch]$CalledFromModule)

    if (-not $CalledFromModule) {
        Show-Header
        Write-Host "  $(t 'menu.repair.label')" -ForegroundColor Red
        Write-Div
        Write-Host ""
        Write-Log "Deep dependency repair. Torch stack is fully protected." INFO
        Write-Log "If conflict is caused by an incompatible custom node — this tool" INFO
        Write-Log "cannot fix it. Use ComfyUI-Manager to disable/remove that node." INFO
        Write-Host ""
        if (-not (Confirm-Action "Proceed with repair?")) { return }
    }

    if (-not (Test-Path $script:SmartFixer)) {
        Write-Log "smart_fixer.py not found in .cache — redeploying..." WARN
        Initialize-Cache
    }
	

    Write-Log "[1/8] Capturing environment snapshot..." STEP
    $beforeList = & $script:VenvPython -m pip list --format json 2>$null | ConvertFrom-Json

    Write-Log "[2/8] Cleaning broken pip cache entries (torch preserved)..." STEP
    foreach ($pkg in @("chardet","urllib3","charset-normalizer","requests","numpy","numba")) {
        & $script:VenvPython -m pip cache remove $pkg 2>$null | Out-Null
    }

    Write-Log "[3/8] Removing broken venv artifacts..." STEP
    Cleanup-Venv

    Write-Log "[4/8] Running Smart Dependency Guard..." STEP
    $env:PIP_CONSTRAINT = ""
    $fixerResult   = & $script:VenvPython $script:SmartFixer $script:VenvPython `
                        (Join-Path $script:Root $DIR_COMFYUI) $script:CacheDir
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

	Write-Log "[5/8] Updating comfyui-workflow-templates..." STEP
    $savedConstraint = $env:PIP_CONSTRAINT
    $env:PIP_CONSTRAINT = ""
    & $script:VenvPython -m pip install comfyui-workflow-templates comfyui-workflow-templates-core comfyui-workflow-templates-media-api comfyui-workflow-templates-media-image comfyui-workflow-templates-media-other comfyui-workflow-templates-media-video --upgrade --prefer-binary
    $env:PIP_CONSTRAINT = $savedConstraint
	
	Write-Log "[6/8] Installing missing transitive dependencies..." STEP
    $savedConstraint2 = $env:PIP_CONSTRAINT
    $env:PIP_CONSTRAINT = ""
    $pipCheckOutput = & $script:VenvPython -m pip check 2>&1
    $missingPkgs = $pipCheckOutput | ForEach-Object {
        if ($_ -match '^\S+ [\d\.]+ requires ([\w\-]+), which is not installed') {
            $Matches[1]
        }
    } | Select-Object -Unique | Where-Object {
        $TorchProtected -notcontains $_.ToLower() -and
        @("comfyui-workflow-templates") -notcontains $_.ToLower()
    }
    if ($missingPkgs) {
        Write-Log "Installing: $($missingPkgs -join ', ')" INFO
        & $script:VenvPython -m pip install @missingPkgs --prefer-binary --quiet
    } else {
        Write-Log "No missing transitive dependencies." INFO
    }
    $env:PIP_CONSTRAINT = $savedConstraint2

    Write-Log "[7/8] Applying stable constraints..." STEP
    if ($fixerExitCode -eq 0) {
        Apply-ConstConstraints
        Write-Log "Constraints active for future pip operations." INFO
    } else {
        Write-Log "Skipped — unresolved conflicts remain." WARN
    }

    Write-Log "[8/8] Repair summary..." STEP
    $afterList    = & $script:VenvPython -m pip list --format json 2>$null | ConvertFrom-Json
    $changesFound = $false
    foreach ($newPkg in $afterList) {
        $oldPkg = $beforeList | Where-Object { $_.name -eq $newPkg.name } | Select-Object -First 1
        if ($oldPkg -and $oldPkg.version -ne $newPkg.version) {
            $isProtected = $TorchProtected -contains $newPkg.name.ToLower()
            $tag  = if ($isProtected) { " [PROTECTED]" } else { " [MODIFIED] " }
            $tagC = if ($isProtected) { "Cyan" } else { "White" }
            Write-Host "$tag" -NoNewline -ForegroundColor $tagC
            Write-Host " $($newPkg.name): " -NoNewline
            Write-Host $oldPkg.version -ForegroundColor Red -NoNewline
            Write-Host " → " -NoNewline
            Write-Host $newPkg.version -ForegroundColor Green
            $changesFound = $true
        }
    }
    if (-not $changesFound) { Write-Log "No packages changed. Environment was already optimal." INFO }

    if ($fixerExitCode -eq 0) {
        Write-Host ""; Write-Log "Repair complete. const.txt updated." SUCCESS
        Write-FileLog "Repair: SUCCESS"
    } else {
        Write-Host ""; Write-Log "Repair finished with unresolved issues." WARN
        if (-not $CalledFromModule) {
            Write-Log "If conflict is from a custom node:" INFO
            Write-Log "  Disable/remove it via ComfyUI-Manager, then run Repair again." INFO
        }
        Write-FileLog "Repair: PARTIAL — unresolved conflicts"
    }

    if (-not $CalledFromModule) { Wait-Key }
}

# --- INFO ---

function Show-Info {
    Show-Header
    Write-Host "  $(t 'menu.info.label')" -ForegroundColor Cyan
    Write-Div
    Write-Host ""

    $reportContent = ""

    # ComfyUI version
    $comfyPath = Join-Path $script:Root $DIR_COMFYUI
    if (Test-Path $comfyPath) {
        Push-Location $comfyPath
        $tag    = git describe --tags --abbrev=0 2>$null
        $commit = git rev-parse --short HEAD 2>$null
        Pop-Location
        $line = if ($tag) { "  ComfyUI:         $tag ($commit)" }
                else      { "  ComfyUI:         (no tag) $commit" }
    } else { $line = "  ComfyUI:         not found" }
    Write-Host $line -ForegroundColor Cyan
    $reportContent += "$line`n"

    # GPU via nvidia-smi
    if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
        $smi     = nvidia-smi --query-gpu=driver_version,name,memory.total --format=csv,noheader,nounits --id=0
        $cudaVer = (nvidia-smi | Select-String "CUDA Version: (\d+\.\d+)").Matches.Groups[1].Value
        $parts   = $smi -split ','
        $vram    = [Math]::Round([float]$parts[2] / 1024, 2)
        $line    = "  GPU:             $($parts[1].Trim()) ($vram GB VRAM, Driver $($parts[0].Trim()), CUDA $cudaVer)"
        Write-Host $line -ForegroundColor Cyan
    } else {
        $line = "  GPU:             nvidia-smi not found"
        Write-Host $line -ForegroundColor Red
    }
    $reportContent += "$line`n"

    # Python, PyTorch and accelerators via venv Python
    $pyCode = @'
import sys, platform, importlib
from importlib.metadata import version, PackageNotFoundError
import subprocess

def install_if_needed(pkg):
    try: importlib.import_module(pkg)
    except ImportError:
        subprocess.run([sys.executable, "-m", "pip", "install", pkg],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

install_if_needed("psutil")
install_if_needed("py-cpuinfo")
import psutil, cpuinfo

def get_cpu():
    try:
        i = cpuinfo.get_cpu_info()
        return f"{i.get('brand_raw','?')} ({psutil.cpu_count(logical=False)}C/{psutil.cpu_count()}T)"
    except: return "unknown"

def gv(pkg):
    aliases = {
        "triton":        ["triton-windows","triton"],
        "flash-attn":    ["flash-attn","flash_attn"],
        "sageattention": ["sageattention","sage-attention"],
        "sageattn3":     ["sageattn3","sage-attn3"],
    }
    for name in aliases.get(pkg.lower(), [pkg]):
        try: return version(name)
        except PackageNotFoundError: continue
    return "not installed"

ram = round(psutil.virtual_memory().total / (1024**3), 2)
print(f"  CPU:             {get_cpu()}")
print(f"  RAM:             {ram} GB")
print(f"  Python:          {platform.python_version()}")
print(f"  PyTorch:         {gv('torch')}")
print(f"  Torchaudio:      {gv('torchaudio')}")
print(f"  Torchvision:     {gv('torchvision')}")
print(f"  Triton:          {gv('triton')}")
print(f"  xFormers:        {gv('xformers')}")
print(f"  Flash-Attn:      {gv('flash-attn')}")
print(f"  SageAttn 2:      {gv('sageattention')}")
print(f"  SageAttn 3:      {gv('sageattn3')}")
'@

    # Clear constraint temporarily so psutil/cpuinfo can install if missing
    $savedConstraint    = $env:PIP_CONSTRAINT
    $env:PIP_CONSTRAINT = ""

    $output = if (Test-Path $script:VenvPython) {
        $pyCode | & $script:VenvPython - 2>&1
    } else { "  venv Python not found" }

    $env:PIP_CONSTRAINT = $savedConstraint

    foreach ($line in $output) {
        $color = if ($line -match "not installed") { "DarkGray" } else { "Cyan" }
        Write-Host $line -ForegroundColor $color
        $reportContent += "$line`n"
    }

    # Save snapshot
    try {
        "Scan Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n$reportContent" |
            Out-File $script:EnvLog -Encoding UTF8 -Force
        Write-Host ""
        Write-Log "Snapshot saved to .cache\env_state.log" INFO
    } catch { Write-Log "Could not save env_state.log" WARN }

    Wait-Key
}

#endregion MANAGER

# ==============================================================================

#region MAIN
# ------------------------------------------------------------------------------


function Main {
    # Console setup
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $Host.UI.RawUI.WindowTitle = "ComfyUI Launcher"
    try { $Host.UI.RawUI.WindowSize = New-Object System.Management.Automation.Host.Size(80,46) } catch {}
    try { $Host.UI.RawUI.BufferSize = New-Object System.Management.Automation.Host.Size(80,200) } catch {}


    # Language
    $langPref       = Load-Settings
    $script:Lang    = Resolve-Language $langPref

    # Cache and deployment
    Initialize-Cache

    # Slow values (python ver, torch ver, comfyui tag)
    Initialize-RuntimeCache

    # Background update check
    Start-UpdateCheck

    # First-run check
    if (-not (Test-Path $script:VenvPython)) {
        while ($true) {
            Show-Header
            Write-Host "  $(t 'status.first.run')" -ForegroundColor Yellow
            Write-Host ""
            Write-Host "  $(t 'status.setup.prompt')" -ForegroundColor White
            Write-Host "  [Y] $(t 'prompt.confirm.yes')   [N] $(t 'prompt.confirm.no')" -ForegroundColor DarkGray
            $k = Read-Key
            if ($k -eq 'Y') {
                Invoke-Install
                Initialize-RuntimeCache
                break
            } elseif ($k -eq 'L') {
                Switch-Language
            } else {
                Write-Log "Setup cancelled." WARN
                Start-Sleep -Seconds 2
                return
            }
        }
    }

    # Main loop
    while ($true) {
        Show-Menu
        $key = Read-Key
        Write-Host $key -ForegroundColor Cyan

        # Launch modes
        $matched = $LAUNCH_MODES | Where-Object { $_.Key -eq $key }
        if ($matched) { Invoke-ComfyUI -Mode $matched; continue }

        switch ($key) {
            'E' { Invoke-Install }
            'U' { Invoke-Update }
            'S' { Invoke-SwapPython }
            'T' { Change-Torch }
            'V' { Change-ComfyUI }
            'R' { Repair-Environment }
            'I' { Show-Info }
            'C' { Open-VenvConsole }
            'M' { Install-ComfyUIManager }
            'H' { Show-ComfyHelp }
            'L' { Switch-Language }   # cycle language, redraw menu
            '0' {
                # Clean up background job
                if ($script:UpdateJob) {
                    Remove-Job $script:UpdateJob -Force -ErrorAction SilentlyContinue
                }
                Clear-Host
                Write-Host ""
                Write-Host "  $(t 'menu.exit.label')" -ForegroundColor DarkGray
                Write-Host ""
                Start-Sleep -Milliseconds 400
                return
            }
        }
    }
}

# Entry point — supports elevated subprocess call with -Mode AdminInstall
if ($Mode -eq 'AdminInstall') {
    Invoke-AdminInstall
} else {
    Main
}

#endregion MAIN
