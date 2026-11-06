# Módulo desinstalador: inventario, desinstalación oficial, escaneo y eliminación directa de restos.
# Código propio (MIT). Inspirado en las ideas de Bulk Crap Uninstaller (Apache-2.0), sin copiar su código.


function ConvertTo-Clave([string]$t) {
    if (-not $t) { return '' }
    $t = $t.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''
    $t = $t -replace '\(.*?\)', '' -replace '\b(x64|x86|64-bit|32-bit|version|versión)\b', '' -replace '\d+(\.\d+)+', ''
    return ($t.ToLowerInvariant() -replace '[^a-z0-9]', '')
}

function Get-AppsInstaladas {
    param([switch]$IncluirAppx)
    $rutas = @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
               'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall')
    $lista = New-Object System.Collections.Generic.List[FilaOpt]
    foreach ($r in $rutas) {
        Get-ChildItem $r -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DisplayName -or $p.SystemComponent -eq 1 -or $p.ParentKeyName -or $p.ReleaseType -match 'Update|Hotfix') { return }
            if (-not $p.UninstallString -and -not $p.QuietUninstallString) { return }
            $d = @{ Tipo='Win32'; DisplayName=$p.DisplayName; Publisher=$p.Publisher; InstallLocation=$p.InstallLocation
                    UninstallString=$p.UninstallString; Quiet=$p.QuietUninstallString; KeyPath=$_.PSPath; KeyName=$_.PSChildName }
            $f = New-Object FilaOpt
            $f.Nombre = $p.DisplayName; $f.Detalle = $p.Publisher; $f.Tipo = 'Win32'; $f.Ruta = $p.InstallLocation; $f.Datos = $d
            $lista.Add($f)
        }
    }
    if ($IncluirAppx) {
        Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { -not $_.IsFramework -and -not $_.NonRemovable -and $_.SignatureKind -ne 'System' } | ForEach-Object {
            $d = @{ Tipo='Appx'; DisplayName=$_.Name; Publisher=$_.Publisher; InstallLocation=$_.InstallLocation; PackageFullName=$_.PackageFullName; PackageFamilyName=$_.PackageFamilyName }
            $f = New-Object FilaOpt
            $f.Nombre = $_.Name; $f.Detalle = ($_.Publisher -replace '^CN=([^,]+).*','$1'); $f.Tipo = 'Tienda'; $f.Ruta = $_.InstallLocation; $f.Datos = $d
            $lista.Add($f)
        }
    }
    return ($lista | Sort-Object Nombre)
}

