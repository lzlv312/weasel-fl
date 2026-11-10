@echo off
setlocal

rem Build librime from source with the patches in patches\, then install the
rem artifacts (rime.dll / rime.lib / headers / opencc data) into the weasel tree.
rem This replaces get-rime.ps1 -use dev, which downloads a prebuilt rime.dll.
rem
rem Usage: build-rime.bat [x64|Win32|all]     default: all
rem Run from the weasel root in a Visual Studio developer prompt.
rem Requires Boost source tree at BOOST_ROOT (headers only; Boost.Regex is
rem header-only since Boost 1.84, no compiled boost libs are needed).

set WEASEL_ROOT=%CD%

if not exist env.bat copy env.bat.template env.bat
if exist env.bat call env.bat

if not defined WEASEL_ROOT set WEASEL_ROOT=%CD%
cd /d %WEASEL_ROOT%

if not defined BOOST_ROOT goto boost_error
if not exist "%BOOST_ROOT%\boost" goto boost_error
echo BOOST_ROOT=%BOOST_ROOT%
echo.

set LIBRIME_ROOT=%WEASEL_ROOT%\librime
if not exist "%LIBRIME_ROOT%\CMakeLists.txt" (
  echo error: librime source not found.
  echo Run: git submodule update --init --recursive librime
  exit /b 1
)
if not exist "%LIBRIME_ROOT%\deps\glog\CMakeLists.txt" (
  echo error: librime deps submodules not initialized.
  echo Run: git submodule update --init --recursive librime
  exit /b 1
)

rem ---- apply local patches (idempotent, like trime's patch-apply target) ----
call :apply_patch detect-modifications.patch
if errorlevel 1 goto error
call :apply_patch restore-saved-options.patch
if errorlevel 1 goto error

set ARCH_LIST=%1
if "%ARCH_LIST%" == "" set ARCH_LIST=all

if "%ARCH_LIST%" == "x64" call :build_arch x64
if "%ARCH_LIST%" == "Win32" call :build_arch Win32
if "%ARCH_LIST%" == "all" (
  call :build_arch x64
  if errorlevel 1 goto error
  call :build_arch Win32
  if errorlevel 1 goto error
)

echo.
echo librime build done. rime.dll installed into the weasel tree.
goto end

rem ---------------------------------------------------------------------------
rem Build deps and librime for one architecture, then copy artifacts.
:build_arch
rem per-arch build dirs and install prefixes keep x64 and Win32 artifacts apart
set ARCH=%1
set build_dir=build\%ARCH%
set deps_install_prefix=%LIBRIME_ROOT%\deps\install\%ARCH%
set rime_install_prefix=%LIBRIME_ROOT%\dist\%ARCH%

rem librime's build.bat sources librime\env.bat, whose template would force
rem ARCH=Win32 and VS2019; generate it here to control ARCH and the generator
(
  echo set RIME_ROOT=%LIBRIME_ROOT%
  echo set BOOST_ROOT=%BOOST_ROOT%
  if defined CMAKE_GENERATOR echo set CMAKE_GENERATOR=%CMAKE_GENERATOR%
  if defined PLATFORM_TOOLSET echo set PLATFORM_TOOLSET=%PLATFORM_TOOLSET%
) > "%LIBRIME_ROOT%\env.bat"

echo ==== building librime deps for %ARCH% ====
pushd "%LIBRIME_ROOT%"
call build.bat deps
if errorlevel 1 (popd & goto error)
echo ==== building librime for %ARCH% ====
call build.bat librime
if errorlevel 1 (popd & goto error)
popd

call :copy_artifacts %ARCH%
if errorlevel 1 goto error
exit /b

rem ---------------------------------------------------------------------------
:copy_artifacts
set ARCH=%1
set DIST=%LIBRIME_ROOT%\dist\%ARCH%
if not exist "%DIST%\lib\rime.dll" (
  echo error: %DIST%\lib\rime.dll not found; build for %ARCH% failed.
  exit /b 1
)
rem headers and opencc data are arch-independent
copy /y "%DIST%\include\rime_*.h" "%WEASEL_ROOT%\include\" >nul
if errorlevel 1 goto copy_error
if exist "%DIST%\share\opencc" (
  xcopy /y /i "%DIST%\share\opencc\*.*" "%WEASEL_ROOT%\output\data\opencc\" >nul
  if errorlevel 1 goto copy_error
)
if "%ARCH%" == "x64" (
  copy /y "%DIST%\lib\rime.dll" "%WEASEL_ROOT%\output\" >nul
  if errorlevel 1 goto copy_error
  if exist "%DIST%\lib\rime.pdb" copy /y "%DIST%\lib\rime.pdb" "%WEASEL_ROOT%\output\" >nul
  copy /y "%DIST%\lib\rime.lib" "%WEASEL_ROOT%\lib64\" >nul
  if errorlevel 1 goto copy_error
) else (
  copy /y "%DIST%\lib\rime.dll" "%WEASEL_ROOT%\output\Win32\" >nul
  if errorlevel 1 goto copy_error
  if exist "%DIST%\lib\rime.pdb" copy /y "%DIST%\lib\rime.pdb" "%WEASEL_ROOT%\output\Win32\" >nul
  copy /y "%DIST%\lib\rime.lib" "%WEASEL_ROOT%\lib\" >nul
  if errorlevel 1 goto copy_error
)
echo installed %ARCH% rime.dll into the weasel tree
exit /b

:copy_error
echo error copying librime artifacts for %ARCH%
exit /b 1

rem ---------------------------------------------------------------------------
:apply_patch
git apply --directory=librime --check patches\%1 >nul 2>&1
if errorlevel 1 (
  git apply --directory=librime --reverse --check patches\%1 >nul 2>&1
  if errorlevel 1 (
    echo error: patches\%1 does not apply to librime.
    echo the librime submodule probably moved, regenerate the patch.
    exit /b 1
  )
  echo patches\%1 already applied
  exit /b
)
git apply --directory=librime patches\%1
if errorlevel 1 exit /b 1
echo applied patches\%1
exit /b

rem ---------------------------------------------------------------------------
:boost_error
echo Error: Boost not found! Please set BOOST_ROOT in env.bat.
echo Run install_boost.bat first if the boost source tree is missing.
exit /b 1

:error
echo error building librime...
exit /b 1

:end
exit /b 0
