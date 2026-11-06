@echo off
title Limpieza Windows 11
color 0A

echo ==========================================
echo       LIMPIEZA DE WINDOWS 11
echo ==========================================
echo.

REM Comprobar permisos de administrador
fltmc >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Ejecuta este archivo como administrador.
    echo Haz clic derecho y selecciona Ejecutar como administrador.
    pause
    exit /b 1
)

REM Comprobar que PowerShell esta disponible
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] No se encuentra PowerShell.
    pause
    exit /b 1
)

echo [1/7] Midiendo espacio libre inicial...

for /f %%A in ('powershell.exe -NoProfile -Command "[math]::Round((Get-PSDrive C).Free / 1GB, 2)"') do set "ANTES=%%A"

echo Espacio libre inicial: %ANTES% GB
echo.

echo [2/7] Deteniendo servicios de actualizacion...

for %%S in (bits wuauserv UsoSvc dosvc) do (
    net stop %%S /y >nul 2>&1
)

echo.

echo [3/7] Limpiando descargas de Windows Update...

if exist "C:\Windows\SoftwareDistribution\Download" (
    del /f /s /q "C:\Windows\SoftwareDistribution\Download\*" >nul 2>&1
    for /d %%D in ("C:\Windows\SoftwareDistribution\Download\*") do (
        rd /s /q "%%D" >nul 2>&1
    )
)

echo.

echo [4/7] Limpiando cache de Delivery Optimization...

set "DOCACHE=C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"

if exist "%DOCACHE%" (
    del /f /s /q "%DOCACHE%\*" >nul 2>&1
    for /d %%D in ("%DOCACHE%\*") do (
        rd /s /q "%%D" >nul 2>&1
    )
)

echo.

echo [5/7] Limpiando archivos temporales...

if defined TEMP (
    if exist "%TEMP%" (
        del /f /s /q "%TEMP%\*" >nul 2>&1
        for /d %%D in ("%TEMP%\*") do (
            rd /s /q "%%D" >nul 2>&1
        )
    )
)

if exist "C:\Windows\Temp" (
    del /f /s /q "C:\Windows\Temp\*" >nul 2>&1
    for /d %%D in ("C:\Windows\Temp\*") do (
        rd /s /q "%%D" >nul 2>&1
    )
)

echo.

echo [6/7] Vaciando papelera y limpiando DNS...

powershell.exe -NoProfile -Command "Clear-RecycleBin -Force -ErrorAction SilentlyContinue" >nul 2>&1

ipconfig /flushdns

echo.
echo Limpiando componentes antiguos de Windows...
echo Este proceso puede tardar varios minutos.

Dism.exe /Online /Cleanup-Image /StartComponentCleanup

echo.

echo Reiniciando servicios de Windows Update...

for %%S in (bits wuauserv UsoSvc dosvc) do (
    sc start %%S >nul 2>&1
)

echo.

echo [7/7] Midiendo espacio libre final...

for /f %%A in ('powershell.exe -NoProfile -Command "[math]::Round((Get-PSDrive C).Free / 1GB, 2)"') do set "DESPUES=%%A"

echo.
echo ==========================================
echo          LIMPIEZA TERMINADA
echo ==========================================
echo.
echo Espacio libre antes:   %ANTES% GB
echo Espacio libre despues: %DESPUES% GB
echo.
echo La limpieza ha finalizado.
echo Es recomendable reiniciar el equipo.
echo.
pause