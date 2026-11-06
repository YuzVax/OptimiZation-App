# Funciones auxiliares de OptimiZation (código propio, licencia de uso no comercial; ver LICENSE).

function Write-Log {
    param([string]$Mensaje, [ValidateSet('INFO','OK','AVISO','ERROR')][string]$Nivel = 'INFO')
    $linea = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Nivel, $Mensaje
    try { Add-Content -Path $Global:RutaLog -Value $linea -Encoding UTF8 } catch {}
    if ($Global:EnSegundoPlano) { if($Global:Sync.MostrarRegistro){$Global:Sync.Cola.Enqueue($linea)} }
    elseif ($Global:TxtLog -and $Global:RegistroAplicacionAbierto) { $Global:TxtLog.AppendText($linea + [Environment]::NewLine); $Global:TxtLog.ScrollToEnd() }
}

# Línea viva del registro: se reemplaza en pantalla en vez de añadir líneas nuevas (no se escribe en el .log).
function Write-Vivo([string]$Texto) {
    if ($Global:EnSegundoPlano -and $Global:Sync.MostrarRegistro) { $Global:Sync.Cola.Enqueue([string][char]1 + ('[{0}] [INFO]   {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Texto)) }
}
function Format-Duracion([double]$s) {
    $t = [TimeSpan]::FromSeconds([Math]::Max(0, [Math]::Round($s)))
    if ($t.TotalHours -ge 1) { '{0}:{1:00}:{2:00}' -f [int][Math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds } else { '{0:00}:{1:00}' -f $t.Minutes, $t.Seconds }
}
function Get-TextoProgreso([string]$Nombre, [double]$Pct, [double]$Seg) {
    if ($Pct -ge 0) {
        $txt = '{0}: {1:N1} % · {2} transcurrido' -f $Nombre, $Pct, (Format-Duracion $Seg)
        if ($Pct -ge 1 -and $Pct -lt 100) { $txt += ' · ~' + (Format-Duracion ($Seg * (100 - $Pct) / $Pct)) + ' restante' }
        return $txt
    }
    return '{0}: en curso · {1} transcurrido' -f $Nombre, (Format-Duracion $Seg)
}
# Ejecuta un programa de consola leyendo su salida real (porcentaje) con la codificación correcta.
# sfc escribe UTF-16 al redirigirse; DISM y cmd usan la página OEM (cp850 en español); winget UTF-8.
function Invoke-ConProgreso {
    param([string]$Exe, [string]$Argumentos, [string]$Nombre, [ValidateSet('OEM','Unicode','UTF8')][string]$Codificacion = 'OEM', [int]$MaxMinutos = 0)
    $psi = New-Object System.Diagnostics.ProcessStartInfo($Exe, $Argumentos)
    $psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = switch ($Codificacion) {
        'Unicode' { [Text.Encoding]::Unicode } 'UTF8' { New-Object System.Text.UTF8Encoding($false) }
        default { [Text.Encoding]::GetEncoding([Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage) } }
    $psi.StandardErrorEncoding = $psi.StandardOutputEncoding
    Write-Log "  Ejecutando $Exe $Argumentos"
    $p = [System.Diagnostics.Process]::Start($psi)
    $err = $p.StandardError.ReadToEndAsync()
    $t0 = Get-Date; $pct = -1; $ultimaViva = [datetime]::MinValue; $vistas = @{}
    $lect = $p.StandardOutput.ReadLineAsync()
    while ($true) {
        if ($lect.Wait(1000)) {
            $l = $lect.Result
            if ($null -eq $l) { break }
            $l = ($l -replace "`0", '').Trim()
            if ($l) {
                if ($l -match '(\d{1,3}(?:[.,]\d+)?)\s?%') { $v = [double]($Matches[1] -replace ',', '.'); if ($v -le 100) { $pct = $v } }
                elseif ($l -notmatch '[█▒░■]' -and $l -notmatch '^[\s=\-\[\]\|/\\]+$' -and $l.Length -gt 2 -and -not $vistas.ContainsKey($l)) { $vistas[$l] = 1; Write-Log "    ${Nombre}: $l" }
            }
            $lect = $p.StandardOutput.ReadLineAsync()
        }
        $seg = ((Get-Date) - $t0).TotalSeconds
        if (((Get-Date) - $ultimaViva).TotalMilliseconds -ge 900) {
            $ultimaViva = Get-Date; $txt = Get-TextoProgreso $Nombre $pct $seg
            Write-Vivo $txt; Set-Estado "$Global:PrefijoEstado$txt"
        }
        if ($MaxMinutos -gt 0 -and $seg -gt $MaxMinutos * 60) {
            Write-Log "  $Nombre lleva más de $MaxMinutos minutos: se cancela." 'AVISO'
            try { $p.Kill() } catch {}
            break
        }
    }
    $p.WaitForExit(10000) | Out-Null
    $e = if ($err.Wait(2000)) { ($err.Result -replace "`0", '').Trim() } else { '' }
    if ($e) { Write-Log "    ${Nombre} (errores): $e" 'AVISO' }
    $codigo = try { $p.ExitCode } catch { -1 }
    Write-Vivo ((Get-TextoProgreso $Nombre $(if ($pct -ge 0) { 100 } else { -1 }) ((Get-Date) - $t0).TotalSeconds) + " · terminado (código $codigo)")
    Write-Log ('  {0}: terminado en {1} (código {2}).' -f $Nombre, (Format-Duracion ((Get-Date) - $t0).TotalSeconds), $codigo)
    return $codigo
}
# Espera a un proceso sin salida (p. ej. cleanmgr) mostrando el tiempo transcurrido.
function Wait-ConProgreso($Proceso, [string]$Nombre) {
    $t0 = Get-Date
    while (-not $Proceso.WaitForExit(1000)) { $txt = Get-TextoProgreso $Nombre -1 ((Get-Date) - $t0).TotalSeconds; Write-Vivo $txt; Set-Estado "$Global:PrefijoEstado$txt" }
    Write-Vivo ((Get-TextoProgreso $Nombre -1 ((Get-Date) - $t0).TotalSeconds) + ' · terminado')
    Write-Log ('  {0}: terminado en {1}.' -f $Nombre, (Format-Duracion ((Get-Date) - $t0).TotalSeconds))
}
# Aplica al momento la configuración del ratón (sin cerrar sesión).
function Update-RatonSinAceleracion([bool]$Sin) {
    try {
        if (-not ('RatonSPI' -as [type])) { Add-Type -Namespace '' -Name RatonSPI -MemberDefinition '[DllImport("user32.dll")] public static extern bool SystemParametersInfo(int a, int b, int[] c, int d);' }
        $v = if ($Sin) { [int[]](0, 0, 0) } else { [int[]](6, 10, 1) }
        [void][RatonSPI]::SystemParametersInfo(4, 0, $v, 3)   # SPI_SETMOUSE, guardar y notificar
    } catch { Write-Log "  No se pudo aplicar el ratón al momento (se aplicará al reiniciar sesión): $($_.Exception.Message)" 'AVISO' }
}

function Send-Parcial($x) { if ($Global:EnSegundoPlano -and $Global:Sync -and $Global:Sync.Parciales) { $Global:Sync.Parciales.Enqueue($x) } }

function Set-Estado([string]$Texto, [int]$Porcentaje = -1) {
    if ($Global:EnSegundoPlano) { $Global:Sync.Estado = $Texto; if ($Porcentaje -ge 0) { $Global:Sync.Progreso = $Porcentaje } }
}

function Update-UI {
    if ($Global:EnSegundoPlano) { return }
    if ($Global:Ventana) {
        $Global:Ventana.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background)
    }
}

function Set-Reg {
    param([string]$Ruta, [string]$Nombre, $Valor, [string]$Tipo = 'DWord')
    if (-not (Test-Path $Ruta)) { New-Item -Path $Ruta -Force | Out-Null }
    Set-ItemProperty -Path $Ruta -Name $Nombre -Value $Valor -Type $Tipo -Force
}

function Remove-Reg {
    param([string]$Ruta, [string]$Nombre)
    Remove-ItemProperty -Path $Ruta -Name $Nombre -Force -ErrorAction SilentlyContinue
}

function Set-Svc {
    param([string]$Nombre, [ValidateSet('Disabled','Manual','Automatic')][string]$Inicio)
    $s = Get-Service -Name $Nombre -ErrorAction SilentlyContinue
    if (-not $s) { Write-Log "  Servicio $Nombre no existe en este equipo (se omite)." 'AVISO'; return }
    if ($Inicio -eq 'Disabled') { Stop-Service -Name $Nombre -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $Nombre -StartupType $Inicio -ErrorAction Stop
    Write-Log "  Servicio $Nombre -> $Inicio"
}

function Set-Tarea {
    param([string[]]$Rutas, [bool]$Activar)
    foreach ($r in $Rutas) {
        $carpeta = $r.Substring(0, $r.LastIndexOf('\') + 1)
        $nombre  = $r.Substring($r.LastIndexOf('\') + 1)
        $t = Get-ScheduledTask -TaskPath $carpeta -TaskName $nombre -ErrorAction SilentlyContinue
        if (-not $t) { Write-Log "  Tarea $r no existe (se omite)." 'AVISO'; continue }
        if ($Activar) { $t | Enable-ScheduledTask | Out-Null } else { $t | Disable-ScheduledTask | Out-Null }
        Write-Log "  Tarea $nombre -> $(if($Activar){'activada'}else{'desactivada'})"
    }
}

function Restart-Explorer {
    $sesion=[Diagnostics.Process]::GetCurrentProcess().SessionId
    Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sesion} | Stop-Process -Force -ErrorAction Stop
    Start-Sleep -Seconds 2
    if(-not @(Get-Process -Name explorer -ErrorAction SilentlyContinue | Where-Object {$_.SessionId -eq $sesion}).Count){Start-Process explorer.exe -ErrorAction Stop}
}

function Invoke-Liberador {
    $base = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
        Set-ItemProperty -Path $_.PSPath -Name 'StateFlags0777' -Value 2 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Log '  Ejecutando cleanmgr /sagerun:777 (puede tardar varios minutos)...'
    $p = Start-Process cleanmgr.exe -ArgumentList '/sagerun:777' -PassThru
    Wait-ConProgreso $p 'Liberador de espacio'
}

function Set-PlanAlto {
    $alto = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    powercfg /setactive $alto 2>$null
    if ($LASTEXITCODE -ne 0) {
        $salida = powercfg /duplicatescheme $alto
        if ($salida -match '([0-9a-fA-F\-]{36})') { powercfg /setactive $Matches[1] }
        else { throw 'Este equipo no permite el plan Alto rendimiento (Modern Standby).' }
    }
}

function Set-PlanMaximo {
    $salida = powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
    if ($salida -match '([0-9a-fA-F\-]{36})') { powercfg /setactive $Matches[1] }
    else { throw 'No se pudo crear el plan Rendimiento máximo.' }
}

function Set-EfectosRendimiento {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 3
    Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) 'Binary'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'FontSmoothing' '2' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 0
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
}

function Reset-Efectos {
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 0
    Set-Reg 'HKCU:\Control Panel\Desktop' 'UserPreferencesMask' ([byte[]](0x9E,0x1E,0x07,0x80,0x12,0x00,0x00,0x00)) 'Binary'
    Set-Reg 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '400' 'String'
    Set-Reg 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarAnimations' 1
    Set-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
}

$Global:DominiosTelemetria = @(
    'vortex.data.microsoft.com','vortex-win.data.microsoft.com','telecommand.telemetry.microsoft.com',
    'oca.telemetry.microsoft.com','sqm.telemetry.microsoft.com','watson.telemetry.microsoft.com',
    'settings-win.data.microsoft.com','telemetry.microsoft.com','v10.events.data.microsoft.com')
$Global:RutaHosts = "$env:windir\System32\drivers\etc\hosts"

function Remove-HostsBloqueo {
    $c = Get-Content $Global:RutaHosts -ErrorAction SilentlyContinue
    $fuera = $false; $nuevo = foreach ($l in $c) {
        if ($l -eq '# >>> OptimizadorWindows') { $fuera = $true; continue }
        if ($l -eq '# <<< OptimizadorWindows') { $fuera = $false; continue }
        if (-not $fuera) { $l }
    }
    Set-Content -Path $Global:RutaHosts -Value $nuevo -Encoding ASCII
}

function Add-HostsBloqueo {
    Copy-Item $Global:RutaHosts "$($Global:RutaHosts).copia_optimizador" -Force
    Remove-HostsBloqueo
    $bloque = @('# >>> OptimizadorWindows') + ($Global:DominiosTelemetria | ForEach-Object { "0.0.0.0 $_" }) + @('# <<< OptimizadorWindows')
    Add-Content -Path $Global:RutaHosts -Value $bloque -Encoding ASCII
    ipconfig /flushdns | Out-Null
}

function Remove-Bloat {
    param([string[]]$Listas, [switch]$SoloProvisionado)
    foreach ($l in $Listas) {
        foreach ($patron in $Global:Catalogo.listasBloatware.$l) {
            if ($SoloProvisionado) {
                Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like $patron } | ForEach-Object {
                    $prov = $_
                    try { Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null; Write-Log "  Desaprovisionado: $($prov.DisplayName)" }
                    catch { Write-Log "  No se pudo desaprovisionar $($prov.DisplayName): $($_.Exception.Message)" 'AVISO' }
                }
                continue
            }
            $paquetes = @(Get-AppxPackage -AllUsers -Name $patron -ErrorAction SilentlyContinue)
            foreach ($p in $paquetes) {
                try { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop; Write-Log "  Quitada: $($p.Name)" }
                catch {
                    try { Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop; Write-Log "  Quitada (usuario actual): $($p.Name)" }
                    catch { Write-Log "  No se pudo quitar $($p.Name): $($_.Exception.Message)" 'AVISO' }
                }
            }
        }
    }
}

function Restore-Bloat {
    param([string[]]$Listas)
    foreach ($l in $Listas) {
        foreach ($patron in $Global:Catalogo.listasBloatware.$l) {
            $paquetes = @(Get-AppxPackage -AllUsers -Name $patron -ErrorAction SilentlyContinue)
            if (-not $paquetes) { Write-Log "  $patron ya no está en el sistema: reinstálala desde Microsoft Store." 'AVISO'; continue }
            foreach ($p in $paquetes) {
                try { Add-AppxPackage -DisableDevelopmentMode -Register "$($p.InstallLocation)\AppxManifest.xml" -ErrorAction Stop; Write-Log "  Registrada de nuevo: $($p.Name)" }
                catch { Write-Log "  No se pudo restaurar $($p.Name): $($_.Exception.Message)" 'AVISO' }
            }
        }
    }
}

function Uninstall-OneDrive {
    Stop-Process -Name OneDrive -Force -ErrorAction SilentlyContinue
    $candidatos = @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")
    $candidatos += Get-ChildItem "$env:LOCALAPPDATA\Microsoft\OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName
    $candidatos += Get-ChildItem "${env:ProgramFiles}\Microsoft OneDrive\*\OneDriveSetup.exe" -ErrorAction SilentlyContinue | ForEach-Object FullName
    $exe = $candidatos | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
    if (-not $exe) { throw 'No se encontró OneDriveSetup.exe; puede que ya esté desinstalado.' }
    Start-Process $exe -ArgumentList '/uninstall' -Wait
}

function Remove-Edge {
    $setup = Get-ChildItem "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\*\Installer\setup.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $setup) { throw 'No se encontró el instalador de Edge.' }
    Start-Process $setup.FullName -ArgumentList '--uninstall','--system-level','--verbose-logging','--force-uninstall' -Wait
}

# v6: no confundir una llamada sin errores con un punto realmente creado.
$Global:UltimoErrorRestauracion = ''
function Get-PuntosRestauracion {
    @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -OperationTimeoutSec 30 -ErrorAction Stop |
        Sort-Object SequenceNumber -Descending)
}
function Test-AdminRestauracion {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Wait-NuevoPuntoRestauracion([long]$MaxAntes, [string]$Descripcion, [int]$Segundos=45) {
    # El proveedor puede publicar el punto después de devolver un aviso o cambiar su descripción.
    for($intento=0;$intento -le $Segundos;$intento++){
        try {
            $nuevos=@(Get-PuntosRestauracion | Where-Object {[long]$_.SequenceNumber -gt $MaxAntes} | Sort-Object SequenceNumber -Descending)
            if($nuevos.Count){
                $coincide=@($nuevos | Where-Object {([string]$_.Description).Trim() -eq $Descripcion.Trim()})
                if($coincide.Count){return $coincide[0]}
                return $nuevos[0]
            }
        } catch {Write-Log "  Esperando la lista de puntos: $($_.Exception.Message)" 'AVISO'}
        if($intento -lt $Segundos){Start-Sleep -Seconds 1}
    }
    return $null
}

function New-PuntoRestauracion {
    param([string]$Descripcion = 'OptimiZation · Versión 2')
    $Global:UltimoErrorRestauracion = ''
    $clave = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore'
    $freq = 'SystemRestorePointCreationFrequency'
    $teniaFreq = $false; $previo = $null; $tipoPrevio = 'DWord'; $freqCambiada = $false
    $descripcionReal = (($Descripcion -replace '[\r\n]', ' ') + ' · ' + (Get-Date -Format 'HH:mm:ss') + ' · ' + (Get-Random -Maximum 99999))
    if ($descripcionReal.Length -gt 250) { $descripcionReal = $descripcionReal.Substring(0,250) }
    try {
        Set-Estado 'Preparando Protección del sistema...' 5
        if (-not (Test-AdminRestauracion)) { throw 'Abre la aplicación como administrador.' }
        $os = Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec 15 -ErrorAction Stop
        if ($os.ProductType -ne 1) { throw 'Restaurar sistema solo está disponible en Windows de escritorio, no en Windows Server.' }
        $drive = "$env:SystemDrive\"
        Write-Log "Creando punto verificado en ${drive}: $descripcionReal"
        # Guardamos las directivas locales antes de desbloquear la protección. Una política de empresa puede volver a imponerlas.
        foreach ($ruta in @('HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\SystemRestore', $clave)) {
            foreach ($nombre in 'DisableSR','DisableConfig') {
                $props = Get-ItemProperty -LiteralPath $ruta -ErrorAction SilentlyContinue
                if ($props -and $props.$nombre -eq 1) {
                    $dir = Join-Path (Get-DirectorioCopias) 'ProteccionSistema'
                    New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
                    $archivo = Join-Path $dir ((Get-Date -Format 'yyyyMMdd_HHmmssfff') + "_$nombre.reg")
                    & reg.exe export ($ruta -replace '^HKLM:', 'HKLM') $archivo /y | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "No se pudo guardar la directiva $nombre; no se modifica." }
                    Remove-ItemProperty -LiteralPath $ruta -Name $nombre -ErrorAction Stop
                    if ((Get-ItemProperty -LiteralPath $ruta -ErrorAction SilentlyContinue).$nombre -eq 1) { throw "La directiva $nombre sigue bloqueada (puede gestionarla tu empresa)." }
                    Write-Log "  Quitado bloqueo local $nombre. Copia de la directiva: $archivo" 'AVISO'
                }
            }
        }
        # Algunos Windows no incluyen SDRSVC/srservice/SRS*. No se crean servicios inexistentes.
        $servicios = @(Get-Service -Name 'VSS','swprv','SDRSVC','srservice','SRS*','Winmgmt' -ErrorAction SilentlyContinue | Sort-Object Name -Unique)
        foreach ($sv in $servicios) {
            if ($sv.StartType -eq 'Disabled') {
                Set-Service -Name $sv.Name -StartupType Manual -ErrorAction Stop
                Write-Log "  Servicio $($sv.Name): deshabilitado -> Manual." 'AVISO'
            }
            if ($sv.Status -ne 'Running') {
                try {
                    Start-Service -Name $sv.Name -ErrorAction Stop
                    (Get-Service -Name $sv.Name).WaitForStatus('Running', [TimeSpan]::FromSeconds(20))
                } catch {
                    if ($sv.Name -in 'VSS','swprv','Winmgmt') { throw "No se puede iniciar $($sv.Name): $($_.Exception.Message)" }
                    Write-Log "  Servicio opcional $($sv.Name): $($_.Exception.Message)" 'AVISO'
                }
            }
        }
        Set-Estado 'Activando Protección del sistema en la unidad de Windows...' 20
        Enable-ComputerRestore -Drive $drive -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $clave)) { New-Item -Path $clave -Force -ErrorAction Stop | Out-Null }
        $k = Get-Item -LiteralPath $clave -ErrorAction Stop
        $teniaFreq = $k.GetValueNames() -contains $freq
        if ($teniaFreq) { $previo = $k.GetValue($freq); $tipoPrevio = $k.GetValueKind($freq).ToString() }
        New-ItemProperty -LiteralPath $clave -Name $freq -Value 0 -PropertyType DWord -Force -ErrorAction Stop | Out-Null
        $freqCambiada = $true
        $antes = @(Get-PuntosRestauracion)
        $maxAntes = if ($antes.Count) { [long]($antes | Measure-Object SequenceNumber -Maximum).Maximum } else { [long]-1 }
        Set-Estado 'Creando el punto de restauración (puede tardar varios minutos)...' 40
        $falloCheckpoint = ''
        try { Checkpoint-Computer -Description $descripcionReal -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction Stop }
        catch { $falloCheckpoint = $_.Exception.Message; Write-Log "  Checkpoint-Computer: $falloCheckpoint" 'AVISO' }
        $nuevo = Wait-NuevoPuntoRestauracion $maxAntes $descripcionReal 45
        if (-not $nuevo -and $falloCheckpoint) {
            Write-Log '  Reintentando con el proveedor oficial WMI de Restaurar sistema.' 'AVISO'
            try {
                $argsSR = @{ Description = $descripcionReal; RestorePointType = [uint32]12; EventType = [uint32]100 }
                $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments $argsSR -OperationTimeoutSec 180 -ErrorAction Stop
                if ([uint32]$r.ReturnValue -ne 0) { throw ('El proveedor de Restaurar sistema devolvió 0x{0:X8}.' -f [uint32]$r.ReturnValue) }
                $argsSR.EventType = [uint32]101
                $fin = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint -Arguments $argsSR -OperationTimeoutSec 60 -ErrorAction Stop
                if ([uint32]$fin.ReturnValue -ne 0) { throw ('No se pudo finalizar el punto: 0x{0:X8}.' -f [uint32]$fin.ReturnValue) }
            } catch {$falloCheckpoint += ' · ' + $_.Exception.Message;Write-Log "  Proveedor WMI: $($_.Exception.Message)" 'AVISO'}
            # Incluso un proveedor que lance error puede haber creado/publicado ya el punto.
            $nuevo = Wait-NuevoPuntoRestauracion $maxAntes $descripcionReal 45
        }
        if (-not $nuevo) { throw "Windows no muestra un punto nuevo tras esperar. No se da por creado. $falloCheckpoint" }
        Write-Log "Punto de restauración comprobado: nº $($nuevo.SequenceNumber) · $($nuevo.Description)" 'OK'
        Set-Estado 'Punto de restauración creado y comprobado.' 100
        return $true
    } catch {
        $detalle = $_.Exception.Message
        $ayuda = 'Abre «Protección del sistema», activa la unidad de Windows y revisa el espacio asignado. Si persiste, revisa los errores VSS/Volsnap de Windows. No se borran puntos existentes.'
        if ($detalle -match '800423|VSS|instant') { $ayuda = 'Fallo del servicio de instantáneas. Reinicia Windows y revisa VSS/Volsnap en el Visor de eventos. No se borran instantáneas ni puntos existentes.' }
        if ($detalle -match '80070005|acceso|deneg|policy|directiva') { $ayuda = 'Permisos o directivas bloquean Protección del sistema. Usa un administrador; en equipos de empresa consulta al administrador.' }
        if ($detalle -match '8004231F|espacio|space') { $ayuda = 'Falta espacio para el punto. Libera espacio y aumenta el máximo en Protección del sistema.' }
        $Global:UltimoErrorRestauracion = "$detalle`n$ayuda"
        Write-Log "No se pudo crear el punto: $Global:UltimoErrorRestauracion" 'ERROR'
        Set-Estado "No se creó el punto. $detalle" 100
        return $false
    } finally {
        if ($freqCambiada) {
            try {
                if ($teniaFreq) { New-ItemProperty -LiteralPath $clave -Name $freq -Value $previo -PropertyType $tipoPrevio -Force -ErrorAction Stop | Out-Null }
                else { Remove-ItemProperty -LiteralPath $clave -Name $freq -ErrorAction Stop }
            } catch { Write-Log "No se pudo restaurar el límite de frecuencia anterior: $($_.Exception.Message)" 'AVISO' }
        }
    }
}

function Get-DirectorioCopias {
    if ($Global:DirectorioCopias) { return $Global:DirectorioCopias }
    if ($env:OW_BACKUP_DIR) { return $env:OW_BACKUP_DIR }
    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Optimization')
}

function Backup-Registro {
    $dir = Join-Path (Get-DirectorioCopias) ("CopiasRegistro\" + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $claves = [ordered]@{
        'HKCU' = 'HKCU.reg'
        'HKLM\SOFTWARE\Policies' = 'HKLM_Policies.reg'
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion' = 'HKLM_CurrentVersion.reg'
        'HKLM\SYSTEM\CurrentControlSet\Services' = 'HKLM_Services.reg'
        'HKLM\SYSTEM\CurrentControlSet\Control' = 'HKLM_Control.reg'
    }
    $fallos = 0
    foreach ($k in $claves.Keys) {
        Write-Log "  Exportando $k ..."; Update-UI
        & reg.exe export $k (Join-Path $dir $claves[$k]) /y | Out-Null
        if ($LASTEXITCODE -ne 0) { $fallos++; Write-Log "  No se pudo exportar $k" 'ERROR' }
    }
    if ($fallos) { throw "Copia incompleta: $fallos claves no se exportaron. No se aplican cambios. Carpeta: $dir" }
    Write-Log "Copia del registro guardada en $dir" 'OK'
    return $dir
}

# ----- Funciones añadidas en v2 -----
function Add-MenuTomarPosesion {
    $defs = @{
        'Software\Classes\*\shell\TomarPosesion'         = 'cmd.exe /c takeown /f "%1" && icacls "%1" /grant *S-1-5-32-544:F /c'
        'Software\Classes\Directory\shell\TomarPosesion' = 'cmd.exe /c takeown /f "%1" /r /d S && icacls "%1" /grant *S-1-5-32-544:F /t /c'
    }
    foreach ($base in $defs.Keys) {
        $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($base)
        $k.SetValue('', 'Tomar posesión'); $k.SetValue('HasLUAShield', ''); $k.SetValue('NoWorkingDirectory', '')
        $c = $k.CreateSubKey('command'); $c.SetValue('', $defs[$base]); $c.Close(); $k.Close()
    }
}
function Remove-MenuTomarPosesion {
    foreach ($base in 'Software\Classes\*\shell\TomarPosesion', 'Software\Classes\Directory\shell\TomarPosesion') {
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($base, $false)
    }
}
function Add-MenuPowerShellAdmin {
    $k = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Classes\Directory\Background\shell\PowerShellAdmin')
    $k.SetValue('', 'Abrir PowerShell aquí (admin)'); $k.SetValue('HasLUAShield', ''); $k.SetValue('Icon', 'powershell.exe')
    $c = $k.CreateSubKey('command')
    $valor = @'
powershell.exe -NoProfile -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoExit','-Command','Set-Location -LiteralPath ''%V'''"
'@
    $c.SetValue('', $valor.Trim())
    $c.Close(); $k.Close()
}
function Remove-MenuPowerShellAdmin {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree('Software\Classes\Directory\Background\shell\PowerShellAdmin', $false)
}

function Set-DnsAdaptadores([string[]]$Servidores) {
    Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | ForEach-Object {
        if ($Servidores) { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $Servidores }
        else { Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ResetServerAddresses }
        Write-Log "  DNS de '$($_.Name)' -> $(if($Servidores){$Servidores -join ', '}else{'automático'})"
    }
    ipconfig /flushdns | Out-Null
}

function Set-PausaWU([int]$Dias) {
    $k = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    $nombres = 'PauseFeatureUpdatesStartTime','PauseFeatureUpdatesEndTime','PauseQualityUpdatesStartTime','PauseQualityUpdatesEndTime','PauseUpdatesStartTime','PauseUpdatesExpiryTime'
    if ($Dias -le 0) { $nombres | ForEach-Object { Remove-Reg $k $_ }; return }
    $ini = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $fin = (Get-Date).AddDays($Dias).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($n in $nombres) { Set-Reg $k $n $(if ($n -match 'Start') { $ini } else { $fin }) 'String' }
}

function Reset-WindowsUpdate {
    $servicios = 'wuauserv','bits','cryptsvc','msiserver'
    Stop-Service $servicios -Force -ErrorAction SilentlyContinue
    $sello = Get-Date -Format 'yyyyMMddHHmmss'
    foreach ($d in "$env:windir\SoftwareDistribution", "$env:windir\System32\catroot2") {
        if (Test-Path $d) { Rename-Item $d "$(Split-Path $d -Leaf).$sello.old" -ErrorAction Stop; Write-Log "  Renombrada $d" }
    }
    Start-Service $servicios -ErrorAction SilentlyContinue
}

function Remove-OneDriveCompleto {
    try { Uninstall-OneDrive } catch { Write-Log "  $($_.Exception.Message)" 'AVISO' }
    Start-Sleep -Seconds 3
    foreach ($d in "$env:LOCALAPPDATA\Microsoft\OneDrive", "$env:ProgramData\Microsoft OneDrive", "$env:SystemDrive\OneDriveTemp", "${env:ProgramFiles}\Microsoft OneDrive") {
        if (Test-Path $d) { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; Write-Log "  Borrada carpeta de programa: $d" }
    }
    Set-Reg 'HKCU:\Software\Classes\CLSID\{018D5C66-4533-4307-9B53-224DE2ED1FE6}' 'System.IsPinnedToNameSpaceTree' 0
    Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive' 'DisableFileSyncNGSC' 1
    Remove-Reg 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' 'OneDrive'
    Get-ScheduledTask -TaskName 'OneDrive*' -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false
    Write-Log '  Tu carpeta de archivos de OneDrive (en tu perfil) NO se ha tocado.' 'AVISO'
}

function Test-RegIgual {
    param([string]$Ruta, [string]$Nombre, $Valor, [string]$Tipo = 'DWord')
    try {
        $k = Get-ItemProperty -Path $Ruta -Name $Nombre -ErrorAction Stop
        $actual = $k.$Nombre
        if ($Tipo -eq 'Binary' -or $Valor -is [byte[]]) { $igual = ((@($actual) -join ',') -eq (@($Valor) -join ',')) }
        else { $igual = ("$actual" -eq "$Valor") }
    } catch { $igual = $false }
    if (-not $igual) { $Global:EstadoOk = $false }
}
function Test-SvcIgual {
    param([string]$Nombre, [string]$Inicio)
    $s = Get-Service -Name $Nombre -ErrorAction SilentlyContinue
    if ($s -and "$($s.StartType)" -ne $Inicio) { $Global:EstadoOk = $false }
}
function Test-TareaIgual {
    param([string[]]$Rutas, [bool]$Activar)
    foreach ($r in $Rutas) {
        $carpeta = $r.Substring(0, $r.LastIndexOf('\') + 1); $nombre = $r.Substring($r.LastIndexOf('\') + 1)
        $t = Get-ScheduledTask -TaskPath $carpeta -TaskName $nombre -ErrorAction SilentlyContinue
        if ($t -and (($t.State -ne 'Disabled') -ne $Activar)) { $Global:EstadoOk = $false }
    }
}
function Get-CacheAppx {
    if (-not $Global:CacheAppx) {
        $Global:CacheAppx = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue | ForEach-Object Name)
        if (-not $Global:CacheAppx) { $Global:CacheAppx = @(Get-AppxPackage -ErrorAction SilentlyContinue | ForEach-Object Name) }
    }
    return $Global:CacheAppx
}
function Test-BloatQuitado {
    param([string[]]$Listas)
    $inst = Get-CacheAppx
    foreach ($l in $Listas) { foreach ($p in $Global:Catalogo.listasBloatware.$l) { if ($inst | Where-Object { $_ -like $p }) { return $false } } }
    return $true
}
function Test-ProvisionadoQuitado {
    param([string[]]$Listas)
    $prov = @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications' -ErrorAction SilentlyContinue | ForEach-Object { ($_.PSChildName -split '_')[0] })
    foreach ($l in $Listas) { foreach ($p in $Global:Catalogo.listasBloatware.$l) { if ($prov | Where-Object { $_ -like $p }) { return $false } } }
    return $true
}
function Get-EstadoAjustes {
    # Comprueba cada ajuste en paralelo (4 hilos) con tiempo máximo por comprobación.
    # Devuelve líneas "id|True/False/Error/Timeout". Registra inicio, fin y duración de cada una.
    param([int]$MaxSegundos = 15)
    $t0 = Get-Date
    $lista = @($Global:Catalogo.ajustes | Where-Object { $_.comprobar })
    Write-Log "Detección: inicio ($($lista.Count) comprobaciones, máx. $MaxSegundos s cada una)."
    $prefijo = ". (Join-Path '$($Global:Raiz -replace "'","''")' 'Engine.ps1'); `$Global:EstadoOk = `$true;`n"
    $pool = [runspacefactory]::CreateRunspacePool(1, 4)
    $pool.Open()
    $pendientes = New-Object System.Collections.Generic.List[object]
    foreach ($a in $lista) {
        $ps = [powershell]::Create(); $ps.RunspacePool = $pool
        [void]$ps.AddScript("param(`$Cat, `$Log) `$Global:Catalogo = `$Cat; `$Global:RutaLog = `$Log`n" + $prefijo + $a.comprobar).AddArgument($Global:Catalogo).AddArgument($Global:RutaLog)
        $pendientes.Add(@{ A = $a; PS = $ps; H = $null; Inicio = $null })
    }
    $enMarcha = New-Object System.Collections.Generic.List[object]
    $hechos = 0; $idx = 0
    while ($hechos -lt $pendientes.Count) {
        while ($enMarcha.Count -lt 4 -and $idx -lt $pendientes.Count) {
            $w = $pendientes[$idx]; $idx++
            $w.Inicio = Get-Date; $w.H = $w.PS.BeginInvoke()
            Write-Log "  Comprobando: $($w.A.nombre) [$($w.A.id)]"
            Set-Estado "Detectando $hechos/$($pendientes.Count) · $($w.A.nombre)" ([int](100 * $hechos / $pendientes.Count))
            $enMarcha.Add($w)
        }
        foreach ($w in $enMarcha.ToArray()) {
            $seg = ((Get-Date) - $w.Inicio).TotalSeconds
            if ($w.H.IsCompleted) {
                try {
                    $out = @($w.PS.EndInvoke($w.H)); $ultimo = $out | Select-Object -Last 1; if ($ultimo -isnot [bool]) { throw 'La comprobación no devolvió un estado válido.' }; $r = $ultimo
                    if ($w.PS.Streams.Error.Count) { throw $w.PS.Streams.Error[0].Exception }
                    "$($w.A.id)|$r"; Send-Parcial "$($w.A.id)|$r"
                    Write-Log ("  -> {0}: {1} ({2:N2} s)" -f $w.A.id, $(if ($r) { 'aplicado' } else { 'no aplicado' }), $seg)
                } catch {
                    "$($w.A.id)|Error"; Send-Parcial "$($w.A.id)|Error"
                    Write-Log ("  -> {0}: ERROR {1} ({2:N2} s)" -f $w.A.id, $_.Exception.Message, $seg) 'AVISO'
                }
                $w.PS.Dispose(); [void]$enMarcha.Remove($w); $hechos++
                Set-Estado "Detectando $hechos/$($pendientes.Count) · $($w.A.nombre) ✔" ([int](100 * $hechos / $pendientes.Count))
            } elseif ($seg -gt $MaxSegundos) {
                "$($w.A.id)|Timeout"; Send-Parcial "$($w.A.id)|Timeout"; $hechos++
                Set-Estado "Detectando $hechos/$($pendientes.Count) · $($w.A.nombre) (sin respuesta)" ([int](100 * $hechos / $pendientes.Count)); $hechos--
                Write-Log ("  -> {0}: SIN RESPUESTA tras {1:N0} s, se abandona" -f $w.A.id, $seg) 'AVISO'
                try { [void]$w.PS.BeginStop($null, $null) } catch {}
                [void]$enMarcha.Remove($w); $hechos++
            }
        }
        Start-Sleep -Milliseconds 50
    }
    try { [void]$pool.BeginClose($null, $null) } catch {}
    Write-Log ("Detección: fin en {0:N1} s." -f ((Get-Date) - $t0).TotalSeconds) 'OK'
    Set-Estado 'Estado actual detectado.' 100
}

# Tamaños legibles del escáner actual.
function Format-Tam([double]$b) { if ($b -ge 1TB) { '{0:N2} TB' -f ($b / 1TB) } elseif ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f ($b / 1MB) } }
function Test-AjusteAplicado($Ajuste) {
    if (-not $Ajuste.comprobar) { return $false }
    $ps = [powershell]::Create()
    try {
        $script = 'param($Raiz,$Cat,$Codigo) $Global:Catalogo=$Cat; . (Join-Path $Raiz "Engine.ps1"); & ([scriptblock]::Create($Codigo))'
        [void]$ps.AddScript($script).AddArgument($Global:Raiz).AddArgument($Global:Catalogo).AddArgument($Ajuste.comprobar)
        $h = $ps.BeginInvoke()
        if (-not $h.AsyncWaitHandle.WaitOne(15000)) { [void]$ps.BeginStop($null,$null); throw 'La comprobación tardó más de 15 segundos. Vuelve a detectar el estado.' }
        $out = @($ps.EndInvoke($h))
        if ($ps.Streams.Error.Count) { throw $ps.Streams.Error[0].Exception }
        if (-not $out.Count -or $out[-1] -isnot [bool]) { throw 'Estado no verificable: no se ejecuta por seguridad.' }
        return $out[-1]
    } finally { if (-not $h -or $h.IsCompleted) { $ps.Dispose() } }
}

# Lecturas reales, sin porcentajes de ejemplo. CIM usa clases no localizadas.
function ConvertTo-PorcentajeValido($Valor) {
    if($null -eq $Valor -or $Valor -is [bool] -or [string]::IsNullOrWhiteSpace([string]$Valor)){return $null}
    try {$v=[double]$Valor;if(-not [double]::IsNaN($v) -and -not [double]::IsInfinity($v) -and $v -ge 0 -and $v -le 100){return [Math]::Round($v,1)}} catch {}
    return $null
}
function Get-UsoGpu {
    try {
        $null=Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -OperationTimeoutSec 2 -ErrorAction Stop
        Start-Sleep -Milliseconds 1000
        $motores=@(Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine -OperationTimeoutSec 2 -ErrorAction Stop)
        $grupos=@{};$instancias=@{};$incoherente=$false
        foreach($m in $motores){
            # Identidad de adaptador + motor físico: sumar procesos SOLO dentro de ese motor.
            if([string]$m.Name -notmatch '^pid_\d+_(luid_.+_phys_\d+_eng_\d+_engtype_.+)$'){continue}
            $clave=$Matches[1]
            if($instancias.ContainsKey([string]$m.Name)){$incoherente=$true;break}
            $instancias[[string]$m.Name]=$true
            if($null -eq (ConvertTo-PorcentajeValido $m.UtilizationPercentage)){$incoherente=$true;break}
            # No redondear cada proceso antes de sumar: perdería cargas pequeñas acumuladas.
            $v=[double]$m.UtilizationPercentage
            if(-not $grupos.ContainsKey($clave)){$grupos[$clave]=0.0};$grupos[$clave]+=$v
        }
        if($grupos.Count -and -not $incoherente){
            $max=($grupos.Values | Measure-Object -Maximum).Maximum
            # No sumar motores diferentes ni GPU diferentes; no recortar >100 como si fuera válido.
            if($max -le 100){return [pscustomobject]@{Valor=[Math]::Round($max,1);Fuente='Motor GPU más ocupado (todas las gráficas); suma de procesos del mismo motor, segunda muestra'}}
        }
    } catch {}
    return [pscustomobject]@{Valor=$null;Fuente='No se pudo leer; controlador/contadores GPU no disponibles o incoherentes'}
}
# Instantánea de solo lectura. Nueve tarjetas estables; un fallo nunca genera hardware ficticio.
function Get-ScannerInfo {
    param([ValidateRange(1,60)][int]$TimeoutSegundos=10)
    # El límite pertenece al escáner, también en runspaces nuevos. No depende de helpers antiguos.
    $cpu=$null;$gpus=@();$os=$null;$cs=$null;$ram=@();$vols=@();$resultado=New-Object Collections.Generic.List[object]
    $spec=@(@('cpu','Procesador'),@('gpu','Gráfica'),@('ram','Memoria'),@('discos','Almacenamiento'),@('volumenes','Volúmenes'),@('sistema','Sistema'),@('pantalla','Pantalla'),@('placa','Placa'),@('seguridad','Energía y seguridad'))
    $idx=0
    foreach($s in $spec){
        $idx++;Set-Estado "Escaneando $($s[1].ToLowerInvariant()) ($idx/9)…" ([int](100*($idx-1)/9))
        $filas=New-Object Collections.Generic.List[object];$resumen='No disponible';$errorLectura='';$extra=@{}
        try {
            switch($s[0]){
                'cpu' {
                    $cpu=Get-CimInstance Win32_Processor -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop | Select-Object -First 1
                    if(-not $cpu){throw 'Windows no devuelve un procesador.'};$resumen=$cpu.Name.Trim()
                    $filas.Add(@('Núcleos / hilos',"$($cpu.NumberOfCores) / $($cpu.NumberOfLogicalProcessors)"));$filas.Add(@('Frecuencia máxima',"$($cpu.MaxClockSpeed) MHz"));$filas.Add(@('Zócalo',"$($cpu.SocketDesignation)"))
                    $extra.Cpu=$resumen
                }
                'gpu' {
                    $lecturaGpu=Get-UsoGpu
                    $gpus=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop)
                    $g=$gpus | Sort-Object @{Expression={if($_.CurrentHorizontalResolution){0}else{1}}} | Select-Object -First 1
                    if(-not $g){throw 'No se puede leer la gráfica.'};$resumen=$g.Name;$extra.Gpu=($gpus.Name -join ' / ');$extra.Nvidia=(@($gpus | Where-Object {$_.Name -match 'NVIDIA'}).Count -gt 0)
                    $filas.Add(@('Controlador',"$($g.DriverVersion)"))
                    if($g.AdapterRAM -gt 0){$filas.Add(@('VRAM (WMI, aprox.)',(Format-Tam $g.AdapterRAM)))}
                    $filas.Add(@('Gráficas detectadas',"$($gpus.Count)"));$filas.Add(@('Uso de GPU',$(if($null -ne $lecturaGpu.Valor){"$($lecturaGpu.Valor) % · motor más ocupado"}else{'No se pudo leer'})))
                }
                'ram' {
                    $cs=Get-CimInstance Win32_ComputerSystem -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop;$os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop
                    $ram=@(Get-CimInstance Win32_PhysicalMemory -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop);$tipos=@{20='DDR';21='DDR2';24='DDR3';26='DDR4';34='DDR5'};$tipo=(@($ram | ForEach-Object {$tipos[[int]$_.SMBIOSMemoryType]} | Select-Object -Unique) -join ' / ')
                    $resumen=((Format-Tam $cs.TotalPhysicalMemory)+' '+$tipo).Trim();$extra.Ram=$resumen
                    $filas.Add(@('Módulos',"$($ram.Count)"));$vel=@($ram.ConfiguredClockSpeed | Where-Object {$_ -gt 0} | Select-Object -Unique);if($vel.Count){$filas.Add(@('Velocidad',(($vel -join ' / ')+' MHz')))}
                    if($os.TotalVisibleMemorySize -gt 0 -and $null -ne $os.FreePhysicalMemory -and $os.FreePhysicalMemory -ge 0 -and $os.FreePhysicalMemory -le $os.TotalVisibleMemorySize){$uso=[Math]::Round(100*(1-$os.FreePhysicalMemory/$os.TotalVisibleMemorySize),1);$extra.RamUso=$uso;$filas.Add(@('En uso',"$uso %"));$filas.Add(@('Disponible',(Format-Tam ($os.FreePhysicalMemory*1KB))))}
                }
                'discos' {
                    $discos=@(Get-CimInstance -Namespace root\Microsoft\Windows\Storage -ClassName MSFT_PhysicalDisk -OperationTimeoutSec $TimeoutSegundos -ErrorAction SilentlyContinue)
                    if($discos.Count){$resumen=Format-Tam (($discos | Measure-Object Size -Sum).Sum);$medios=@{3='HDD';4='SSD';5='SCM'};foreach($d in $discos | Select-Object -First 3){$m=$medios[[int]$d.MediaType];if(-not $m){$m='Tipo no informado'};$filas.Add(@($d.FriendlyName,((Format-Tam $d.Size)+' · '+$m)))};$extra.DiscosAviso=(@($discos | Where-Object {$null -ne $_.HealthStatus -and $_.HealthStatus -ne 0}).Count -gt 0)}
                    else{$discos=@(Get-CimInstance Win32_DiskDrive -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop);if(-not $discos.Count){throw 'No se pudieron leer los discos.'};$resumen=Format-Tam (($discos | Measure-Object Size -Sum).Sum);foreach($d in $discos | Select-Object -First 3){$filas.Add(@($d.Model,(Format-Tam $d.Size)))}}
                    $filas.Add(@('Unidades físicas',"$($discos.Count)"))
                }
                'volumenes' {
                    $vols=@(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop | Where-Object {$_.Size -gt 0});$resumen="$($vols.Count) unidades locales"
                    foreach($v in $vols | Select-Object -First 4){$filas.Add(@($v.DeviceID,((Format-Tam $v.FreeSpace)+' libres / '+(Format-Tam $v.Size))))}
                    $extra.PocoEspacio=@($vols | Where-Object {$_.FreeSpace/$_.Size -lt .15} | ForEach-Object {$_.DeviceID})
                }
                'sistema' {
                    if(-not $os){$os=Get-CimInstance Win32_OperatingSystem -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop};$cv=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
                    $resumen=$os.Caption;$filas.Add(@('Versión',"$($cv.DisplayVersion) · $($os.BuildNumber).$($cv.UBR)"));$filas.Add(@('Arquitectura',$os.OSArchitecture));$filas.Add(@('Equipo',$env:COMPUTERNAME))
                    if($os.LastBootUpTime){$uptime=(Get-Date)-[datetime]$os.LastBootUpTime;$filas.Add(@('Encendido',("{0} d {1} h {2} min" -f [int][Math]::Floor($uptime.TotalDays),$uptime.Hours,$uptime.Minutes)))}
                    $extra.Procesos=@(Get-Process -ErrorAction Stop).Count
                }
                'pantalla' {
                    if(-not $gpus.Count){$gpus=@(Get-CimInstance Win32_VideoController -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop)};$g=$gpus | Where-Object {$_.CurrentHorizontalResolution -gt 0} | Select-Object -First 1
                    if(-not $g){throw 'No se informa una pantalla activa (sesión remota o controlador).'}
                    $resumen="$($g.CurrentHorizontalResolution) × $($g.CurrentVerticalResolution)";$filas.Add(@('Frecuencia',"$($g.CurrentRefreshRate) Hz"));$filas.Add(@('Salida',$g.Name));$filas.Add(@('Fuente','Pantalla principal según WMI'))
                }
                'placa' {
                    $b=Get-CimInstance Win32_BaseBoard -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop;$bios=Get-CimInstance Win32_BIOS -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop
                    $resumen=("$($b.Manufacturer) $($b.Product)").Trim();$filas.Add(@('BIOS',$bios.SMBIOSBIOSVersion));$filas.Add(@('Fabricante BIOS',$bios.Manufacturer))
                    if($bios.ReleaseDate){$filas.Add(@('Fecha BIOS',([datetime]$bios.ReleaseDate).ToString('dd/MM/yyyy')))}
                }
                'seguridad' {
                    $p=Get-CimInstance -Namespace root\cimv2\power -ClassName Win32_PowerPlan -Filter 'IsActive=TRUE' -OperationTimeoutSec $TimeoutSegundos -ErrorAction SilentlyContinue | Select-Object -First 1
                    $resumen=if($p){$p.ElementName}else{'Plan no disponible'}
                    $sb=try{if(Confirm-SecureBootUEFI -ErrorAction Stop){'Activado'}else{'Desactivado'}}catch{'No disponible'};$filas.Add(@('Arranque seguro',$sb));$extra.ArranqueSeguro=$sb
                    $tpm=try{Get-CimInstance -Namespace root\cimv2\security\microsofttpm -ClassName Win32_Tpm -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop | Select-Object -First 1}catch{$null};$filas.Add(@('TPM',$(if($tpm){'Presente · '+(($tpm.SpecVersion -split ',')[0])}else{'No informado'})))
                    $dg=try{Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -OperationTimeoutSec $TimeoutSegundos -ErrorAction Stop}catch{$null}
                    $integridad=if($dg){if(@($dg.SecurityServicesRunning) -contains 2){'En ejecución'}else{'No está en ejecución'}}else{'No disponible'};$filas.Add(@('Integridad de memoria',$integridad));$extra.Integridad=$integridad
                    $bat=Get-CimInstance Win32_Battery -OperationTimeoutSec $TimeoutSegundos -ErrorAction SilentlyContinue | Select-Object -First 1;if($bat){$filas.Add(@('Batería',"$($bat.EstimatedChargeRemaining) %"))}
                }
            }
        } catch {$errorLectura=$_.Exception.Message;Write-Log "Escáner/$($s[0]): $errorLectura" 'AVISO';$filas.Add(@('Lectura','No disponible; consulta el registro'))}
        $obj=[pscustomobject]@{Id=$s[0];Categoria=$s[1];Resumen=$resumen;Filas=$filas.ToArray();Datos=$extra;Error=$errorLectura}
        $resultado.Add($obj);Send-Parcial $obj
    }
    Set-Estado 'Escaneo terminado. Lecturas de esta instantánea, no en tiempo real.' 100
    return $resultado.ToArray()
}

# Port nativo de extras/LimpiezaWindows11.bat. No depende del BAT al ejecutar el EXE.
function Get-CiblesTemporales {
    $rutas=@('C:\Windows\Temp')
    if($env:TEMP){
        $temp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')
        # Lista local y cerrada. Nunca Documentos, una raíz, UNC o una ruta relativa.
        if($env:TEMP -notmatch '^[A-Za-z]:\\' -or $temp -notmatch '^[A-Za-z]:\\(?:[^\\]+\\)*(?:Temp|Tmp)$'){throw 'TEMP no es una carpeta temporal local segura. No se ha borrado nada.'}
        $rutas+=$temp
    }
    return @($rutas | Select-Object -Unique)
}
function Get-CiblesLimpiezaWindows {
    return @(@(
        'C:\Windows\SoftwareDistribution\Download',
        'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache'
    ) + @(Get-CiblesTemporales) | Select-Object -Unique)
}
function Remove-ContenidoLimpieza([string]$Ruta) {
    # Lista cerrada; nunca se usa un comodín para ampliar la raíz de borrado.
    $base=[IO.Path]::GetFullPath($Ruta).TrimEnd('\')
    if($base -notin @(Get-CiblesLimpiezaWindows)){throw "Carpeta fuera de la limpieza permitida: $Ruta"}
    if(-not (Test-Path -LiteralPath $base)){return 0}
    # Ni la raíz ni sus antecesores pueden ser enlaces/junctions.
    $cursor=$base
    while($cursor){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw "Se omite un enlace de carpetas: $cursor"}
        $padre=[IO.Path]::GetDirectoryName($cursor)
        if($padre -eq $cursor){break};$cursor=$padre
    }
    $protegidas=@($Global:Raiz,$Global:DirectorioCopias,$env:OW_LAUNCHER_PATH,$env:OW_CLOSE_REQUEST) | Where-Object {$_} | ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\')}
    $separador=[IO.Path]::DirectorySeparatorChar
    $contexto=@{Omitidos=0}
    $vaciar={
        param([string]$directorio)
        foreach($entrada in @(Get-ChildItem -LiteralPath $directorio -Force -ErrorAction Stop)){
            $rutaCompleta=[IO.Path]::GetFullPath($entrada.FullName).TrimEnd('\')
            $protegida=$false
            foreach($p in $protegidas){
                if($rutaCompleta -eq $p -or $rutaCompleta.StartsWith($p+$separador,[StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($rutaCompleta+$separador,[StringComparison]::OrdinalIgnoreCase)){$protegida=$true;break}
            }
            if($protegida -or ($entrada.Attributes -band [IO.FileAttributes]::ReparsePoint)){$contexto.Omitidos++;continue}
            try {
                if($entrada.PSIsContainer){
                    & $vaciar $entrada.FullName
                    # Solo quitar un directorio vacío; nunca -Recurse a través de un enlace.
                    if(-not @(Get-ChildItem -LiteralPath $entrada.FullName -Force -ErrorAction Stop).Count){Remove-Item -LiteralPath $entrada.FullName -Force -ErrorAction Stop}
                }else{Remove-Item -LiteralPath $entrada.FullName -Force -ErrorAction Stop}
            } catch {$contexto.Omitidos++}
        }
    }
    & $vaciar $base
    return [int]$contexto.Omitidos
}
function Invoke-LimpiezaWindows {
    if(-not (Test-AdminRestauracion)){throw 'Abre la app como administrador para limpiar Windows.'}
    # Validar TODAS las raíces y medir antes de detener servicios o borrar.
    $cibles=@(Get-CiblesLimpiezaWindows)
    $antes=[Math]::Round((Get-PSDrive -Name C -ErrorAction Stop).Free / 1GB,2)
    $avisos=New-Object 'Collections.Generic.List[string]'
    $servicios='bits','wuauserv','UsoSvc','dosvc';$detenidos=@{};$reinicio=$false;$despues=$null
    Write-Log ('Espacio libre antes en C: {0:N2} GB.' -f $antes)
    Send-Parcial ([pscustomobject]@{Tipo='LIMPIEZA_INICIO';AntesGB=$antes})
    try {
        Set-Estado '1/8 · Pausando las descargas de Windows…' 5
        foreach($nombre in $servicios){
            try {
                $s=Get-Service -Name $nombre -ErrorAction Stop
                if($s.Status -ne 'Stopped'){
                    Stop-Service -Name $nombre -Force -ErrorAction Stop -WarningAction SilentlyContinue
                    (Get-Service -Name $nombre -ErrorAction Stop).WaitForStatus('Stopped',[TimeSpan]::FromSeconds(20))
                }
                $detenidos[$nombre]=$true
            } catch {$avisos.Add("No se pudo pausar ${nombre}: $($_.Exception.Message)")}
        }
        Set-Estado '2/8 · Limpiando descargas y caché de actualizaciones…' 15
        foreach($ruta in $cibles){
            if($ruta -like '*\SoftwareDistribution\Download' -and -not ($detenidos['bits'] -and $detenidos['wuauserv'] -and $detenidos['UsoSvc'])){$avisos.Add('Descargas de Windows Update omitidas: siguen en uso.');continue}
            if($ruta -like '*\DeliveryOptimization\Cache' -and -not $detenidos['dosvc']){$avisos.Add('Caché de Delivery Optimization omitida: sigue en uso.');continue}
            if($ruta -notlike '*\SoftwareDistribution\Download' -and $ruta -notlike '*\DeliveryOptimization\Cache'){Set-Estado '3/8 · Limpiando archivos temporales…' 30}
            try {
                $omitidos=Remove-ContenidoLimpieza $ruta
                if($omitidos){$avisos.Add("${ruta}: $omitidos archivos o carpetas en uso, protegidos o enlazados se han conservado.")}
            } catch {$avisos.Add("No se pudo limpiar ${ruta}: $($_.Exception.Message)")}
        }
        Set-Estado '4/8 · Vaciando la Papelera…' 42
        try {Clear-RecycleBin -Force -ErrorAction Stop | Out-Null} catch {$avisos.Add("Papelera: $($_.Exception.Message)")}
        Set-Estado '5/8 · Vaciando la caché DNS…' 48
        try {
            $codigo=Invoke-ConProgreso -Exe 'ipconfig.exe' -Argumentos '/flushdns' -Nombre 'Vaciando DNS'
            if($codigo -ne 0){throw "Windows devolvió el código $codigo."}
        } catch {$avisos.Add("DNS: $($_.Exception.Message)")}
        Set-Estado '6/8 · Limpiando componentes antiguos. Puede tardar varios minutos…' 55
        try {
            $codigo=Invoke-ConProgreso -Exe 'Dism.exe' -Argumentos '/Online /Cleanup-Image /StartComponentCleanup' -Nombre 'Limpiando componentes de Windows'
            if($codigo -eq 3010){$reinicio=$true}elseif($codigo -ne 0){throw "DISM devolvió el código $codigo."}
        } catch {$avisos.Add("Componentes de Windows: $($_.Exception.Message)")}
    } finally {
        # Siempre se intenta reanudar los cuatro, incluso si falló un paso anterior.
        Set-Estado '7/8 · Reanudando los servicios de Windows…' 88
        foreach($nombre in $servicios){
            try {Start-Service -Name $nombre -ErrorAction Stop -WarningAction SilentlyContinue}
            catch {$avisos.Add("No se pudo reanudar ${nombre}: $($_.Exception.Message)")}
        }
    }
    Set-Estado '8/8 · Midiendo el espacio libre final…' 95
    try {$despues=[Math]::Round((Get-PSDrive -Name C -ErrorAction Stop).Free / 1GB,2)} catch {$avisos.Add('No se pudo medir el espacio final en C:.')}
    foreach($aviso in $avisos){Write-Log $aviso 'AVISO'}
    $texto=if($null -ne $despues){'Limpieza terminada. Antes: {0:N2} GB; después: {1:N2} GB libres en C:.' -f $antes,$despues}else{'Limpieza terminada sin medición final.'}
    Write-Log $texto $(if($avisos.Count){'AVISO'}else{'OK'});Set-Estado $texto 100
    return [pscustomobject]@{Tipo='LIMPIEZA';AntesGB=$antes;DespuesGB=$despues;Avisos=@($avisos.ToArray());RequiereReinicio=$reinicio}
}

# Acciones independientes de Acelerar: sin limpiar Update, Papelera ni reiniciar Explorer.
function Invoke-LimpiarTemporales {
    if(-not (Test-AdminRestauracion)){throw 'Abre OptimiZation como administrador para limpiar temporales.'}
    $rutas=@(Get-CiblesTemporales) # Validación completa antes del primer borrado.
    $avisos=New-Object 'Collections.Generic.List[string]'
    foreach($ruta in $rutas){
        Set-Estado "Limpiando temporales: $ruta" 25
        try {
            $n=Remove-ContenidoLimpieza $ruta
            if($n){$avisos.Add("${ruta}: $n elementos en uso, protegidos o enlazados se han conservado.")}
        } catch {$avisos.Add("No se pudo limpiar ${ruta}: $($_.Exception.Message)")}
    }
    foreach($aviso in $avisos){Write-Log $aviso 'AVISO'}
    Set-Estado 'Limpieza de temporales terminada.' 100
    return [pscustomobject]@{Tipo='TEMPORALES';Avisos=@($avisos.ToArray())}
}
function Invoke-VaciarDns {
    $codigo=Invoke-ConProgreso -Exe 'ipconfig.exe' -Argumentos '/flushdns' -Nombre 'Vaciando la caché DNS'
    if($codigo -ne 0){throw "No se pudo vaciar la caché DNS (código $codigo)."}
    Write-Log 'Caché DNS vaciada.' 'OK'
    return 'DNS_OK'
}

# SRRemoveRestorePoint: API oficial de SrClient.dll, cargada bajo demanda desde System32.
function Initialize-ApiRestauracion {
    if('OptimizationRestorePoints' -as [type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
public static class OptimizationRestorePoints {
    [DllImport("kernel32.dll", EntryPoint="LoadLibraryW", CharSet=CharSet.Unicode, ExactSpelling=true, SetLastError=true)]
    static extern IntPtr LoadLibraryW(string path);
    [DllImport("kernel32.dll", CharSet=CharSet.Ansi, ExactSpelling=true, SetLastError=true)]
    static extern IntPtr GetProcAddress(IntPtr module, string name);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    [UnmanagedFunctionPointer(CallingConvention.Winapi)] delegate uint RemovePoint(uint sequence);
    public static uint Remove(uint sequence) {
        if(sequence==0) throw new ArgumentOutOfRangeException("sequence");
        // No buscar DLLs en el directorio actual ni en el PATH.
        var module=LoadLibraryW(Path.Combine(Environment.SystemDirectory,"SrClient.dll"));
        if(module==IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(),"No se pudo cargar la API de Restaurar sistema.");
        try {
            var address=GetProcAddress(module,"SRRemoveRestorePoint");
            if(address==IntPtr.Zero) throw new EntryPointNotFoundException("SRRemoveRestorePoint no está disponible.");
            var remove=(RemovePoint)Marshal.GetDelegateForFunctionPointer(address,typeof(RemovePoint));
            return remove(sequence); // DWORD devuelto por la API, no GetLastWin32Error.
        } finally {FreeLibrary(module);}
    }
}
'@
}
function Invoke-SRRemoveRestorePoint([uint32]$Numero) {
    Initialize-ApiRestauracion
    return [OptimizationRestorePoints]::Remove($Numero)
}
function Remove-PuntosRestauracion {
    param([object[]]$Numeros, [switch]$Confirmado)
    if(-not $Confirmado){throw 'Borrado irreversible: se requiere confirmación explícita de los puntos seleccionados.'}
    if(-not (Test-AdminRestauracion)){throw 'Abre OptimiZation como administrador para eliminar puntos de restauración.'}
    if(-not $Numeros -or $Numeros.Count -eq 0){throw 'No hay puntos seleccionados. No se borra nada.'}
    # Validar TODOS los identificadores antes de enumerar o borrar; nunca comodines ni /All.
    $ids=@($(foreach($valor in $Numeros){
        [uint32]$id=0
        if([string]$valor -notmatch '^[1-9][0-9]*$' -or -not [uint32]::TryParse([string]$valor,[ref]$id)){throw 'Número de punto no válido. No se borra nada.'}
        $id
    }) | Select-Object -Unique)
    $actuales=@(Get-PuntosRestauracion)
    $resultados=New-Object 'Collections.Generic.List[object]'
    foreach($id in $ids){
        if($id -notin @($actuales.SequenceNumber)){
            $resultados.Add([pscustomobject]@{Numero=$id;Eliminado=$false;Mensaje='Ya no figura en Windows; no se ha llamado al borrado.'});continue
        }
        Set-Estado "Eliminando punto de restauración nº $id…" 20
        try {
            $codigo=Invoke-SRRemoveRestorePoint $id
            if($codigo -ne 0){throw (New-Object ComponentModel.Win32Exception([int]$codigo))}
            # La API es la autoridad. Verificar publicación de la lista, sin repetir el borrado.
            $verificado=$false;$detalle=''
            try {
                for($intento=0;$intento -lt 6;$intento++){
                    if($id -notin @((Get-PuntosRestauracion).SequenceNumber)){$verificado=$true;break}
                    if($intento -lt 5){Start-Sleep -Seconds 1}
                }
            } catch {$detalle=$_.Exception.Message}
            $mensaje=if($verificado){'Eliminado y comprobado en Windows.'}else{"Windows aceptó el borrado; lista aún sin verificar. Actualiza la lista. $detalle"}
            Write-Log "Punto nº ${id}: $mensaje" $(if($verificado){'OK'}else{'AVISO'})
            $resultados.Add([pscustomobject]@{Numero=$id;Eliminado=$true;Verificado=$verificado;Mensaje=$mensaje})
        } catch {
            $mensaje="No se pudo eliminar: $($_.Exception.Message). Revisa Protección del sistema. No se ha intentado un borrado global."
            Write-Log "Punto nº ${id}: $mensaje" 'ERROR'
            $resultados.Add([pscustomobject]@{Numero=$id;Eliminado=$false;Verificado=$false;Mensaje=$mensaje})
        }
    }
    Set-Estado 'Borrado de puntos seleccionados terminado. Actualizando lista…' 100
    return [pscustomobject]@{Tipo='PUNTOS_ELIMINADOS';Resultados=@($resultados.ToArray())}
}

# API oficial: Restore prepara el punto; la restauración real ocurre durante el reinicio.
# https://learn.microsoft.com/en-us/windows/win32/sr/restore-systemrestore
function Start-RestauracionSeleccionada {
    param([object]$Numero, [switch]$Confirmado)
    try {
        if(-not $Confirmado){throw 'Se requiere confirmar expresamente el punto de restauración.'}
        if(-not (Test-AdminRestauracion)){throw 'Abre OptimiZation como administrador para restaurar Windows.'}
        [uint32]$id=0
        if([string]$Numero -notmatch '^[1-9][0-9]*$' -or -not [uint32]::TryParse([string]$Numero,[ref]$id)){throw 'Número de punto no válido. Selecciona un único punto de la lista.'}
        $actuales=@(Get-PuntosRestauracion)
        if($id -notin @($actuales.SequenceNumber)){throw 'Ese punto ya no figura en Windows. Actualiza la lista y vuelve a seleccionar.'}
        Set-Estado "Solicitando restaurar el punto nº $id…" 10
        $r=Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName Restore -Arguments @{SequenceNumber=$id} -OperationTimeoutSec 180 -ErrorAction Stop
        # Ausencia de respuesta/ReturnValue NO equivale a S_OK (cero).
        [uint32]$codigo=0
        if($null -eq $r -or -not $r.PSObject.Properties['ReturnValue'] -or -not [uint32]::TryParse([string]$r.ReturnValue,[ref]$codigo)){throw 'La API de Windows no devolvió un código de aceptación válido.'}
        if($codigo -ne 0){throw ("La API de Windows rechazó la restauración (código 0x{0:X8})." -f $codigo)}
        Write-Log "Windows aceptó restaurar el punto nº $id. Es necesario reiniciar manualmente; la restauración aún no se ha completado." 'OK'
        Set-Estado 'Solicitud aceptada. Reinicia Windows manualmente para completar la restauración.' 100
        return [pscustomobject]@{Tipo='RESTAURACION_SOLICITADA';Numero=$id;ReinicioNecesario=$true}
    } catch {
        $mensaje="No se pudo iniciar o confirmar la restauración: $($_.Exception.Message) No se reintenta ni se elige otro punto. No se reinicia automáticamente."
        Write-Log $mensaje 'ERROR'
        return [pscustomobject]@{Tipo='RESTAURACION_ERROR';Mensaje=$mensaje}
    }
}
