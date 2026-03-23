@echo off
setlocal enabledelayedexpansion

title ComfyUI Multi-Launcher

:: ======================================================
:: --- CONFIGURATION ---
:: ======================================================

set "ACTIVATE_SCRIPT=.\venv\Scripts\activate.bat"
set "MAIN_PY=.\ComfyUI\main.py"

:: --- COMMON ARGS ---
:: These arguments are shared across ALL launch modes (items 1-2).
:: You can add any ComfyUI flags here that should always be active.
::
:: --output-directory  : output folder placed next to this .bat to avoid
::                       accidental loss when reinstalling the ComfyUI folder
:: --listen            : allow connections from other devices on the network
:: --reserve-vram      : amount of VRAM (GB) to keep free for the OS / other apps
:: --enable-manager    : enable ComfyUI-Manager plugin on startup
::
:: Other useful flags you may want to add here:
::   --lowvram             : for GPUs with limited VRAM
::   --cpu                 : run on CPU only (very slow)
::   --preview-method auto : enable latent previews during generation
::   --force-fp16          : force FP16 precision globally
::
set "COMMON_ARGS=--output-directory .\output"

:: ======================================================
:: --- HOW TO ADD A CUSTOM LAUNCH MODE ---
:: ======================================================
:: You need to edit exactly 3 places in this file:
::
:: PLACE 1 -- Add a line in the MENU echo block, e.g.:
::   echo  3. My Custom Mode
::
:: PLACE 2 -- Add a condition in the choice block, e.g.:
::   if "%choice%"=="3" goto RUN_CUSTOM
::
:: PLACE 3 -- Add a launch block in the LAUNCH MODES section, e.g.:
::   :RUN_CUSTOM
::   echo [INFO] Starting ComfyUI in custom mode...
::   python "%MAIN_PY%" %COMMON_ARGS% --my-flag --another-flag
::   pause
::   goto MENU
::
:: ======================================================

:: Check if venv activation script exists
:: If not found -- this is likely a first run, offer to launch the setup script now
if exist "%ACTIVATE_SCRIPT%" goto VENV_OK

echo.
echo [WARN] Virtual environment not found: %ACTIVATE_SCRIPT%
echo [INFO] This is probably your first run. The environment has not been set up yet.
echo.
echo  To get started, ComfyUI-Environment.ps1 must be run first.
echo  It will install all required software, create the venv,
echo  clone ComfyUI and install ComfyUI-Manager.
echo.
set /p setup="Run ComfyUI-Environment.ps1 now? (Y/N): "
if /i "%setup%"=="Y" goto RUN_FIRST_SETUP
echo [WARN] Setup cancelled. Exiting.
pause
exit /b 1

:RUN_FIRST_SETUP
echo [STEP] Launching ComfyUI-Environment.ps1 ...
powershell.exe -ExecutionPolicy Bypass -File ".\ComfyUI-Environment.ps1"
echo.
echo [OK] Setup finished. Restarting launcher...
pause
call "%~f0"
exit /b

:VENV_OK

:: Activate virtual environment once at startup
call "%ACTIVATE_SCRIPT%"
if errorlevel 1 (
    echo [ERROR] Failed to activate virtual environment.
    pause
    exit /b 1
)

:: Create output directory next to this .bat if it does not exist yet
if not exist ".\output" (
    mkdir ".\output"
    echo [OK] Output directory created: .\output
)

:MENU
cls
echo  --- ComfyUI Multi-Launcher ---
echo  --- Launch ---
echo  1. Normal
echo  2. Normal + fast
:: PLACE 1: add your custom mode echo line here, e.g.:
::   echo  3. My Custom Mode
echo  ----------------------------------------------------
echo  --- Tools ---
echo  5. Setup environment    (ComfyUI-Environment.ps1)
echo  6. Manage packages      (ComfyUI-Manager.ps1)
echo  7. Install ComfyUI-Manager
echo  8. venv console         (pip / manual install)
echo  9. ComfyUI help         (--help)
echo  0. Exit
echo ======================================================
set /p choice="Enter number (0-9): "

