#Requires -Version 5.1
# Punto de entrada común para el EXE y Fuentes/Iniciar.bat. Código propio, MIT.
$ErrorActionPreference='Stop'
$admin=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $admin.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
    $exe=if([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess){"$env:windir\Sysnative\WindowsPowerShell\v1.0\powershell.exe"}else{"$env:windir\System32\WindowsPowerShell\v1.0\powershell.exe"}
    Start-Process -FilePath $exe -Verb RunAs -ArgumentList "-NoLogo -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`""
    exit
}
if(-not $env:OW_SESSION_ID){$env:OW_SESSION_ID='sesion-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)}
$backup=Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('Optimization\'+$env:OW_SESSION_ID)
$env:OW_BACKUP_DIR=$backup
if(-not $env:OW_CLOSE_REQUEST){$env:OW_CLOSE_REQUEST=Join-Path $backup 'limpiar.confirmado'}
try {
    . (Join-Path $PSScriptRoot 'Main.ps1')
} catch {
    Add-Type -AssemblyName PresentationFramework
    [void][Windows.MessageBox]::Show("No se pudo abrir OptimiZation Versión 2.`n$($_.Exception.Message)`nLínea: $($_.InvocationInfo.ScriptLineNumber)`nLas copias existentes se conservan.",'OptimiZation', 'OK','Error')
    exit 1
} finally {
    # Solo esta sesión. No tocar historiales de Windows, copias antiguas ni archivos exportados.
    if(Test-Path -LiteralPath $env:OW_CLOSE_REQUEST){
        try {
            if((Split-Path $backup -Leaf) -eq $env:OW_SESSION_ID -and $env:OW_SESSION_ID -match '^sesion-\d{8}-\d{6}-[a-f0-9]{8}$'){
                $info=Get-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
                $parent=Get-Item -LiteralPath (Split-Path $backup -Parent) -Force -ErrorAction SilentlyContinue
                if($info -and -not ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) -and -not ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint)){
                    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction Stop
                    if(-not @(Get-ChildItem -LiteralPath $parent.FullName -Force).Count){Remove-Item -LiteralPath $parent.FullName -Force -ErrorAction Stop}
                }
            }
        } catch { # El lanzador EXE vuelve a intentarlo después de salir PowerShell.
        }
    }
}
