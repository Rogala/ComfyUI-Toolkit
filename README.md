# ComfyUI-Toolkit

> A set of Windows tools for installing, managing, updating, switching versions, and running
> ComfyUI + the PyTorch stack in a Python venv virtual environment for NVIDIA GPUs.

---


> [!WARNING]
> **Before running the scripts for the first time:**
> - Remove the legacy **Python Launcher** if installed (Settings → Apps → search "Python Launcher")
> - Remove any manually installed standalone Python versions to avoid PATH conflicts
> - Let the toolkit install and manage Python through **Python Manager** (`pymanager`)
>
> Skipping this step is the most common cause of setup failures. See [Troubleshooting](#troubleshooting) for details.

## What is this?

**ComfyUI-Toolkit** automates everything around ComfyUI on Windows: setting up the environment
from scratch, switching Python versions, managing the PyTorch/CUDA stack, repairing dependency
conflicts, and launching ComfyUI — all from a single `.bat` file.

This is **not a portable version**. It is a locally cloned ComfyUI running inside a Python
virtual environment (venv). All packages are isolated inside the venv and do not affect your
system Python or any other software on your machine.

Designed for users who are comfortable with a console and want to understand what is happening
under the hood — the toolkit handles the routine work of setup and maintenance, but nothing
is hidden from you.

Manual package management is always available through the built-in venv console (option 8).

---

## Who is it for?

- Users taking their first steps with a local ComfyUI setup who want a clean, guided process
- Power users who switch between PyTorch / CUDA versions or test new ComfyUI releases
- Anyone who has broken their venv and needs a reliable repair tool
- Users who install many custom nodes and deal with dependency conflicts

---

## Requirements

- Windows 10 / 11 (64-bit)
- NVIDIA GPU with CUDA support
- Internet connection (required at all times — for installs, updates, and fetching version lists)
- PowerShell 5.1+ (included in Windows 10/11)
- Administrator rights (Environment script only — see note below)

> **Why administrator rights?**
> `ComfyUI-Environment.ps1` installs system-level software: Git for Windows, Python Manager (`pymanager`),
> and Visual C++ Runtime. These require elevated privileges — the same as any standard installer
> you download from the web. The script does not modify anything outside of these installations
> and the folder you place it in. You can review the full source code before running it.

---

## File structure

Place all four files in an **empty folder on a fast drive (SSD or NVMe), preferably not the
system drive**, as ComfyUI models and the venv can take tens of gigabytes:

```
your-folder/          <- recommended: fast non-system SSD/NVMe drive
│
├── start_comfyui.bat            <- main launcher, start here
├── ComfyUI-Environment.ps1      <- installs and manages the environment
├── ComfyUI-Manager.ps1          <- manages PyTorch, ComfyUI versions, repairs deps
├── smart_fixer.py               <- auto dependency guard (used by Manager internally)
│
│   -- created automatically --
│
├── ComfyUI/                     <- cloned by Environment script
├── venv/                        <- created by Environment script
├── output/                      <- created by launcher on first run (your generated images)
└── .cache/                      <- created by Manager (logs, snapshots, temp files)
    ├── history.log              <- timestamped log of all Manager operations
    ├── env_state.log            <- last environment info snapshot
    ├── const.txt                <- stable dependency snapshot used as pip constraint
    └── smart_fixer.py           <- deployed here automatically by Manager
```

> **Why is `output/` next to the `.bat` and not inside `ComfyUI/`?**
> If you delete or reinstall the `ComfyUI/` folder, everything inside it is gone.
> Keeping generated images at the root level means they survive any reinstall.

---

## Quick start

### First run (nothing installed yet)

1. Place all four files in an empty folder
2. Run `start_comfyui.bat`
3. The launcher detects that `venv` is missing and prompts:

```
[WARN]  Virtual environment not found: .\venv\Scripts\activate.bat
[INFO]  This is probably your first run. The environment has not been set up yet.

 To get started, ComfyUI-Environment.ps1 must be run first.
 It will install all required software, create the venv,
 clone ComfyUI and install ComfyUI-Manager.

Run ComfyUI-Environment.ps1 now? (Y/N):
```

4. Press `Y` — the Environment script runs, sets everything up, then the launcher restarts
5. Choose option `6` to open **ComfyUI-Manager.ps1**, then:
   - `[1]` install the PyTorch stack
   - `[2]` select your ComfyUI version (this syncs all dependencies)
6. Choose option `1` or `2` to launch ComfyUI

---

## start_comfyui.bat

The main entry point. Activates the venv once at startup and keeps it active for all actions.
Creates the `output/` folder automatically on first run if it does not exist.

```
 --- ComfyUI Multi-Launcher ---
 --- Launch ---
 1. Normal
 2. Normal + fast
 ----------------------------------------------------
 --- Tools ---
 5. Setup environment    (ComfyUI-Environment.ps1)
 6. Manage packages      (ComfyUI-Manager.ps1)
 7. Install ComfyUI-Manager
 8. venv console         (pip / manual install)
 9. ComfyUI help         (--help)
 0. Exit
```

### Launch modes

**1. Normal** — standard ComfyUI launch with base arguments from `COMMON_ARGS`.

**2. Normal + fast** — adds `--fast` which enables faster attention and other optimizations
available in recent ComfyUI versions.

### COMMON_ARGS

At the top of the `.bat` file there is a shared argument string applied to all launch modes:

```bat
set "COMMON_ARGS=--output-directory .\output"
```

You can extend it with any ComfyUI flags that should always be active.
For a full list of available flags use option `9` (ComfyUI help) in the launcher.

Some common examples:

```bat
:: --listen            : allow connections from other devices on the network
:: --reserve-vram 0.5  : keep 0.5 GB VRAM free for the OS
:: --enable-manager    : enable ComfyUI-Manager plugin on startup
:: --lowvram           : for GPUs with limited VRAM
:: --preview-method auto : enable latent previews during generation
```

### Adding a custom launch mode

You need to edit **3 places** in the file, all clearly marked with comments `PLACE 1`, `PLACE 2`, `PLACE 3`:

```bat
:: PLACE 1 — add to the menu echo block
echo  3. Sage Attention + fast

:: PLACE 2 — add a condition
if "%choice%"=="3" goto RUN_SAGE_FAST

:: PLACE 3 — add the launch block
:RUN_SAGE_FAST
echo [STEP] Starting ComfyUI - Sage Attention + fast...
python "%MAIN_PY%" %COMMON_ARGS% --use-sage-attention --fast
pause
goto MENU
```

### Option 7 — Install ComfyUI-Manager

Clones [ComfyUI-Manager](https://github.com/Comfy-Org/ComfyUI-Manager) into
`ComfyUI/custom_nodes/` without launching any external script.
Detects if it is already installed and skips if so.

### Option 8 — venv console

Opens an interactive console **inside the venv**. All `pip` commands install packages
into the venv only — not into the global system Python. Type `exit` to return to the menu.

---

## ComfyUI-Environment.ps1

Manages the full lifecycle of the base environment.

```
  Select action:

    1  Install  - fresh setup: py launcher, git, vc++, python, venv, ComfyUI
    2  Update   - update git + python minor; venv and ComfyUI not touched
    3  Swap     - change Python branch; recreates venv, ComfyUI not touched
    0  Exit
```

### Install

Runs in order:

1. **Python Manager** (`pymanager`) — downloads and installs if missing. Note: this is the NEW launcher from python.org, different from the legacy **Python Launcher**. If you have the legacy one installed, remove it first (see Troubleshooting)
2. **Git for Windows** — downloads latest release from GitHub if missing
3. **Visual C++ Runtime** — installs if missing
4. **Python** — lets you pick a branch (e.g. 3.12) from the online list, installs if needed
5. **venv** — creates a clean virtual environment under the selected Python version
6. **ComfyUI** — clones from the official Comfy-Org repository
7. **pip** — upgrades pip inside the venv

### Update

Updates Git and Python minor version only. The venv and ComfyUI folder are not touched.
Useful for keeping base tools current without risking the environment.

### Swap

Deletes the existing venv and recreates it under a different Python branch.
ComfyUI folder is not touched. After a swap, the PyTorch stack must be reinstalled
via **ComfyUI-Manager.ps1** option `[1]`.

---

## ComfyUI-Manager.ps1

Manages the PyTorch stack, ComfyUI version and environment health. Launched via option `6`
in the `.bat` launcher or directly as a PowerShell script.

```
  ComfyUI Master Manager  v0.1
  -----------------------------------
 [1] Change Torch Stack (NVIDIA CUDA)
 [2] Change ComfyUI Version (Tags / Notes)
 [3] Repair Environment (Deep Clean)
 [4] Show Environment Info
 [0] Exit
```

Auto-returns to the main menu after 5 minutes of inactivity.

> **Note on response times:** some operations in this script involve network requests and
> package index lookups which may take 10–30 seconds before output appears:
> - `[1]` fetches the CUDA version list from pytorch.org and queries the PyTorch package index
> - `[2]` runs `git fetch --tags` and optionally queries the GitHub API for release notes
> - `[3]` runs `pip index versions` for each package in requirements.txt during smart_fixer
>
> This is normal — the script is not frozen, it is working.

### [1] Change Torch Stack

- Fetches the list of currently supported CUDA versions dynamically from
  [pytorch.org/get-started/locally](https://pytorch.org/get-started/locally/)
- For each CUDA version shows the 3 most recent available Torch builds
- Installs `torch` + `torchvision` + `torchaudio` as a matched trio
- Syncs `ComfyUI/requirements.txt` afterwards (torch trio excluded)
- Saves a version snapshot to `.cache/const.txt` for future constraint enforcement
- Warns if the new Torch stack conflicts with current ComfyUI requirements
- Warns if custom nodes are installed (they may not work with the new stack)
- Automatically runs **Repair Environment** after install to resolve any dependency conflicts

### [2] Change ComfyUI Version

Two-level selection: branch (e.g. `v0.18`) then patch version (e.g. `v0.18.3`).

- Optionally fetches and displays release notes from GitHub before switching
- Checks if `requirements.txt` for the target version references the protected torch stack
- Detects downgrades and offers to delete the ComfyUI database to avoid migration errors
  (database stores only asset cache and job history — no workflows or models)
- Installs dependencies with the torch stack fully excluded
- Automatically runs **Repair Environment** after install to resolve any dependency conflicts

### [3] Repair Environment

Deep clean and smart dependency resolution in 6 steps.
Runs automatically after options `[1]` and `[2]`, and can also be run manually — for example
after installing custom nodes that break dependencies.

```
[1/6] Capturing environment snapshot
[2/6] Cleaning broken pip cache entries  (torch cache preserved — it is 2 GB+)
[3/6] Removing broken venv artifacts     (orphaned .dist-info, __pycache__, ~* temps)
[4/6] Running Smart Dependency Guard     (smart_fixer.py)
[5/6] Applying stable constraints        (const.txt as pip constraint)
[6/6] Repair summary                     (before/after diff of changed packages)
```

Shows which packages changed and whether any conflicts remain unresolved.
If a conflict cannot be fixed, it is likely caused by an incompatible custom node —
the output will tell you what to do.

### [4] Show Environment Info

Displays a full snapshot of the current environment and saves it to `.cache/env_state.log`.
Also shows the status of all major accelerators:

```
  --- System Environment Info ---
  ComfyUI:         v0.18.3 (a1b2c3d)
  GPU / CUDA:      NVIDIA GeForce RTX 5060 Ti (16.0 GB VRAM, Driver 572.16, CUDA 13.0)
  CPU Info:        Intel Core i9-13900K (24C/32T)
  RAM Size:        64.0 GB
  Python Version:  3.14.3
  Torch:           2.10.0+cu130
  Torchaudio:      2.10.0+cu130
  Torchvision:     0.22.0+cu130
  Triton:          Not installed
  Xformers:        Not installed
  Flash-Attn:      Not installed
  Sage-Attn 2:     Not installed
  Sage-Attn 3:     Not installed
```

---

## smart_fixer.py

Internal tool — **not called directly**. Deployed automatically to `.cache/` by the Manager
when the Repair function runs.

What it does:

- Reads `ComfyUI/requirements.txt` to build the package check list
- Imports each package in a subprocess with all warnings enabled
- Detects `DependencyWarning` — parses the conflicting package and required version
- Resolves and installs a satisfying version (up to 5 retry attempts per package)
- If all conflicts resolved — writes a stable snapshot to `.cache/const.txt`

Protected packages — **never modified** by smart_fixer or any repair tool:

| Package | Reason |
|---|---|
| `torch` | CUDA build — not resolvable from standard PyPI index |
| `torchvision` | must match torch version exactly |
| `torchaudio` | must match torch version exactly |

These can only be changed via **option [1] Change Torch Stack**.

---

## Accelerators (optional)

Accelerators such as Triton, xFormers, SageAttention and Flash Attention are **not installed
automatically**. They must be installed manually using the venv console (option 8 in the launcher).

You need to select a pre-built wheel that matches your exact combination of
**Python version + Torch version + CUDA version**. Use option `[4] Show Environment Info`
in the Manager to see your current versions before choosing a package.

**Official sources:**

| Accelerator | Source |
|---|---|
| Triton (Windows) | https://github.com/triton-lang/triton-windows |
| SageAttention | https://github.com/woct0rdho/SageAttention |
| xFormers | https://github.com/facebookresearch/xformers |
| Flash Attention | https://github.com/Dao-AILab/flash-attention |

**Pre-built wheels collections:**

| Collection | Notes |
|---|---|
| https://github.com/wildminder/AI-windows-whl | Large collection of pre-built Windows wheels |
| https://github.com/Rogala/AI_Attention | Builds optimized for RTX 5xxx Blackwell architecture |

**Installation example (from venv console, option 8):**

```bat
pip install <path-to-wheel-file>.whl
```

or directly from a URL if the source provides one.

---

## Notes

- The `.ps1` files are already saved with **UTF-8 BOM** encoding — do not change the encoding
  when editing them, otherwise PowerShell will fail to parse them correctly on Windows
- `const.txt` is regenerated after every successful repair or torch install — do not edit manually
- The `.bat` launcher activates the venv once at startup and keeps it active for the entire session
- `.cache/` and `output/` are created automatically — you do not need to create them manually

---


## Troubleshooting

### Python version list unavailable during Install

**Symptom:**
```
[ERROR] Could not retrieve Python version list.
[WARN] Install aborted: no Python version selected.
```

**Cause:**
You have the legacy **Python Launcher** (`py.exe`) installed on your system.
The toolkit uses the new **Python Manager** (`pymanager`) which has a different command syntax.
When both are present, the old launcher takes priority and `py list --online` fails.

**Fix:**
1. Open **Settings → Apps → Installed Apps**
2. Search for **"Python Launcher"**
3. Uninstall it
4. Open a new terminal window
5. Run the Environment script again

> Your existing Python installations are **not affected** — only the old launcher is removed.
> Windows will confirm this with the message:
> *"If you have already installed the Python install manager, open Installed Apps and remove
> 'Python Launcher' to enable the new py.exe command."*

---


### Python already installed system-wide (without Python Launcher)

**Symptom:**
The Environment script runs without errors but the venv ends up using a wrong Python version,
or `py -3.12` calls a different Python than expected.

**Cause:**
If Python was installed manually (not through the Python Manager), it registers itself in PATH
directly. When `py -X.XX` is called, there may be a conflict between the system Python and
the one managed by `pymanager`.

**Fix:**
1. Open a new terminal and run:
```
py list
where python
where py
```
2. Make sure `py` points to the Python Manager version, not a manually installed one
3. If there is a conflict — open **Settings → Apps → Installed Apps**, find any manually
   installed Python versions (e.g. **Python 3.12.x**) and uninstall them
4. Let Python Manager handle all Python versions — it is designed to coexist cleanly

> **Note:** Uninstalling a system Python will not affect the toolkit venv once it is created —
> the venv is self-contained. But for a clean first install it is better to have only
> Python Manager managing your Python versions.

---

### General recommendation before first install

Before running `ComfyUI-Environment.ps1` for the first time, make sure your system does not
have conflicting Python tooling:

- **Python Launcher (legacy)** — remove it if present (see above)
- **Other Python versions installed system-wide** — they will not be affected by the toolkit,
  but if you have `PIP_CONSTRAINT` or other environment variables set globally they may
  interfere with the venv setup

The toolkit manages everything inside its own folder and venv — it does not touch your
system Python or any other Python projects on your machine.

---

---

## Українська секція


> [!WARNING]
> **Перед першим запуском скриптів:**
> - Видали старий **Python Launcher** якщо встановлений (Параметри → Програми → пошук "Python Launcher")
> - Видали будь-які вручну встановлені версії Python щоб уникнути конфліктів PATH
> - Дай toolkit встановити Python через **Python Manager** (`pymanager`)
>
> Пропуск цього кроку — найпоширеніша причина помилок при встановленні. Дивись розділ [Вирішення проблем](#вирішення-проблем).

### Що це

**ComfyUI-Toolkit** — набір інструментів для Windows що автоматизує все навколо ComfyUI:
встановлення середовища з нуля, перемикання версій Python та PyTorch, керування залежностями
та запуск ComfyUI — все з одного `.bat` файлу. Тільки для відеокарт NVIDIA.

Це **не портативна версія**. Це локально клонований ComfyUI що працює всередині
віртуального середовища Python (venv). Всі пакети ізольовані у venv і не впливають
на системний Python або будь-яке інше програмне забезпечення на твоєму комп'ютері.

Призначено для користувачів які не бояться консолі і хочуть розуміти що відбувається —
toolkit бере на себе рутину налаштування та обслуговування, але нічого не приховує.

Ручне керування пакетами доступне в будь-який момент через вбудовану консоль venv (пункт 8).

### Для кого

- Для тих хто робить перші кроки з локальним ComfyUI і хоче чистий покроковий процес
- Для досвідчених користувачів що перемикаються між версіями PyTorch / CUDA або тестують нові релізи
- Для тих хто зламав venv і потребує надійного інструменту відновлення
- Для тих хто використовує багато custom nodes і стикається з конфліктами залежностей

### Вимоги

- Windows 10 / 11 (64-bit)
- Відеокарта NVIDIA з підтримкою CUDA
- Інтернет-з'єднання (потрібне постійно — для встановлення, оновлень та отримання списків версій)
- PowerShell 5.1+ (вбудований в Windows 10/11)
- Права адміністратора (тільки для скрипту Environment)

> **Чому потрібні права адміністратора?**
> `ComfyUI-Environment.ps1` встановлює системні програми: Git for Windows, Python Manager (`pymanager`)
> та Visual C++ Runtime. Це вимагає підвищених привілеїв — так само як будь-який стандартний
> інсталятор. Скрипт не змінює нічого за межами цих встановлень і папки де він знаходиться.
> Ти можеш переглянути весь вихідний код перед запуском.

### Структура папки

Поклади всі чотири файли в **порожню папку на швидкому диску (SSD або NVMe), бажано не
системному** — ComfyUI з моделями та venv займають десятки гігабайт:

```
ваша-папка/          <- рекомендовано: швидкий не системний SSD/NVMe
│
├── start_comfyui.bat            <- головний лаунчер, починай тут
├── ComfyUI-Environment.ps1      <- встановлення та керування середовищем
├── ComfyUI-Manager.ps1          <- PyTorch, версії ComfyUI, ремонт залежностей
├── smart_fixer.py               <- авто-ремонт залежностей (викликається Manager-ом)
│
├── ComfyUI/                     <- створюється скриптом Environment
├── venv/                        <- створюється скриптом Environment
├── output/                      <- створюється лаунчером (твої згенеровані зображення)
└── .cache/                      <- створюється Manager-ом (логи, знімки стану)
```

> Папка `output/` знаходиться поруч з `.bat` а не всередині `ComfyUI/` — щоб зображення
> не загубились при видаленні або перевстановленні папки `ComfyUI/`.

### Перший запуск

1. Поклади всі чотири файли в порожню папку
2. Запусти `start_comfyui.bat`
3. Лаунчер виявить відсутність `venv` і запропонує одразу запустити `ComfyUI-Environment.ps1`
4. Підтверди — середовище встановиться автоматично, лаунчер перезапуститься
5. Вибери пункт `6` щоб відкрити `ComfyUI-Manager.ps1`, потім:
   - `[1]` встанови PyTorch стек
   - `[2]` вибери версію ComfyUI (це синхронізує всі залежності)
6. Вибери пункт `1` або `2` для запуску ComfyUI

### Прискорювачі (опціонально)

Triton, xFormers, SageAttention та Flash Attention **не встановлюються автоматично**.
Їх треба встановити вручну через консоль venv (пункт 8 в лаунчері).

Перед вибором пакету перевір свої версії через пункт `[4] Show Environment Info` в Manager —
потрібно підібрати білд під точну комбінацію **Python + Torch + CUDA**.

Офіційні джерела та збірки білдів — дивись секцію **Accelerators** вище.


### Вирішення проблем

**Помилка: список версій Python недоступний під час Install**

Симптом: `[ERROR] Could not retrieve Python version list.`

Причина: в системі встановлений старий **Python Launcher** (legacy `py.exe`) який конфліктує
з новим **Python Manager**. Видали його через **Параметри → Програми → Встановлені програми**,
знайди **"Python Launcher"** і видали. Існуючі версії Python не постраждають.


**Python вже встановлений в системі (без Python Launcher)**

Симптом: venv створюється від не тієї версії Python, або `py -3.12` викликає не той інтерпретатор.

Причина: Python встановлений вручну прописує себе в PATH напряму і може конфліктувати з Python Manager.

Виправлення:
1. Перевір командами `py list`, `where python`, `where py` — що саме викликається
2. Якщо є конфлікт — видали вручну встановлені версії Python через **Параметри → Програми**
3. Дай Python Manager керувати всіма версіями Python — він для цього і призначений

**Загальна рекомендація перед першим встановленням**

Перед запуском `ComfyUI-Environment.ps1` переконайся що в системі немає старого Python Launcher.
Якщо Windows показує повідомлення про legacy `py.exe` — це саме та проблема.

### Важливо

- Це не портативна версія — це повноцінний локальний ComfyUI у venv
- Інтернет потрібен завжди — без нього встановлення та оновлення не працюватимуть
- Файли `.ps1` вже збережені з кодуванням **UTF-8 BOM** — не змінюй кодування при редагуванні
- `const.txt` перегенеровується після кожного успішного ремонту або встановлення torch — не редагуй вручну
- Захищені пакети (`torch`, `torchvision`, `torchaudio`) змінюються тільки через пункт `[1]` в Manager
- Деякі операції в Manager можуть займати 10–30 секунд без виводу — це нормально, скрипт не завис
- Ремонт залежностей запускається автоматично після встановлення torch або зміни версії ComfyUI