:: PLACE 2: add your custom mode condition here, e.g.:
::   if "%choice%"=="3" goto RUN_CUSTOM
if "%choice%"=="1" goto RUN_NORMAL
if "%choice%"=="2" goto RUN_FAST
if "%choice%"=="5" goto RUN_ENVIRONMENT
if "%choice%"=="6" goto RUN_MANAGER
if "%choice%"=="7" goto INSTALL_COMFYUI_MANAGER
if "%choice%"=="8" goto OPEN_CONSOLE
if "%choice%"=="9" goto HELP
if "%choice%"=="0" goto EXIT
goto MENU

:: ======================================================
:: --- LAUNCH MODES ---
:: ======================================================

:RUN_NORMAL
echo [STEP] Starting ComfyUI - normal mode...
python "%MAIN_PY%" %COMMON_ARGS%
pause
goto MENU

:RUN_FAST
echo [STEP] Starting ComfyUI - fast mode...
python "%MAIN_PY%" %COMMON_ARGS% --fast
pause
goto MENU

:: PLACE 3: add your custom launch block here, e.g.:
:: :RUN_CUSTOM
:: echo [INFO] Starting ComfyUI in custom mode...
:: python "%MAIN_PY%" %COMMON_ARGS% --your-flag-here
:: pause
:: goto MENU

:: ======================================================
:: --- TOOLS ---
:: ======================================================

:INSTALL_COMFYUI_MANAGER
cls
echo  --- Install ComfyUI-Manager ---
echo.

:: Check if ComfyUI folder exists first
if exist ".\ComfyUI" goto CHECK_MANAGER_EXISTS
echo [ERROR] ComfyUI folder not found.
echo [WARN] Run option 5 to set up ComfyUI first.
pause
goto MENU

:CHECK_MANAGER_EXISTS
if not exist ".\ComfyUI\custom_nodes\ComfyUI-Manager" goto DO_CLONE_MANAGER
echo [OK] ComfyUI-Manager is already installed.
echo [INFO] Location: ComfyUI\custom_nodes\ComfyUI-Manager
echo.
pause
goto MENU

:DO_CLONE_MANAGER
if not exist ".\ComfyUI\custom_nodes" mkdir ".\ComfyUI\custom_nodes"
echo [PROCESS] Cloning ComfyUI-Manager...
git clone https://github.com/Comfy-Org/ComfyUI-Manager.git ".\ComfyUI\custom_nodes\ComfyUI-Manager" --quiet
if not exist ".\ComfyUI\custom_nodes\ComfyUI-Manager" goto CLONE_FAILED
echo [SUCCESS] ComfyUI-Manager installed successfully.
echo.
pause
goto MENU

:CLONE_FAILED
echo [ERROR] Clone failed. Check internet connection or git installation.
echo.
pause
goto MENU

:RUN_ENVIRONMENT
echo [STEP] Launching ComfyUI-Environment.ps1 ...
powershell.exe -ExecutionPolicy Bypass -File ".\ComfyUI-Environment.ps1"
pause
goto MENU

:RUN_MANAGER
echo [STEP] Launching ComfyUI-Manager.ps1 ...
powershell.exe -ExecutionPolicy Bypass -File ".\ComfyUI-Manager.ps1"
pause
goto MENU

:OPEN_CONSOLE
cls
echo  --- venv Console ---
echo.
echo  You are inside the virtual environment (venv).
echo  All pip commands will install packages ONLY
echo  into venv, not into the global system.
echo.
echo  Useful commands:
echo    pip list                    - list installed packages
echo    pip install ^<package^>       - install a package
echo    pip uninstall ^<package^>     - remove a package
echo    pip install --upgrade ^<pkg^> - upgrade a package
echo    python --version            - show Python version
echo.
echo  Type 'exit' and press Enter to return to the main menu.
echo ======================================================
echo.
echo [PROCESS] Upgrading pip...
python -m pip install --upgrade pip
echo.
echo [INFO] Type 'exit' to return to menu.
echo.
if exist ".cache\const.txt" (
    cmd /k "call %ACTIVATE_SCRIPT% && doskey pip install=pip install $* -c .cache\const.txt"
) else (
    cmd /k "call %ACTIVATE_SCRIPT%"
)
goto MENU

:HELP
echo [STEP] Displaying ComfyUI help...
python "%MAIN_PY%" --help
pause
goto MENU

:EXIT
echo [OK] Exiting. Goodbye!
endlocal
exit /b 0
