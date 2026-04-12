# ComfyUI Toolkit

> Windows tools for installing, managing, updating, switching versions, and running
> ComfyUI with the PyTorch stack in a Python virtual environment — for NVIDIA GPUs.

---

- [English](#english)
- [Українська](#українська)

---

# English

## What is this?

**ComfyUI Toolkit** automates everything around ComfyUI on Windows: setting up the environment
from scratch, switching Python versions, managing the PyTorch/CUDA stack, repairing dependency
conflicts, and launching ComfyUI — all from a single `.bat` file.

This is **not a portable version**. It is a locally cloned ComfyUI running inside a Python
virtual environment (venv). All packages are isolated inside the venv and do not affect your
system Python or any other software on your machine.

Designed for users who are comfortable with a console and want to understand what is happening
under the hood. The toolkit handles the routine work of setup and maintenance, but nothing
is hidden from you. Manual package management is always available through the built-in
venv console.

## Who is it for?

- Users taking their first steps with a local ComfyUI setup who want a clean, guided process
- Power users who switch between PyTorch / CUDA versions or test new ComfyUI releases
- Anyone who has broken their venv and needs a reliable repair tool
- Users who install many custom nodes and deal with dependency conflicts

## Requirements

- Windows 10 / 11 (64-bit)
- NVIDIA GPU with CUDA support
- Internet connection (required for installs, updates, and fetching version lists)
- PowerShell 5.1+ (built into Windows 10/11)
- Administrator rights — **only for the first install** of Python Manager, Git, and VC++ Runtime

## File structure

Place both files in an **empty folder on a fast drive (SSD or NVMe), preferably not the
system drive** — ComfyUI with models and the venv can take tens of gigabytes:

```
your-folder/                    ← recommended: fast non-system SSD/NVMe
│
├── start_comfyui.bat           ← entry point — double-click to launch
├── comfyui.ps1                 ← all logic lives here
│
│   — created automatically —
│
├── ComfyUI/                    ← cloned by [E] Install
├── venv/                       ← created by [E] Install
├── output/                     ← created on first launch (your generated images)
└── .cache/                     ← created automatically
    ├── smart_fixer.py          ← deployed from comfyui.ps1 on startup
    ├── const.txt               ← stable dependency snapshot (pip constraint)
    ├── settings.json           ← language preference
    ├── history.log             ← timestamped log of all operations
    ├── release_notes.log       ← ComfyUI release notes fetched during version switch
    └── env_state.log           ← last [I] Info snapshot
```

> **Why is `output/` next to the `.bat` and not inside `ComfyUI/`?**
> If you delete or reinstall the `ComfyUI/` folder, everything inside it is gone.
> Keeping generated images at the root level means they survive any reinstall.

> **Why only two files?**
> `smart_fixer.py` is embedded inside `comfyui.ps1` as a here-string and deployed
> to `.cache/` automatically on startup. You do not need to manage it manually.

## Before the first run

> [!WARNING]
> **Remove the legacy Python Launcher** if installed before running the toolkit.
> Go to **Settings → Apps → Installed Apps**, search for **"Python Launcher"** and uninstall it.
> The toolkit uses the new **Python Manager** (`pymanager`) which conflicts with the legacy one.
> Your existing Python installations are **not affected** — only the old launcher is removed.

Also remove any manually installed standalone Python versions to avoid PATH conflicts.
Let the toolkit install and manage Python through Python Manager.

## Quick start

### First run (nothing installed yet)

1. Place `start_comfyui.bat` and `comfyui.ps1` in an empty folder
2. Double-click `start_comfyui.bat`
3. The launcher detects that `venv` is missing and prompts to run the install
4. Confirm — the install flow runs automatically
5. After install: press **[T]** to set up the PyTorch stack
6. Press **[V]** to select a ComfyUI version (this syncs all dependencies)
7. Press **[1]** to launch ComfyUI

### Subsequent runs

Double-click `start_comfyui.bat` → press **[1]** or **[2]** to launch.

---

## Interface

The launcher opens a **PowerShell window** with full Unicode and color support.
Navigation is by **single keypress** — no Enter needed.

### Header

```
  ==============================================================
    ComfyUI Launcher                                       [UK]
  ==============================================================

   Python 3.12.10 ✓   ComfyUI v0.18.5 ✓   PyTorch 2.11.0+cu130

  Press [L] to change language Language (EN UK)

   * Update available: v0.19.0
```

- **Python / ComfyUI** — green badge if found, red if missing
- **PyTorch** — cyan badge with version and CUDA suffix, red if missing
- **`[UK]`** — current interface language code shown in the title bar
- **Language hint** — shows current language name; press `[L]` to switch
- **`* Update available`** — appears when a newer ComfyUI release is detected on GitHub
  (checked once per session in the background, no delay on menu draw)

### Language

Press **`[L]`** at any time to toggle between two languages:

`EN ↔ UK`

The selection is saved automatically to `.cache/settings.json` and restored on next launch.
On first run the language is detected from your system locale (`Get-Culture`).

Technical log lines (`[OK]`, `[WARN]`, `[ERROR]`, `[STEP]`) are always in English
regardless of the selected language — this makes it easier to search for errors online.

---

## Menu reference

### Launch

| Key | Name | Description |
|-----|------|-------------|
| `1` | Normal | Standard ComfyUI launch with `COMMON_ARGS` |
| `2` | Fast | Adds `--fast` (experimental speed optimizations) |

**Adding a custom launch mode** — edit `comfyui.ps1`, find `$LAUNCH_MODES` in `#region CONFIG`
and add one line:

```powershell
@{ Key="3"; LabelKey="menu.lowvram.label"; DescKey="menu.lowvram.desc"; Args=@("--lowvram") }
```

The menu rebuilds automatically. No other changes needed.

**Shared arguments** — edit `$COMMON_ARGS` in `#region CONFIG`:

```powershell
$COMMON_ARGS = @("--output-directory", ".\output", "--listen", "--reserve-vram", "0.5")
```

---

### Environment `[E] [U] [S]`

#### `[E]` Install ★ Administrator required

Full fresh setup. A UAC prompt will appear — this is expected.

**Admin-only steps** (run in a separate elevated window that closes automatically):
1. **Python Manager** (`pymanager`) — new-generation Python version manager from python.org
2. **Git for Windows** — latest release from GitHub
3. **Visual C++ Runtime** — if not already installed

**User-level steps** (run in the main window after the elevated window closes):

4. **Python version** — interactive selection from the online list (stable releases only, no dev/alpha/beta); installs if not present locally
5. **venv** — created under the selected Python version
6. **pip** — upgraded inside the venv
7. **ComfyUI** — cloned from the official Comfy-Org repository

After install: use **[T]** to install PyTorch, then **[V]** to select a ComfyUI version.

> **Why administrator rights?**
> Python Manager and Git write to system PATH. VC++ Runtime writes to the system registry.
> These are standard installer operations — the same as any software you download from the web.
> Everything else (venv, pip, ComfyUI) runs as your normal user account.

#### `[U]` Update

Updates Git and Python minor version only. The venv and ComfyUI folder are not touched.

- Git: checks latest release on GitHub, reports if update requires admin (use `[E]` Install)
- Python: `py install X.Y --update` via Python Manager — no admin required for minor updates
- pip: upgraded inside the venv

#### `[S]` Swap Python

Changes the Python version used by the venv. The ComfyUI folder is not touched.

**Safe order of operations:**
1. Select new Python version (interactive, stable releases only)
2. Confirm the destructive action
3. Delete old venv
4. Create new venv under selected version
5. Upgrade pip

> After a swap, PyTorch and all pip packages must be reinstalled.
> Use **[T]** to reinstall PyTorch, then **[V]** to resync ComfyUI requirements.

---

### Packages `[T] [V] [R]`

#### `[T]` Torch — Change PyTorch / CUDA stack

Two-level selection: CUDA version → PyTorch version.

- CUDA version list is fetched dynamically from `docs.pytorch.org`
- PyTorch version list is fetched via `pip index versions` from the PyTorch index (stable, documented)
- Installs `torch` + `torchvision` + `torchaudio` + `torchsde` as a matched set
- Syncs `ComfyUI/requirements.txt` afterwards (torch stack excluded to avoid conflicts)
- Saves a version snapshot to `.cache/const.txt`
- Runs **[R] Repair** automatically after install

**Protected packages** — never modified by any repair or install operation:

| Package | Reason |
|---------|--------|
| `torch` | CUDA build — not resolvable from standard PyPI |
| `torchvision` | must match torch version exactly |
| `torchaudio` | must match torch version exactly |
| `torchsde` | torch-coupled, version-sensitive |
| `comfyui-workflow-templates` | managed separately during version switch |

#### `[V]` ComfyUI — Switch version

Two-level selection: branch (e.g. `v0.18`) → patch version (e.g. `v0.18.5`).

- Fetches all tags via `git fetch --tags`
- Optionally fetches and displays release notes from GitHub API before switching; saves to `.cache/release_notes.log`
- Detects downgrades and offers to delete the database to avoid migration errors
  *(database stores only asset cache and job history — no workflows or models)*
- Installs `requirements.txt` for the target version with torch stack excluded
- Warns if the target version is below `v0.13.0` (minimum recommended)
- Runs **[R] Repair** automatically after switching

#### `[R]` Repair — Auto dependency fix

Deep clean and smart dependency resolution in 8 steps.
Runs automatically after **[T]** and **[V]**, and can be triggered manually —
for example after installing custom nodes that break dependencies.

```
[1/8] Capturing environment snapshot
[2/8] Cleaning broken pip cache entries    (torch cache preserved — 2 GB+)
[3/8] Removing broken venv artifacts       (orphaned .dist-info, __pycache__, ~* temps)
[4/8] Running Smart Dependency Guard       (smart_fixer.py)
[5/8] Updating comfyui-workflow-templates  (ensures sub-packages are current)
[6/8] Installing missing transitive deps   (packages required by installed packages)
[7/8] Applying stable constraints          (const.txt as pip constraint)
[8/8] Repair summary                       (before/after diff of changed packages)
```

**Smart Dependency Guard** (`smart_fixer.py`) — how it works:

1. Runs `pip check` to find all dependency conflicts (stable, machine-readable output)
2. For each conflict: queries `pip index versions` to find a satisfying version
3. Installs the resolved version, retries up to 5 times per package
4. If all conflicts resolved — writes a stable snapshot to `const.txt`
5. `const.txt` is then applied as a `PIP_CONSTRAINT` for all future pip operations

If a conflict cannot be resolved, it is likely caused by an incompatible custom node.
The output will tell you which package is the source and suggest using ComfyUI-Manager
to disable or downgrade the problematic node.

---

### Tools `[I] [C] [M] [H]`

#### `[I]` Info — Environment snapshot

Displays full environment info and saves to `.cache/env_state.log`:

```
ComfyUI:         v0.18.5 (7782171a)
GPU:             NVIDIA GeForce RTX 5060 Ti (16.0 GB VRAM, Driver 595.79, CUDA 13.2)
CPU:             12th Gen Intel Core i3-12100F (4C/8T)
RAM:             64.0 GB
Python:          3.12.10
PyTorch:         2.11.0+cu130
Torchaudio:      2.11.0+cu130
Torchvision:     0.26.0+cu130
Triton:          not installed
xFormers:        not installed
Flash-Attn:      not installed
SageAttn 2:      not installed
SageAttn 3:      not installed
```

#### `[C]` Console — venv shell

Opens an interactive shell with the venv activated.
All `pip` commands install into the venv only — not into the global system Python.

If `.cache/const.txt` exists, a reminder is shown that you can use it as a constraint:
```
pip install <package> -c .cache\const.txt
```

Type `exit` and press Enter to return to the menu.

#### `[M]` ComfyUI-Manager — Install plugin

Clones [ComfyUI-Manager](https://github.com/Comfy-Org/ComfyUI-Manager) into
`ComfyUI/custom_nodes/` if not already installed. Detects existing installation and skips.

#### `[H]` Help

Runs `python main.py --help` and shows all available ComfyUI command-line flags.

---

## Accelerators (optional)

Triton, xFormers, SageAttention, and Flash Attention are **not installed automatically**.
Install them manually via the venv console **[C]**.

Before choosing a wheel, check your exact versions via **[I] Info** —
you need a build matching your exact **Python + PyTorch + CUDA** combination.

| Accelerator | Source |
|-------------|--------|
| Triton (Windows) | https://github.com/triton-lang/triton-windows |
| SageAttention | https://github.com/woct0rdho/SageAttention |
| xFormers | https://github.com/facebookresearch/xformers |
| Flash Attention | https://github.com/Dao-AILab/flash-attention |

**Pre-built wheels for RTX 5xxx Blackwell:**
https://github.com/Rogala/AI_Attention

**Installation via venv console [C]:**
```
pip install <path-to-wheel>.whl
```

---

## Developer notes

### Adding a language

Open `comfyui.ps1`, find `#region I18N`. Add your language code to `$script:LangCycle`
and a new column to each row in `$T`:

```powershell
$script:LangCycle = @('en','uk','de')

$T = @{
  'section.launch' = @{ en='Launch'; uk='Запуск'; de='Starten' }
  ...
}
```

### Encoding

`comfyui.ps1` must be saved as **UTF-8 with BOM** (`UTF-8 BOM`).
PowerShell 5.1 on Windows requires BOM to correctly parse files with non-ASCII characters.
Most editors (VS Code, Notepad++) have this as a save option.

### const.txt

`const.txt` is regenerated after every successful repair or torch install.
Do not edit manually — it is overwritten automatically.

The file is used as a `PIP_CONSTRAINT` — pip will refuse to install versions
that conflict with it. This prevents custom node installs from silently
downgrading packages that ComfyUI depends on.

---

## Troubleshooting

### Python version list unavailable during Install

**Symptom:**
```
[ERROR] Could not retrieve Python version list.
```

**Cause:** The legacy **Python Launcher** (`py.exe`) is installed and conflicts with
Python Manager. Both use `py.exe` but with incompatible command syntax.

**Fix:**
1. **Settings → Apps → Installed Apps** → search **"Python Launcher"** → Uninstall
2. Open a new terminal, run the toolkit again

> Your existing Python installations are **not affected**.

---

### Wrong Python version used for venv

**Symptom:** venv uses unexpected Python, or `py -3.12` calls the wrong interpreter.

**Cause:** Python was installed manually (not through Python Manager) and registered
itself in PATH directly, conflicting with Python Manager's version resolution.

**Fix:**
1. Run `py list`, `where python`, `where py` to see what is being called
2. If there is a conflict — uninstall manually installed Python versions via
   **Settings → Apps → Installed Apps**
3. Let Python Manager handle all Python versions

---

### ComfyUI fails to start after downgrade

**Symptom:** ComfyUI crashes on startup with a database migration error.

**Cause:** The database contains migrations from a newer version that the downgraded
ComfyUI does not know about.

**Fix:** Use **[V]** ComfyUI version switcher — it detects downgrades and offers
to delete the database automatically. The database contains only asset cache and
job history, not your workflows or models.

---

### ComfyUI fails to start — `No module named 'torchsde'`

**Symptom:** ComfyUI crashes with `ModuleNotFoundError: No module named 'torchsde'`.

**Cause:** `torchsde` was not installed as part of the PyTorch stack.

**Fix:** Run **[T]** to reinstall PyTorch — `torchsde` is now installed automatically.
Or install manually via **[C]** console:
```
pip install torchsde
```

---

### Custom node breaks dependencies after install

**Symptom:** ComfyUI starts but some nodes fail, or there are import errors.

**Fix:** Run **[R] Repair**. If the conflict cannot be resolved automatically,
the output will identify the problematic package. Use ComfyUI-Manager to
disable or downgrade the custom node that caused the conflict, then run Repair again.

---

---

# Українська

## Що це таке?

**ComfyUI Toolkit** автоматизує все навколо ComfyUI на Windows: встановлення середовища
з нуля, перемикання версій Python, керування стеком PyTorch/CUDA, виправлення конфліктів
залежностей та запуск ComfyUI — все з одного `.bat` файлу.

Це **не портативна версія**. Це локально клонований ComfyUI що працює всередині
віртуального середовища Python (venv). Всі пакети ізольовані у venv і не впливають
на системний Python або будь-яке інше програмне забезпечення на твоєму комп'ютері.

Призначено для користувачів які не бояться консолі і хочуть розуміти що відбувається.
Toolkit бере на себе рутину налаштування та обслуговування, але нічого не приховує.
Ручне керування пакетами доступне в будь-який момент через вбудовану консоль venv.

## Для кого

- Для тих хто робить перші кроки з локальним ComfyUI і хоче чистий покроковий процес
- Для досвідчених користувачів що перемикаються між версіями PyTorch/CUDA або тестують нові релізи
- Для тих хто зламав venv і потребує надійного інструменту відновлення
- Для тих хто використовує багато custom nodes і стикається з конфліктами залежностей

## Вимоги

- Windows 10 / 11 (64-bit)
- Відеокарта NVIDIA з підтримкою CUDA
- Інтернет-з'єднання (потрібне для встановлення, оновлень та отримання списків версій)
- PowerShell 5.1+ (вбудований у Windows 10/11)
- Права адміністратора — **тільки при першому встановленні** Python Manager, Git та VC++ Runtime

## Структура файлів

Поклади обидва файли в **порожню папку на швидкому диску (SSD або NVMe), бажано не
системному** — ComfyUI з моделями та venv займають десятки гігабайт:

```
ваша-папка/                     ← рекомендовано: швидкий не системний SSD/NVMe
│
├── start_comfyui.bat           ← точка входу — подвійний клік для запуску
├── comfyui.ps1                 ← вся логіка тут
│
│   — створюється автоматично —
│
├── ComfyUI/                    ← клонується при [E] Встановлення
├── venv/                       ← створюється при [E] Встановлення
├── output/                     ← створюється при першому запуску (твої згенеровані зображення)
└── .cache/                     ← створюється автоматично
    ├── smart_fixer.py          ← розгортається з comfyui.ps1 при старті
    ├── const.txt               ← знімок стабільних залежностей (pip constraint)
    ├── settings.json           ← збережене налаштування мови
    ├── history.log             ← лог усіх операцій з мітками часу
    ├── release_notes.log       ← release notes ComfyUI при зміні версії
    └── env_state.log           ← останній знімок [I] Інфо
```

> **Чому `output/` поруч з `.bat` а не всередині `ComfyUI/`?**
> Якщо видалити або перевстановити папку `ComfyUI/` — все всередині зникне.
> Зображення на рівні кореня зберігаються при будь-якому перевстановленні.

> **Чому тільки два файли?**
> `smart_fixer.py` вбудований у `comfyui.ps1` як here-string і розгортається
> в `.cache/` автоматично при старті. Керувати ним вручну не потрібно.

## Перед першим запуском

> [!WARNING]
> **Видали старий Python Launcher** якщо встановлений перед запуском toolkit.
> Перейди до **Параметри → Програми → Встановлені програми**, знайди **"Python Launcher"**
> і видали. Toolkit використовує новий **Python Manager** (`pymanager`) який конфліктує
> зі старим. Твої існуючі версії Python **не постраждають** — видаляється тільки старий launcher.

Також видали будь-які вручну встановлені версії Python щоб уникнути конфліктів PATH.
Дозволь toolkit встановлювати Python і керувати ним через Python Manager.

## Швидкий старт

### Перший запуск (нічого не встановлено)

1. Поклади `start_comfyui.bat` та `comfyui.ps1` в порожню папку
2. Подвійний клік на `start_comfyui.bat`
3. Лаунчер виявляє відсутність `venv` і пропонує запустити встановлення
4. Підтвердь — процес встановлення запускається автоматично
5. Після встановлення: натисни **[T]** щоб налаштувати стек PyTorch
6. Натисни **[V]** щоб вибрати версію ComfyUI (це синхронізує всі залежності)
7. Натисни **[1]** щоб запустити ComfyUI

### Наступні запуски

Подвійний клік на `start_comfyui.bat` → натисни **[1]** або **[2]** для запуску.

---

## Інтерфейс

Лаунчер відкривається у **вікні PowerShell** з повною підтримкою Unicode та кольорів.
Навігація — **одним натисканням клавіші**, без Enter.

### Хедер

```
  ==============================================================
    ComfyUI Launcher                                       [UK]
  ==============================================================

   Python 3.12.10 ✓   ComfyUI v0.18.5 ✓   PyTorch 2.11.0+cu130

  Щоб змінити мову натисни [L] Language / Українська: UK  (EN UK)

   * Доступне оновлення: v0.19.0
```

- **Python / ComfyUI** — зелений бейдж якщо знайдено, червоний якщо відсутній
- **PyTorch** — блакитний бейдж з версією та суфіксом CUDA, червоний якщо відсутній
- **`[UK]`** — код поточної мови інтерфейсу в рядку заголовку
- **Підказка мови** — показує назву поточної мови; натисни `[L]` щоб перемкнути
- **`* Доступне оновлення`** — з'являється коли виявлено новішу версію ComfyUI на GitHub
  (перевірка виконується раз на сесію у фоні, затримки при відмальовуванні меню немає)

### Мова

Натискай **`[L]`** в будь-який момент щоб перемикати між двома мовами:

`EN ↔ UK`

Вибір зберігається автоматично в `.cache/settings.json` і відновлюється при наступному запуску.
При першому запуску мова визначається автоматично з системного локалю (`Get-Culture`).

Технічні рядки логу (`[OK]`, `[WARN]`, `[ERROR]`, `[STEP]`) — завжди англійською
незалежно від вибраної мови. Це полегшує пошук помилок в інтернеті.

---

## Довідник меню

### Запуск

| Клавіша | Назва | Опис |
|---------|-------|------|
| `1` | Звичайний | Стандартний запуск ComfyUI з `COMMON_ARGS` |
| `2` | Швидкий | Додає `--fast` (експериментальні оптимізації швидкості) |

**Додати власний режим запуску** — відкрий `comfyui.ps1`, знайди `$LAUNCH_MODES` в `#region CONFIG`
і додай один рядок:

```powershell
@{ Key="3"; LabelKey="menu.lowvram.label"; DescKey="menu.lowvram.desc"; Args=@("--lowvram") }
```

Меню перебудовується автоматично. Більше нічого змінювати не потрібно.

**Спільні аргументи** — відредагуй `$COMMON_ARGS` в `#region CONFIG`:

```powershell
$COMMON_ARGS = @("--output-directory", ".\output", "--listen", "--reserve-vram", "0.5")
```

---

### Середовище `[E] [U] [S]`

#### `[E]` Встановлення ★ Потребує прав адміністратора

Повне встановлення з нуля. З'явиться запит UAC — це очікувана поведінка.

**Кроки з правами адміна** (виконуються в окремому підвищеному вікні яке закривається автоматично):
1. **Python Manager** (`pymanager`) — новий менеджер версій Python від python.org
2. **Git for Windows** — остання версія з GitHub
3. **Visual C++ Runtime** — якщо ще не встановлений

**Кроки від звичайного користувача** (виконуються в основному вікні після закриття підвищеного):

4. **Версія Python** — інтерактивний вибір зі списку онлайн (тільки стабільні версії, без dev/alpha/beta); встановлюється якщо потрібно
5. **venv** — створюється під обраною версією Python
6. **pip** — оновлюється всередині venv
7. **ComfyUI** — клонується з офіційного репозиторію Comfy-Org

Після встановлення: використовуй **[T]** для встановлення PyTorch, потім **[V]** для вибору версії ComfyUI.

> **Чому потрібні права адміністратора?**
> Python Manager і Git записують у системний PATH. VC++ Runtime записує в системний реєстр.
> Це стандартні операції інсталятора — такі самі як у будь-якого програмного забезпечення.
> Все інше (venv, pip, ComfyUI) працює від твого звичайного облікового запису.

#### `[U]` Оновлення

Оновлює тільки Git і мінорну версію Python. Venv і папка ComfyUI не чіпаються.

- Git: перевіряє останній реліз на GitHub, повідомляє якщо оновлення потребує адміна
- Python: `py install X.Y --update` через Python Manager — без адміна
- pip: оновлюється всередині venv

#### `[S]` Swap Python

Змінює версію Python яку використовує venv. Папка ComfyUI не чіпається.

**Безпечний порядок операцій:**
1. Вибір нової версії Python (інтерактивно, тільки стабільні версії)
2. Підтвердження деструктивної дії
3. Видалення старого venv
4. Створення нового venv під обраною версією
5. Оновлення pip

> Після swap потрібно перевстановити PyTorch і всі pip-пакети.
> Використай **[T]** для перевстановлення PyTorch, потім **[V]** для ресинхронізації залежностей ComfyUI.

---

### Пакети `[T] [V] [R]`

#### `[T]` Torch — Змінити стек PyTorch / CUDA

Дворівневий вибір: версія CUDA → версія PyTorch.

- Список версій CUDA отримується динамічно з `docs.pytorch.org`
- Список версій PyTorch отримується через `pip index versions` (стабільний задокументований формат)
- Встановлює `torch` + `torchvision` + `torchaudio` + `torchsde` як узгоджений набір
- Синхронізує `ComfyUI/requirements.txt` після встановлення (стек torch виключається)
- Зберігає знімок версій у `.cache/const.txt`
- Автоматично запускає **[R] Ремонт** після встановлення

**Захищені пакети** — ніколи не змінюються жодною операцією ремонту або встановлення:

| Пакет | Причина |
|-------|---------|
| `torch` | CUDA-збірка — не резолвиться зі стандартного PyPI |
| `torchvision` | повинна точно відповідати версії torch |
| `torchaudio` | повинна точно відповідати версії torch |
| `torchsde` | прив'язана до torch, чутлива до версій |
| `comfyui-workflow-templates` | керується окремо при зміні версії |

#### `[V]` ComfyUI — Переключити версію

Дворівневий вибір: гілка (напр. `v0.18`) → патч-версія (напр. `v0.18.5`).

- Отримує всі теги через `git fetch --tags`
- Опційно показує release notes з GitHub API перед перемиканням; зберігає у `.cache/release_notes.log`
- Виявляє даунгрейди і пропонує видалити базу даних щоб уникнути помилок міграції
  *(база даних містить тільки кеш ресурсів та історію задач — не воркфлоу і не моделі)*
- Встановлює `requirements.txt` для цільової версії з виключенням стека torch
- Попереджає якщо цільова версія нижче `v0.13.0` (мінімально рекомендована)
- Автоматично запускає **[R] Ремонт** після перемикання

#### `[R]` Ремонт — Авторемонт залежностей

Глибоке очищення та розумне вирішення конфліктів залежностей у 8 кроків.
Запускається автоматично після **[T]** і **[V]**, і може бути запущений вручну —
наприклад після встановлення custom nodes які ламають залежності.

```
[1/8] Знімок середовища перед ремонтом
[2/8] Очищення пошкоджених записів pip cache     (кеш torch збережено — 2 ГБ+)
[3/8] Видалення пошкоджених артефактів venv       (orphaned .dist-info, __pycache__, ~* temps)
[4/8] Запуск Smart Dependency Guard               (smart_fixer.py)
[5/8] Оновлення comfyui-workflow-templates        (забезпечує актуальність під-пакетів)
[6/8] Встановлення відсутніх транзитивних залежностей
[7/8] Застосування стабільних обмежень            (const.txt як pip constraint)
[8/8] Підсумок ремонту                            (diff пакетів до/після)
```

**Smart Dependency Guard** (`smart_fixer.py`) — як працює:

1. Запускає `pip check` щоб знайти всі конфлікти залежностей (стабільний машинозчитуваний вивід)
2. Для кожного конфлікту: запитує `pip index versions` щоб знайти відповідну версію
3. Встановлює знайдену версію, повторює до 5 разів на пакет
4. Якщо всі конфлікти вирішено — записує стабільний знімок у `const.txt`
5. `const.txt` застосовується як `PIP_CONSTRAINT` для всіх наступних pip-операцій

Якщо конфлікт не вдається вирішити — скоріш за все причина в несумісному custom node.
Вивід покаже який пакет є джерелом і запропонує використати ComfyUI-Manager
щоб відключити або понизити версію проблемного ноду.

---

### Інструменти `[I] [C] [M] [H]`

#### `[I]` Інфо — Знімок середовища

Виводить повну інформацію про середовище і зберігає у `.cache/env_state.log`:

```
ComfyUI:         v0.18.5 (7782171a)
GPU:             NVIDIA GeForce RTX 5060 Ti (16.0 ГБ VRAM, Driver 595.79, CUDA 13.2)
CPU:             12th Gen Intel Core i3-12100F (4C/8T)
RAM:             64.0 ГБ
Python:          3.12.10
PyTorch:         2.11.0+cu130
Torchaudio:      2.11.0+cu130
Torchvision:     0.26.0+cu130
Triton:          не встановлено
xFormers:        не встановлено
Flash-Attn:      не встановлено
SageAttn 2:      не встановлено
SageAttn 3:      не встановлено
```

#### `[C]` Консоль — venv shell

Відкриває інтерактивну оболонку з активованим venv.
Всі `pip` команди встановлюють пакети тільки у venv — не в системний Python.

Якщо `.cache/const.txt` існує — показується підказка що можна використовувати його як обмеження:
```
pip install <пакет> -c .cache\const.txt
```

Введи `exit` і натисни Enter щоб повернутись до меню.

#### `[M]` ComfyUI-Manager — Встановити плагін

Клонує [ComfyUI-Manager](https://github.com/Comfy-Org/ComfyUI-Manager) у
`ComfyUI/custom_nodes/` якщо ще не встановлено. Виявляє існуючу установку і пропускає.

#### `[H]` Довідка

Запускає `python main.py --help` і показує всі доступні прапори командного рядка ComfyUI.

---

## Прискорювачі (опціонально)

Triton, xFormers, SageAttention та Flash Attention **не встановлюються автоматично**.
Встанови їх вручну через консоль venv **[C]**.

Перед вибором колеса перевір свої точні версії через **[I] Інфо** —
потрібна збірка під точну комбінацію **Python + PyTorch + CUDA**.

| Прискорювач | Джерело |
|-------------|---------|
| Triton (Windows) | https://github.com/triton-lang/triton-windows |
| SageAttention | https://github.com/woct0rdho/SageAttention |
| xFormers | https://github.com/facebookresearch/xformers |
| Flash Attention | https://github.com/Dao-AILab/flash-attention |

**Збірки для RTX 5xxx Blackwell:**
https://github.com/Rogala/AI_Attention

**Встановлення через консоль venv [C]:**
```
pip install <шлях-до-файлу>.whl
```

---

## Нотатки для розробників

### Додати мову

Відкрий `comfyui.ps1`, знайди `#region I18N`. Додай код мови у `$script:LangCycle`
і нову колонку у кожен рядок `$T`:

```powershell
$script:LangCycle = @('en','uk','de')

$T = @{
  'section.launch' = @{ en='Launch'; uk='Запуск'; de='Starten' }
  ...
}
```

### Кодування файлу

`comfyui.ps1` повинен бути збережений у кодуванні **UTF-8 з BOM** (`UTF-8 BOM`).
PowerShell 5.1 на Windows потребує BOM для коректного парсингу файлів з не-ASCII символами.
У більшості редакторів (VS Code, Notepad++) це є опцією при збереженні.

### const.txt

`const.txt` перегенеровується після кожного успішного ремонту або встановлення torch.
Не редагуй вручну — перезаписується автоматично.

Файл використовується як `PIP_CONSTRAINT` — pip відмовить встановлювати версії
що конфліктують з ним. Це захищає від ситуації коли custom node мовчки знижує
версію пакету від якого залежить ComfyUI.

---

## Вирішення проблем

### Список версій Python недоступний під час встановлення

**Симптом:**
```
[ERROR] Could not retrieve Python version list.
```

**Причина:** Встановлений старий **Python Launcher** (`py.exe`) конфліктує з
Python Manager. Обидва використовують `py.exe` але з несумісним синтаксисом команд.

**Виправлення:**
1. **Параметри → Програми → Встановлені програми** → пошук **"Python Launcher"** → Видалити
2. Відкрий нове вікно термінала, запусти toolkit знову

> Твої існуючі версії Python **не постраждають**.

---

### Використовується не та версія Python для venv

**Симптом:** venv використовує неочікувану версію Python, або `py -3.12` викликає не той інтерпретатор.

**Причина:** Python встановлений вручну (не через Python Manager) і прописав себе в PATH
напряму, конфліктуючи з резолюцією версій Python Manager.

**Виправлення:**
1. Виконай `py list`, `where python`, `where py` щоб побачити що викликається
2. Якщо є конфлікт — видали вручну встановлені версії Python через **Параметри → Програми**
3. Дозволь Python Manager керувати всіма версіями Python

---

### ComfyUI не запускається після даунгрейду

**Симптом:** ComfyUI падає при старті з помилкою міграції бази даних.

**Причина:** База даних містить міграції з новішої версії яких стара версія не знає.

**Виправлення:** Використай **[V]** перемикач версій ComfyUI — він виявляє даунгрейди
і пропонує видалити базу даних автоматично. База містить тільки кеш ресурсів та
історію задач, не воркфлоу і не моделі.

---

### ComfyUI не запускається — `No module named 'torchsde'`

**Симптом:** ComfyUI падає з `ModuleNotFoundError: No module named 'torchsde'`.

**Причина:** `torchsde` не був встановлений разом зі стеком PyTorch.

**Виправлення:** Запусти **[T]** для перевстановлення PyTorch — `torchsde` тепер
встановлюється автоматично. Або встанови вручну через консоль **[C]**:
```
pip install torchsde
```

---

### Custom node ламає залежності після встановлення

**Симптом:** ComfyUI запускається але деякі ноди падають, або є помилки імпорту.

**Виправлення:** Запусти **[R] Ремонт**. Якщо конфлікт не вдається вирішити автоматично —
вивід покаже проблемний пакет. Використай ComfyUI-Manager щоб відключити або понизити
версію custom node що спричинив конфлікт, потім запусти Ремонт знову.