function Invoke-DesinstaladorOficial($d) {
    if ($d.Tipo -eq 'Appx') {
        Remove-AppxPackage -Package $d.PackageFullName -ErrorAction Stop
        return 0
    }
    $cmd = if ($d.Quiet) { $d.Quiet } else { $d.UninstallString }
    Write-Log "  Lanzando desinstalador oficial: $cmd"
    if ($cmd -match 'msiexec' -and $cmd -match '\{[0-9A-Fa-f\-]{36}\}') {
        $p = Start-Process msiexec.exe -ArgumentList "/x $($Matches[0]) /qb /norestart" -Wait -PassThru
    } else {
        $p = Start-Process cmd.exe -ArgumentList "/c `"$cmd`"" -Wait -PassThru
    }
    return $p.ExitCode
}

function Get-RutasProtegidas {
    $r = @($env:windir, "$env:windir\System32", $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432, $env:ProgramData,
           $env:APPDATA, $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", "$env:LOCALAPPDATA\Programs", $env:USERPROFILE, ($env:SystemDrive + '\'),
           "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files", "$env:ProgramFiles\WindowsApps",
           "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs",
           [Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop")
    return ($r | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLowerInvariant() })
}
$Global:ServiciosProtegidos = @('RpcSs','RpcEptMapper','DcomLaunch','Winmgmt','VSS','swprv','EventLog','SamSs','LSM','PlugPlay','Power','ProfSvc','Schedule','BFE','mpssvc','WinDefend','TrustedInstaller','CryptSvc','LanmanWorkstation','LanmanServer','Dhcp','Dnscache','NlaSvc','nsi')
$Global:NombresProtegidos = @('microsoft','windows','common files','microsoft shared','windowsapps','windows defender','windows nt','internet explorer',
    'packages','temp','programs','microsoft.net','dotnet','reference assemblies','windows kits','msbuild','windowspowershell','installshield installation information',
    'package cache','nvidia corporation','intel','amd','realtek','google','mozilla','classes','policies','wow6432node','clients','registeredapplications','system','software')

function Get-RutaCanonica([string]$Ruta) {
    if (-not $Ruta -or $Ruta -notmatch '^[A-Za-z]:\\' -or $Ruta -match '[*?]' -or $Ruta.Substring(2).Contains(':')) { throw 'Ruta no válida para eliminar restos.' }
    [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Ruta)).TrimEnd('\').ToLowerInvariant()
}
function Test-EnRuta([string]$Ruta, [string]$Base) {
    $Ruta -eq $Base -or $Ruta.StartsWith($Base.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)
}
function Test-Protegida([string]$ruta, $otrasApps) {
    if (-not $ruta) { return $true }
    $n = $ruta.TrimEnd('\').ToLowerInvariant()
    if ($n -like '*registry::*' -or $n -like 'hk*:*') {
        $reg = (ConvertTo-RutaReg $n).ToLowerInvariant()
        if ($reg -notmatch '^hk(cu|lm)\\software\\[^\\]+') { return $true }
        $hoja = ($reg -split '\\')[-1]
        if ($Global:NombresProtegidos -contains $hoja) { return $true }
        # Solo se permiten claves de aplicaciones. Las políticas y el sistema quedan protegidos.
        if ($reg -match '^hklm\\software\\(wow6432node\\)?microsoft\\windows\\currentversion\\uninstall\\[^\\]+$' -or $reg -match '^hkcu\\software\\microsoft\\windows\\currentversion\\uninstall\\[^\\]+$') { return $false }
        if ($reg -match '^hk(cu|lm)\\software\\(wow6432node\\)?(microsoft|classes|policies)(\\|$)') { return $true }
        return $false
    }
    try { $n = Get-RutaCanonica $ruta } catch { return $true }
    foreach ($p in @(Get-RutasProtegidas)) {
        if ($n -eq $p -or $p.StartsWith($n + '\')) { return $true }
    }
    foreach ($base in @($env:windir, "$env:ProgramFiles\WindowsApps", "${env:ProgramFiles(x86)}\WindowsApps", "$env:ProgramFiles\Common Files", "${env:ProgramFiles(x86)}\Common Files", "$env:ProgramData\Microsoft\Windows", "$env:LOCALAPPDATA\Microsoft\Windows", [Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('MyPictures'))) {
        if ($base -and (Test-EnRuta $n $base.TrimEnd('\').ToLowerInvariant())) { return $true }
    }
    if ($Global:NombresProtegidos -contains (Split-Path $n -Leaf)) { return $true }
    # No seguir un enlace/junction hacia otra ubicación, ni siquiera si el nombre coincide.
    $actual = $n
    while ($actual -and $actual -match '^[a-z]:\\') {
        $item = Get-Item -LiteralPath $actual -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $true }
        $padre = Split-Path $actual -Parent
        if ($padre -eq $actual) { break }; $actual = $padre
    }
    foreach ($o in $otrasApps) {
        $loc = $o.Datos.InstallLocation
        if ($loc) {
            try { $l = Get-RutaCanonica $loc } catch { continue }
            if ((Test-EnRuta $l $n) -or (Test-EnRuta $n $l)) { return $true }
        }
    }
    return $false
}

function New-Resto($tipo, $ruta, $puntos, $motivo) {
    $f = New-Object FilaOpt
    $f.Tipo = $tipo; $f.Ruta = $ruta; $f.Puntuacion = $puntos; $f.Detalle = $motivo
    $f.Confianza = if ($puntos -ge 75) { 'Alta' } elseif ($puntos -ge 45) { 'Media' } else { 'Baja' }
    $f.Seleccionado = ($puntos -ge 75)
    return $f
}

function Find-Restos {
    param($App, $TodasLasApps)
    $d = $App.Datos
    $Global:RutasProtegidas = Get-RutasProtegidas
    $otras = @($TodasLasApps | Where-Object { -not [object]::ReferenceEquals($_, $App) })
    $kNombre = ConvertTo-Clave $d.DisplayName
    $kEditor = ConvertTo-Clave ($d.Publisher -replace '^CN=([^,]+).*','$1')
    $editorCompartido = @($otras | Where-Object { (ConvertTo-Clave $_.Datos.Publisher) -eq $kEditor -and $kEditor }).Count -gt 0
    $res = New-Object System.Collections.Generic.List[FilaOpt]
    $vistos = @{}
    $add = { param($t,$r,$p,$m)
        if (-not $r -or $vistos.ContainsKey($r.ToLowerInvariant())) { return }
        if ($t -in 'Carpeta','Acceso directo','Registro' -and (Test-Protegida $r $otras)) { Write-Log "  Ruta protegida, se ignora: $r"; return }
        $vistos[$r.ToLowerInvariant()] = 1; $res.Add((New-Resto $t $r $p $m)) }

    if ($d.Tipo -eq 'Appx') {
        foreach ($b in @("$env:LOCALAPPDATA\Packages\$($d.PackageFamilyName)")) { if (Test-Path $b) { & $add 'Carpeta' $b 95 'Datos de la app de la Tienda' } }
        return $res
    }
    if ($kNombre.Length -lt 3) { Write-Log '  Nombre demasiado corto para buscar restos con seguridad.' 'AVISO'; return $res }

    # 1. Carpeta de instalación declarada
    if ($d.InstallLocation -and (Test-Path $d.InstallLocation)) { & $add 'Carpeta' $d.InstallLocation.TrimEnd('\') 95 'Carpeta de instalación declarada' }
    # 2. Carpeta deducida del desinstalador
    if ($d.UninstallString -match '"?([A-Za-z]:\\[^"]+?\.exe)') {
        $dir = Split-Path $Matches[1] -Parent
        if ((Test-Path $dir) -and ($dir -like "$env:ProgramFiles*" -or $dir -like "${env:ProgramFiles(x86)}*" -or $dir -like "$env:LOCALAPPDATA*")) {
            $pts = if ((ConvertTo-Clave (Split-Path $dir -Leaf)) -like "*$kNombre*" -or $kNombre -like "*$(ConvertTo-Clave (Split-Path $dir -Leaf))*") { 85 } else { 55 }
            & $add 'Carpeta' $dir $pts 'Carpeta del desinstalador'
        }
    }
    # 3. Local, Roaming, LocalLow, ProgramData y carpetas de instalación.
    # Dos niveles: incluye Editor\App incluso si el editor no figura en el registro.
    # Nunca se sigue un junction. Las coincidencias vagas y carpetas de editor requieren selección manual.
    $raices = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:APPDATA, $env:LOCALAPPDATA, "$env:USERPROFILE\AppData\LocalLow", "$env:LOCALAPPDATA\Programs") | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
    foreach ($raiz in $raices) {
        foreach ($c in @(Get-ChildItem -LiteralPath $raiz -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $k = ConvertTo-Clave $c.Name
            if (-not $k) { continue }
            if ($k -eq $kNombre) { & $add 'Carpeta' $c.FullName 85 'Carpeta con el nombre exacto del programa' }
            elseif ($k.Length -ge 5 -and ($kNombre.Contains($k) -or $k.Contains($kNombre))) { & $add 'Carpeta' $c.FullName 35 'Nombre parecido; revisar antes de marcar' }
            if ($kEditor -and $k -eq $kEditor -and -not $editorCompartido) { & $add 'Carpeta' $c.FullName 45 'Carpeta del editor; puede contener datos compartidos' }
            foreach ($h in @(Get-ChildItem -LiteralPath $c.FullName -Directory -Force -ErrorAction SilentlyContinue)) {
                if ($h.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                $kh = ConvertTo-Clave $h.Name
                if ($kh -eq $kNombre) { & $add 'Carpeta' $h.FullName 85 'Subcarpeta con el nombre exacto del programa' }
                elseif ($kh.Length -ge 5 -and ($kh.Contains($kNombre) -or $kNombre.Contains($kh))) { & $add 'Carpeta' $h.FullName 35 'Subcarpeta con nombre parecido; revisar' }
            }
        }
    }
    # 4. Accesos directos
    foreach ($raiz in @("$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:APPDATA\Microsoft\Windows\Start Menu\Programs", [Environment]::GetFolderPath('Desktop'), "$env:PUBLIC\Desktop")) {
        Get-ChildItem $raiz -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $k = ConvertTo-Clave $_.BaseName
            if ($k -eq $kNombre -or ($kEditor -and $k -eq $kEditor -and $_.PSIsContainer -and -not $editorCompartido)) { & $add 'Acceso directo' $_.FullName 80 'Menú Inicio / Escritorio' }
            elseif ($k.Length -ge 5 -and $k.Contains($kNombre)) { & $add 'Acceso directo' $_.FullName 40 'Nombre parecido' }
        }
    }
    # 5. Registro
    foreach ($base in @('HKCU:\Software', 'HKLM:\SOFTWARE', 'HKLM:\SOFTWARE\WOW6432Node')) {
        foreach ($c in (Get-ChildItem $base -ErrorAction SilentlyContinue)) {
            $k = ConvertTo-Clave $c.PSChildName
            if ($k -eq $kNombre) { & $add 'Registro' $c.PSPath 80 'Clave con el nombre del programa'; continue }
            if ($kEditor -and $k -eq $kEditor) {
                foreach ($s in (Get-ChildItem $c.PSPath -ErrorAction SilentlyContinue)) { if ((ConvertTo-Clave $s.PSChildName) -eq $kNombre) { & $add 'Registro' $s.PSPath 85 'Editor\Programa' } }
                if (-not $editorCompartido) { & $add 'Registro' $c.PSPath 50 'Clave del editor (sin otros programas suyos)' }
            }
        }
    }
    if ($d.KeyPath -and (Test-Path $d.KeyPath)) { & $add 'Registro' $d.KeyPath 90 'Entrada de desinstalación huérfana' }
    # 6. Servicios y tareas que apuntan a la carpeta de instalación
    $carpetas = @($res | Where-Object { $_.Tipo -eq 'Carpeta' -and $_.Puntuacion -ge 75 } | ForEach-Object { $_.Ruta.ToLowerInvariant() })
    if ($carpetas) {
        Get-CimInstance Win32_Service -OperationTimeoutSec 15 -ErrorAction SilentlyContinue | ForEach-Object {
            $sv = $_; if ($sv.Name -in $Global:ServiciosProtegidos) { return }
            $pn = Resolve-Ejecutable ($sv.PathName + '')
            if ($pn -and ($carpetas | Where-Object { Test-EnRuta $pn.ToLowerInvariant() $_ })) { & $add 'Servicio' $sv.Name 85 "Ejecutable en $($sv.PathName)" }
        }
        Get-ScheduledTask -ErrorAction SilentlyContinue | ForEach-Object {
            $t = $_; if ($t.TaskPath -like '\Microsoft\*') { return }
            $ejecutables = @($t.Actions | ForEach-Object { if ($_.Execute) { Resolve-Ejecutable $_.Execute } })
            $coincide = @($ejecutables | Where-Object { $exe = $_.ToLowerInvariant(); $carpetas | Where-Object { Test-EnRuta $exe $_ } }).Count -gt 0
            if ($coincide) { & $add 'Tarea' ($t.TaskPath + $t.TaskName) 85 'Tarea que ejecuta el programa' }
        }
    }
    return ($res | Sort-Object Puntuacion -Descending)
}

function ConvertTo-RutaReg([string]$psPath) {
    $p = $psPath -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^HKEY_LOCAL_MACHINE', 'HKLM' -replace '^HKEY_CURRENT_USER', 'HKCU'
    return ($p -replace '^HKLM:', 'HKLM' -replace '^HKCU:', 'HKCU')
}

# Elimina restos directamente. Claves de registro: export .reg a %TEMP% y se borra al terminar.
# Carpetas/accesos: a la Papelera si se puede; si no, borrado permanente. Rutas protegidas ya se filtraron en Find-Restos.
function Remove-A-Papelera([string]$Ruta) {
    if (-not ('Microsoft.VisualBasic.FileIO.FileSystem' -as [type])) { Add-Type -AssemblyName Microsoft.VisualBasic }
    if ((Get-Item -LiteralPath $Ruta -Force -ErrorAction Stop).PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Ruta, 'OnlyErrorDialogs', 'SendToRecycleBin')
    } else { [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Ruta, 'OnlyErrorDialogs', 'SendToRecycleBin') }
}
function Remove-Restos {
    param($Restos, [string]$NombreApp)
    $Global:RutasProtegidas = Get-RutasProtegidas
    $otras = @(Get-AppsInstaladas | Where-Object { $_.Nombre -ne $NombreApp })
    $tmp = Join-Path $env:TEMP ('Optimization_restos_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + ($NombreApp -replace '[^\w\-]', '_'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $ok = 0; $err = 0; $i = 0
    foreach ($r in $Restos) {
        $i++; Set-Estado "Eliminando restos ($i/$($Restos.Count)): $($r.Tipo)" ([int](30 + 70 * ($i - 1) / [Math]::Max(1, $Restos.Count)))
        try {
            switch ($r.Tipo) {
                { $_ -in 'Carpeta','Acceso directo' } {
                    if (-not (Test-Path -LiteralPath $r.Ruta)) { Write-Log "  Ya no existía: $($r.Ruta)" 'AVISO'; continue }
                    if (Test-Protegida $r.Ruta $otras) { throw 'Ruta protegida o compartida: no se elimina.' }
                    # Evitar que Remove-Item siga enlaces de un árbol preparado después del escaneo.
                    $raizItem = Get-Item -LiteralPath $r.Ruta -Force -ErrorAction Stop
                    if ($raizItem.PSIsContainer) {
                        $enlaces = @(Get-ChildItem -LiteralPath $r.Ruta -Force -Recurse -ErrorAction Stop | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
                        if ($enlaces.Count) { throw 'La carpeta contiene enlaces/junctions. No se borra automáticamente por seguridad.' }
                    }
                    $papelera = $false
                    try {
                        Remove-A-Papelera $r.Ruta
                        $papelera = $true
                    } catch {
                        Write-Log "  Papelera no disponible: $($_.Exception.Message). Se intentará borrar la carpeta completa." 'AVISO'
                    }
                    # DeleteDirectory puede no haber retirado la raíz. No basta con vaciarla.
                    if (Test-Path -LiteralPath $r.Ruta) {
                        if (Test-Protegida $r.Ruta $otras) { throw 'La ruta ya no es segura.' }
                        Remove-Item -LiteralPath $r.Ruta -Recurse -Force -ErrorAction Stop
                        $papelera = $false
                    }
                    if (Test-Path -LiteralPath $r.Ruta) { throw 'La carpeta sigue existiendo; puede estar en uso. Cierra el programa y vuelve a intentarlo.' }
                    Write-Log ("  Eliminado [{0}]: {1}{2}" -f $r.Tipo, $r.Ruta, $(if ($papelera) { ' (Papelera)' } else { '' })) 'OK'
                }
                'Registro' {
                    if (Test-Protegida $r.Ruta $otras) { throw 'Clave protegida: no se elimina.' }
                    $rr = ConvertTo-RutaReg $r.Ruta; $f = Join-Path $tmp ("reg_$i.reg")
                    & reg.exe export $rr $f /y | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "No se pudo exportar $rr; no se borra." }
                    Remove-Item -LiteralPath $r.Ruta -Recurse -Force -ErrorAction Stop
                    Write-Log "  Eliminado [Registro]: $($r.Ruta) (copia .reg temporal)" 'OK'
                }
                'Servicio' {
                    if ($r.Ruta -in $Global:ServiciosProtegidos) { throw 'Servicio crítico protegido.' }
                    $f = Join-Path $tmp ("servicio_$i.reg")
                    & reg.exe export "HKLM\SYSTEM\CurrentControlSet\Services\$($r.Ruta)" $f /y | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw 'No se pudo exportar el servicio; no se borra.' }
                    Stop-Service -Name $r.Ruta -Force -ErrorAction SilentlyContinue
                    & sc.exe delete $r.Ruta | Out-Null
                    if ($LASTEXITCODE -ne 0) { throw "Windows no pudo eliminar el servicio (código $LASTEXITCODE)." }
                    Write-Log "  Eliminado [Servicio]: $($r.Ruta)" 'OK'
                }
                'Tarea' {
                    if ($r.Ruta -like '\Microsoft\*') { throw 'Tarea de Windows protegida.' }
                    $carpeta = $r.Ruta.Substring(0, $r.Ruta.LastIndexOf('\') + 1); $nom = $r.Ruta.Substring($r.Ruta.LastIndexOf('\') + 1)
                    $f = Join-Path $tmp ("tarea_$i.xml")
                    try { Export-ScheduledTask -TaskPath $carpeta -TaskName $nom | Set-Content -Path $f -Encoding Unicode } catch {}
                    Unregister-ScheduledTask -TaskPath $carpeta -TaskName $nom -Confirm:$false
                    Write-Log "  Eliminado [Tarea]: $($r.Ruta)" 'OK'
                }
                default { throw "Tipo desconocido: $($r.Tipo)" }
            }
            $ok++
        } catch { Write-Log "  No se pudo eliminar [$($r.Tipo)] $($r.Ruta): $($_.Exception.Message)" 'ERROR'; $err++ }
        Update-UI
    }
    try { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue } catch {}
    Write-Log "Restos: $ok eliminados, $err con error." 'OK'
    Set-Estado "Restos eliminados: $ok correctos, $err con error." 100
    return "RESTOS|$ok|$err"
}

# ---- Programas de inicio (v2: con detección de huérfanas) ----
function Resolve-Ejecutable([string]$Comando) {
    if (-not $Comando -or -not $Comando.Trim()) { return $null }
    try {
    $c = [Environment]::ExpandEnvironmentVariables($Comando.Trim())
    if ($c -match '^"([^"]+)"') { $p = $Matches[1] }
    elseif ($c -match '^(.+?\.(exe|com|bat|cmd|vbs|js|ps1|lnk|scr))(\s|$)') { $p = $Matches[1] }
    else { $p = ($c -split '\s+')[0] }
    if ($p -notmatch '\\') {
        $g = if ($p) { Get-Command -Name $p -CommandType Application } else { $null } -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($g) { return $g.Source }
        foreach ($d in "$env:windir\System32", $env:windir) { if (Test-Path -LiteralPath (Join-Path $d $p)) { return (Join-Path $d $p) } }
    }
    return $p
    } catch { return $null }
}

function Test-Ejecutable([string]$Ruta) {
    if (-not $Ruta) { return $true }              # sin ruta reconocible: no se marca como huérfana
    if ($Ruta -notmatch '^[A-Za-z]:\\') { return $true }
    try { return (Test-Path -LiteralPath $Ruta -ErrorAction Stop) } catch { return $true }
}

function New-FilaInicio($Nombre, $Comando, $Origen, $Datos, [bool]$Desactivado) {
    $exe = Resolve-Ejecutable $Comando
    $f = New-Object FilaOpt
    $f.Nombre = $Nombre; $f.Ruta = $Comando; $f.Tipo = $Origen; $f.Detalle = $exe
    $Datos.Exe = $exe
    $f.Datos = $Datos
    $f.Confianza = if (-not (Test-Ejecutable $exe)) { 'Huérfana' } elseif ($Desactivado) { 'Desactivado' } else { 'Activado' }
    return $f
}

function Get-EstadoAprobado($ClaveAprob, $Nombre) {
    $v = (Get-ItemProperty $ClaveAprob -Name $Nombre -ErrorAction SilentlyContinue).$Nombre
    return ($v -and ($v[0] % 2) -eq 1)
}

function Get-ProgramasInicio {
    $res = New-Object System.Collections.Generic.List[FilaOpt]
    $cv = 'Software\Microsoft\Windows\CurrentVersion'
    $fuentes = @(
        @{ Run = "HKCU:\$cv\Run";      Aprob = "HKCU:\$cv\Explorer\StartupApproved\Run";   Origen = 'Run (usuario)' },
        @{ Run = "HKCU:\$cv\RunOnce";  Aprob = $null;                                       Origen = 'RunOnce (usuario)' },
        @{ Run = "HKLM:\$cv\Run";      Aprob = "HKLM:\$cv\Explorer\StartupApproved\Run";   Origen = 'Run (equipo)' },
        @{ Run = "HKLM:\$cv\RunOnce";  Aprob = $null;                                       Origen = 'RunOnce (equipo)' },
        @{ Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run";     Aprob = "HKLM:\$cv\Explorer\StartupApproved\Run32"; Origen = 'Run (32 bits)' },
        @{ Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"; Aprob = $null; Origen = 'RunOnce (32 bits)' })
    $nombresRun = @{}
    foreach ($f in $fuentes) {
        $props = Get-ItemProperty $f.Run -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            if ($f.Aprob) { $nombresRun["$($f.Aprob)|$($p.Name)"] = 1 }
            $des = if ($f.Aprob) { Get-EstadoAprobado $f.Aprob $p.Name } else { $false }
            try { $res.Add((New-FilaInicio $p.Name ([string]$p.Value) $f.Origen @{ Clase = 'Run'; Clave = $f.Run; Valor = $p.Name; Aprob = $f.Aprob } $des)) } catch { Write-Log "  Inicio: entrada ignorada por error: $($_.Exception.Message)" 'AVISO' }
        }
    }
    Send-Parcial $res.ToArray()
    # Carpetas Inicio
    try { $shell = New-Object -ComObject WScript.Shell } catch { $shell = $null }
    $carpetas = @(
        @{ Dir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Aprob = "HKCU:\$cv\Explorer\StartupApproved\StartupFolder"; Origen = 'Carpeta Inicio (usuario)' },
        @{ Dir = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; Aprob = "HKLM:\$cv\Explorer\StartupApproved\StartupFolder"; Origen = 'Carpeta Inicio (todos)' })
    foreach ($c in $carpetas) {
        foreach ($a in (Get-ChildItem $c.Dir -File -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini')) {
            $nombresRun["$($c.Aprob)|$($a.Name)"] = 1
            $cmd = if ($a.Extension -eq '.lnk' -and $shell) { $t = try { $shell.CreateShortcut($a.FullName).TargetPath } catch { '' }; if ($t) { "`"$t`"" } else { '' } } else { "`"$($a.FullName)`"" }
            try { $res.Add((New-FilaInicio $a.BaseName $cmd $c.Origen @{ Clase = 'Carpeta'; Archivo = $a.FullName; Aprob = $c.Aprob; Valor = $a.Name } (Get-EstadoAprobado $c.Aprob $a.Name))) } catch { Write-Log "  Inicio: entrada ignorada por error: $($_.Exception.Message)" 'AVISO' }
        }
    }
    Send-Parcial $res.ToArray()
    # Tareas programadas que arrancan al iniciar sesión o con el sistema (no de Microsoft)
    try { $tareas = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' }) } catch { $tareas = @(); Write-Log "  Inicio: no se pudieron leer las tareas programadas: $($_.Exception.Message)" 'AVISO' }
    $tareas | ForEach-Object {
        $t = $_
      try {
        $arranque = @($t.Triggers) | Where-Object { $_ -and $_.CimClass -and $_.CimClass.CimClassName -in 'MSFT_TaskLogonTrigger','MSFT_TaskBootTrigger' }
        if (-not $arranque) { return }
        $acc = $t.Actions | Where-Object { $_.Execute } | Select-Object -First 1
        if (-not $acc) { return }
        $cmd = "`"$($acc.Execute.Trim('"'))`" $($acc.Arguments)"
        try { $res.Add((New-FilaInicio $t.TaskName $cmd 'Tarea programada' @{ Clase = 'Tarea'; TaskPath = $t.TaskPath; TaskName = $t.TaskName } ($t.State -eq 'Disabled'))) } catch { Write-Log "  Inicio: entrada ignorada por error: $($_.Exception.Message)" 'AVISO' }
      } catch { Write-Log "  Inicio: tarea '$($t.TaskName)' ignorada: $($_.Exception.Message)" 'AVISO' }
    }
    # Valores StartupApproved sin entrada real (restos de programas desinstalados)
    foreach ($ap in @("HKCU:\$cv\Explorer\StartupApproved\Run", "HKLM:\$cv\Explorer\StartupApproved\Run", "HKLM:\$cv\Explorer\StartupApproved\Run32",
                      "HKCU:\$cv\Explorer\StartupApproved\StartupFolder", "HKLM:\$cv\Explorer\StartupApproved\StartupFolder")) {
        $props = Get-ItemProperty $ap -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        foreach ($p in ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
            if ($nombresRun.ContainsKey("$ap|$($p.Name)")) { continue }
            $f = New-Object FilaOpt
            $f.Nombre = $p.Name; $f.Tipo = 'StartupApproved'; $f.Ruta = '(sin entrada de inicio: resto de un programa desinstalado)'; $f.Confianza = 'Huérfana'
            $f.Datos = @{ Clase = 'Aprobado'; Clave = $ap; Valor = $p.Name; Exe = $null }
            $res.Add($f)
        }
    }
    Write-Log "Inicio: $($res.Count) entradas leídas."
    return ($res | Sort-Object -Property @{ Expression = { $_.Confianza -ne 'Huérfana' } }, @{ Expression = { $_.Nombre } })
}

function Set-ProgramaInicio($Fila, [bool]$Activar) {
    $d = $Fila.Datos
    switch ($d.Clase) {
        'Tarea' { if ($Activar) { Enable-ScheduledTask -TaskPath $d.TaskPath -TaskName $d.TaskName | Out-Null } else { Disable-ScheduledTask -TaskPath $d.TaskPath -TaskName $d.TaskName | Out-Null } }
        { $_ -in 'Run','Carpeta' } {
            if (-not $d.Aprob) { Write-Log "  $($Fila.Nombre): las entradas RunOnce no se pueden desactivar, solo eliminar." 'AVISO'; return }
            $valor = [byte[]](@($(if ($Activar) { 0x02 } else { 0x03 })) + (@(0) * 11))
            Set-Reg $d.Aprob $d.Valor $valor 'Binary'
        }
        default { Write-Log "  $($Fila.Nombre): no se puede activar/desactivar (es huérfana)." 'AVISO'; return }
    }
    Write-Log "  Inicio: $($Fila.Nombre) -> $(if($Activar){'activado'}else{'desactivado'})" 'OK'
}

function New-DirCopiaInicio {
    $dir = Join-Path (Get-DirectorioCopias) ("CopiasInicio\" + (Get-Date -Format 'yyyyMMdd_HHmmssfff'))
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return $dir
}

function Remove-EntradaInicio($Fila, [string]$DirCopia) {
    $d = $Fila.Datos
    $n = ($Fila.Nombre -replace '[^\w\-]', '_') + '_' + (Get-Random -Maximum 99999)
    switch ($d.Clase) {
        'Run' {
            & reg.exe export (ConvertTo-RutaReg $d.Clave) (Join-Path $DirCopia "$n.reg") /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "No se pudo exportar $($d.Clave); no se borra." }
            Remove-ItemProperty -Path $d.Clave -Name $d.Valor -Force -ErrorAction Stop
            if ($d.Aprob) { Remove-ItemProperty -Path $d.Aprob -Name $d.Valor -Force -ErrorAction SilentlyContinue }
        }
        'Carpeta' {
            Copy-Item -LiteralPath $d.Archivo -Destination $DirCopia -Force
            Remove-Item -LiteralPath $d.Archivo -Force -ErrorAction Stop
            Remove-ItemProperty -Path $d.Aprob -Name $d.Valor -Force -ErrorAction SilentlyContinue
        }
        'Tarea' {
            Export-ScheduledTask -TaskPath $d.TaskPath -TaskName $d.TaskName | Set-Content (Join-Path $DirCopia "$n.xml") -Encoding Unicode
            Unregister-ScheduledTask -TaskPath $d.TaskPath -TaskName $d.TaskName -Confirm:$false -ErrorAction Stop
        }
        'Aprobado' {
            & reg.exe export (ConvertTo-RutaReg $d.Clave) (Join-Path $DirCopia "$n.reg") /y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "No se pudo exportar $($d.Clave); no se borra." }
            Remove-ItemProperty -Path $d.Clave -Name $d.Valor -Force -ErrorAction Stop
        }
    }
    Write-Log "  Entrada de inicio eliminada: [$($Fila.Tipo)] $($Fila.Nombre) (copia en $DirCopia)" 'OK'
}

function Find-AppDeEntrada($Fila, $Apps) {
    $exe = $Fila.Detalle
    if ($exe -and $exe -match '^[A-Za-z]:\\') {
        $e = $exe.ToLowerInvariant()
        $m = $Apps | Where-Object { $_.Datos.InstallLocation -and $e.StartsWith($_.Datos.InstallLocation.TrimEnd('\').ToLowerInvariant() + '\') } | Select-Object -First 1
        if ($m) { return $m }
        $carpeta = ConvertTo-Clave (Split-Path (Split-Path $exe -Parent) -Leaf)
        if ($carpeta.Length -ge 4) { $m = $Apps | Where-Object { (ConvertTo-Clave $_.Nombre) -eq $carpeta } | Select-Object -First 1; if ($m) { return $m } }
    }
    $k = ConvertTo-Clave $Fila.Nombre
    if ($k.Length -ge 4) {
        $m = $Apps | Where-Object { $ka = ConvertTo-Clave $_.Nombre; $ka -eq $k -or ($ka.Length -ge 4 -and ($ka.StartsWith($k) -or $k.StartsWith($ka))) } | Select-Object -First 1
        if ($m) { return $m }
    }
    return $null
}
