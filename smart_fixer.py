# =============================================================================
# smart_fixer.py — Auto Dependency Guard
# Part of: ComfyUI Master Manager v0.1
# Location: .cache/smart_fixer.py (deployed automatically by Module 6)
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

# These packages are never touched — managed exclusively by Module 4
PROTECTED = {"torch", "torchvision", "torchaudio"}

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
    Example: requests requires chardet<6,>=3.0.2
    """
    r = pip(["show", pkg])
    requires = {}
    for line in r.stdout.splitlines():
        if line.startswith("Requires:"):
            deps = line.replace("Requires:", "").strip().split(",")
            for dep in deps:
                dep = dep.strip()
                if not dep:
                    continue
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
    Returns (stderr: str, returncode: int).
    """
    import_name = pkg_name.replace("-", "_")
    r = subprocess.run(
        [VENV_PYTHON, "-W", "all", "-c", f"import {import_name}"],
        capture_output=True, text=True
    )
    return r.stderr, r.returncode


def parse_conflict(stderr):
    """
    Extract conflicting dependency requirements from warning text.
    Returns dict {dep_name: version_spec} or None.
    Protected packages are always excluded.
    """
    results = {}

    patterns = [
        r"[\w\-]+ [\d\.]+ requires ([\w\-]+)([><=!]+[\d\.]+(?:,\s*[><=!]+[\d\.]+)?)",
        r"requires ([\w\-]+)\s+([><=!]+[\d\.]+)",
        r"DependencyWarning.*?([\w\-]+)\s+([><=!]+[\d\.]+)",
    ]

    for pattern in patterns:
        for m in re.finditer(pattern, stderr, re.IGNORECASE):
            groups = m.groups()
            dep_name = groups[0].lower()
            dep_spec = groups[1].strip() if len(groups) > 1 and groups[1] else ""
            if dep_name not in PROTECTED:
                results[dep_name] = dep_spec

    # RequestsDependencyWarning:
    # "urllib3 (2.6.3) or chardet (7.2.0)/charset_normalizer (3.4.6) doesn't match a supported version!"
    # Read version constraints directly from requests/__init__.py source comments
    if "doesn't match a supported version" in stderr:
        rdw_pkgs = re.findall(r"([\w\-]+)\s+\([\d\.]+\)", stderr)
        for p in rdw_pkgs:
            p_lower = p.lower()
            if p_lower not in PROTECTED and p_lower not in results:
                spec = _get_requests_constraint(p_lower)
                results[p_lower] = spec

    return results if results else None


def _get_requests_constraint(pkg_name):
    """
    Read version constraints for chardet/charset_normalizer/urllib3
    from requests/__init__.py assert statements.
    Example: assert (3, 0, 2) <= (major, minor, patch) < (6, 0, 0)
    -> returns ">=3.0.2,<6.0.0"
    """
    try:
        import importlib.util
        spec = importlib.util.find_spec("requests")
        if not spec or not spec.origin:
            return ""
        with open(spec.origin, encoding="utf-8") as f:
            lines = f.readlines()

        # Find the block for this package, then look for assert with version tuple
        pkg_map = {
            "chardet": "chardet_version",
            "charset_normalizer": "charset_normalizer_version",
            "charset-normalizer": "charset_normalizer_version",
            "urllib3": "urllib3_version",
        }
        marker = pkg_map.get(pkg_name)
        if not marker:
            return ""

        # Find the if/elif block for this package
        in_block = False
        for i, line in enumerate(lines):
            if f"if {marker}:" in line or f"elif {marker}:" in line:
                in_block = True
            if in_block:
                # Look for assert with two version tuples: lower <= x < upper
                m = re.search(
                    r"assert\s+\((\d+),\s*(\d+),\s*(\d+)\)\s*<=.*<\s*\((\d+),\s*(\d+),\s*(\d+)\)",
                    line
                )
                if m:
                    lo = f"{m.group(1)}.{m.group(2)}.{m.group(3)}"
                    hi = f"{m.group(4)}.{m.group(5)}.{m.group(6)}"
                    return f">={lo},<{hi}"
                # Single lower bound: assert major >= X
                m2 = re.search(r"assert\s+major\s*>=\s*(\d+)", line)
                if m2:
                    return f">={m2.group(1)}.0.0"
                # Stop after a few lines past the marker
                if i > 0 and "elif " in line and not f"elif {marker}:" in line:
                    break
    except Exception:
        pass
    return ""


def resolve_version(pkg, spec):
    """
    Find the latest available version of pkg that satisfies spec.
    Falls back to plain package name if resolution fails.
    """
    r = pip(["index", "versions", pkg])
    m = re.search(r"Available versions:\s*(.+)", r.stdout)
    if not m:
        return pkg

    # Parse all versions, skip non-standard ones like 6.0.0.post1
    raw_versions = [v.strip() for v in m.group(1).split(",")]
    versions = []
    for v in raw_versions:
        v = v.strip()
        # Keep only clean X.Y.Z versions — skip post/dev/rc suffixes
        if re.match(r"^\d+\.\d+\.?\d*$", v):
            versions.append(v)
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
            lines.append(f"{pkg}=={v}  # protected — managed by Module 4")

    for pkg in check_list:
        v = get_installed_version(pkg)
        if v:
            lines.append(f"{pkg}=={v}")

    from datetime import datetime
    header = (
        "# ComfyUI Master Manager — Stable Dependency Snapshot\n"
        f"# Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        "# DO NOT EDIT MANUALLY — regenerated by Module 6 after each repair.\n\n"
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

    check_list = get_check_list()
    if not check_list:
        print("[WARN] requirements.txt not found or empty. Nothing to check.")
        return 0

    print(f"[INFO] Checking {len(check_list)} package(s) from ComfyUI requirements.txt...")

    failed_packages  = []
    fixed_packages   = []
    skipped_packages = []

    for pkg in check_list:
        stderr, returncode = check_import(pkg)

        if returncode != 0 and "ModuleNotFoundError" in stderr:
            skipped_packages.append(pkg)
            continue

        if "warning" not in stderr.lower():
            continue

        print(f"\n[!] Conflict detected in: {pkg}")

        fixed = False
        for attempt in range(1, MAX_FIX_ITERATIONS + 1):
            conflicts = parse_conflict(stderr)
            if not conflicts:
                fixed = True
                break

            print(f"    Attempt {attempt}/{MAX_FIX_ITERATIONS}: {conflicts}")

            for dep_pkg, dep_spec in conflicts.items():
                if dep_pkg in PROTECTED:
                    print(f"    [SKIP] {dep_pkg} is protected (torch stack)")
                    continue

                if dep_spec:
                    install_target = resolve_version(dep_pkg, dep_spec)
                else:
                    # No spec — check what the parent package actually requires
                    parent_req = get_package_requires(pkg)
                    if dep_pkg in parent_req and parent_req[dep_pkg]:
                        install_target = resolve_version(dep_pkg, parent_req[dep_pkg])
                        print(f"    [INFO] {pkg} requires {dep_pkg}{parent_req[dep_pkg]}")
                    else:
                        install_target = dep_pkg

                print(f"    [FIX] Installing: {install_target}")
                pip(["install", install_target, "--prefer-binary", "--quiet"])

            stderr, returncode = check_import(pkg)
            if "warning" not in stderr.lower():
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
