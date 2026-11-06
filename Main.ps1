#Requires -Version 5.1
<#
  OptimiZation para Windows 10/11 · Versión 2 - interfaz WPF en castellano.
  Código propio (licencia de uso no comercial, ver LICENSE). Ideas de WinUtil (MIT), Win11Debloat (MIT), Bulk Crap Uninstaller (Apache-2.0)
  e inspiración visual de Optimizer (hellzerg). No contiene código GPL.
#>
$ErrorActionPreference = 'Continue'
$Global:Raiz = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms, PresentationCore, WindowsBase
if (-not ('FilaOpt' -as [type])) {
Add-Type -TypeDefinition @"
public class FilaOpt {
    public bool Seleccionado { get; set; }
    public string Nombre { get; set; }
    public string Detalle { get; set; }
    public string Confianza { get; set; }
    public int Puntuacion { get; set; }
    public string Tipo { get; set; }
    public string Ruta { get; set; }
    public object Datos { get; set; }
}
"@
}

$Global:IdSesion = if ($env:OW_SESSION_ID) { $env:OW_SESSION_ID } else { 'sesion-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) }
$Global:DirectorioCopias = Join-Path ([Environment]::GetFolderPath('MyDocuments')) ('Optimization\' + $Global:IdSesion)
$env:OW_BACKUP_DIR = $Global:DirectorioCopias
New-Item -ItemType Directory -Path $Global:DirectorioCopias -Force | Out-Null
$Global:RutaLog = Join-Path $Global:DirectorioCopias 'actividad.log'
$Global:ArchivoCierre = if ($env:OW_CLOSE_REQUEST) { $env:OW_CLOSE_REQUEST } else { Join-Path $Global:DirectorioCopias 'limpiar.confirmado' }
. (Join-Path $Global:Raiz 'Engine.ps1')
. (Join-Path $Global:Raiz 'Actions.ps1')
$Global:Catalogo = Get-Content (Join-Path $Global:Raiz 'tweaks.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$build = [Environment]::OSVersion.Version.Build
$Global:Version = if ($build -ge 22000) { 'Win11' } else { 'Win10' }

. (Join-Path $Global:Raiz 'WindowIdentity.ps1')

# ===================== Ventana =====================
[xml]$xaml = Get-Content (Join-Path $Global:Raiz 'MainWindow.xaml') -Raw -Encoding UTF8
$Global:Ventana = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$Global:ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1 -ExpandProperty Value
    $Global:ui[$n] = $Global:Ventana.FindName($n)
}
$Global:Ventana.Add_SourceInitialized({
    $h = [Windows.Interop.WindowInteropHelper]::new($Global:Ventana).Handle
    [OWWindowIdentity]::ApplyAppearance($h)
    try { [OWWindowIdentity]::Apply($h, (Join-Path $Global:Raiz 'logo.ico'), $env:OW_LAUNCHER_PATH) }
    catch { Write-Log "No se pudo completar la identidad de la barra de tareas: $($_.Exception.Message)" 'AVISO' }
})
$Global:Ventana.Add_Closed({ [OWWindowIdentity]::Release() })
$ui = $Global:ui
# WindowChrome gestiona arrastrar/doble clic/ajustar y los bordes; solo dibujamos sus botones.
$ui.BtnMinimizar.Add_Click({ [Windows.SystemCommands]::MinimizeWindow($Global:Ventana) })
$ui.BtnMaximizar.Add_Click({ if($Global:Ventana.WindowState -eq 'Maximized'){[Windows.SystemCommands]::RestoreWindow($Global:Ventana)}else{[Windows.SystemCommands]::MaximizeWindow($Global:Ventana)} })
$ui.BtnCerrarVentana.Add_Click({ $Global:Ventana.Close() }) # Misma confirmación y limpieza que Salir/Alt+F4.
$Global:Ventana.Add_StateChanged({
    $max=$Global:Ventana.WindowState -eq 'Maximized'
    $ui.BtnMaximizar.Content=if($max){[string][char]0xE923}else{[string][char]0xE922}
    $ui.BtnMaximizar.ToolTip=if($max){'Restaurar'}else{'Maximizar'}
    $ui.BtnMaximizar.SetValue([Windows.Automation.AutomationProperties]::NameProperty,[string]$ui.BtnMaximizar.ToolTip)
})
$Global:TxtLog = $ui.TxtLog
$ui.TxtSistema.Text = "$(if($Global:Version -eq 'Win11'){'Windows 11'}else{'Windows 10'})`n$build"
try {
    $rutaLogo = Join-Path $Global:Raiz 'logo.png'; $rutaIco = Join-Path $Global:Raiz 'logo.ico'
    # Se leen los bytes a memoria (OnLoad): el archivo no queda abierto ni bloqueado.
    if (Test-Path $rutaLogo) {
        $ms = New-Object System.IO.MemoryStream(,[System.IO.File]::ReadAllBytes($rutaLogo))
        $bmp = New-Object System.Windows.Media.Imaging.BitmapImage
        $bmp.BeginInit(); $bmp.CacheOption = 'OnLoad'; $bmp.StreamSource = $ms; $bmp.EndInit(); $bmp.Freeze(); $ms.Dispose()
        $ui.ImgLogo.Source = $bmp; $ui.ImgLogoTitulo.Source = $bmp
    }
    if (Test-Path $rutaIco) {
        $ms = New-Object System.IO.MemoryStream(,[System.IO.File]::ReadAllBytes($rutaIco))
        $ico = [System.Windows.Media.Imaging.BitmapFrame]::Create($ms, [System.Windows.Media.Imaging.BitmapCreateOptions]::None, [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad)
        $ico.Freeze(); $ms.Dispose(); $Global:Ventana.Icon = $ico
    }
} catch { Write-Log "No se pudo cargar el logo: $($_.Exception.Message)" 'AVISO' }

$Global:Conv = New-Object System.Windows.Media.BrushConverter
$Global:Pinceles = @{}
function Get-Pincel([string]$c) {
    if(-not $Global:Pinceles.ContainsKey($c)){
        $p=$Global:Conv.ConvertFromString($c)
        if($p.CanFreeze){$p.Freeze()}
        $Global:Pinceles[$c]=$p
    }
    return $Global:Pinceles[$c]
}
function New-Texto($t, $tam = 13, $color = '#E8EAED', [switch]$Negrita) {
    $x = New-Object System.Windows.Controls.TextBlock
    $x.Text = $t; $x.FontSize = $tam; $x.Foreground = Get-Pincel $color; $x.TextWrapping = 'Wrap'
    if ($Negrita) { $x.FontWeight = 'SemiBold' }
    return $x
}
function New-Tarjeta($borde = '#202734') {
    $c = New-Object System.Windows.Controls.Border
    $c.Background = Get-Pincel '#121722'; $c.CornerRadius = '8'; $c.Padding = '14,10'; $c.Margin = '0,0,0,8'
    $c.BorderBrush = Get-Pincel $borde; $c.BorderThickness = '1'
    return $c
}

# ===================== Avisos y confirmación flotante (misma tarjeta que Salir) =====================
$Global:RelojBanner = New-Object System.Windows.Threading.DispatcherTimer
$Global:RelojBanner.Interval = [TimeSpan]::FromSeconds(3.5)
$Global:RelojBanner.Add_Tick({ $ui.Banner.Visibility = 'Collapsed'; $Global:RelojBanner.Stop() })
function Show-Banner([string]$Texto, [ValidateSet('info','ok','aviso','error')][string]$Tipo = 'info') {
    $col = @{ info = '#E61F3A5F'; ok = '#E61E4620'; aviso = '#E65A3B12'; error = '#E65C1F22' }
    $ico = @{ info = 'ℹ  '; ok = '✔  '; aviso = '⚠  '; error = '✖  ' }
    $ui.TxtBanner.Text = $ico[$Tipo] + $Texto; $ui.Banner.Background = Get-Pincel $col[$Tipo]; $ui.Banner.Visibility = 'Visible'
    $Global:RelojBanner.Stop(); if ($Tipo -in 'info','ok') { $Global:RelojBanner.Start() }
}
$ui.BtnCerrarBanner.Add_Click({ $ui.Banner.Visibility = 'Collapsed' })

function Request-Confirmacion {
    param([string]$Titulo, [string]$Texto, [string]$Boton = 'Confirmar', [scriptblock]$Si, [string]$BotonB = '', [scriptblock]$B = $null, [scriptblock]$AlCancelar = $null, [string]$BotonCancelar = 'Cancelar')
    if($ui.BtnCancelar){$ui.BtnCancelar.Content=$BotonCancelar}
    $ui.TxtConfirmarTitulo.Text = $Titulo; $ui.TxtConfirmar.Text = $Texto; $ui.BtnConfirmar.Content = $Boton
    $Global:ConfirmarSi = $Si; $Global:ConfirmarB = $B; $Global:ConfirmarCancelar = $AlCancelar
    if ($BotonB) { $ui.BtnConfirmar2.Content = $BotonB; $ui.BtnConfirmar2.Visibility = 'Visible' } else { $ui.BtnConfirmar2.Visibility = 'Collapsed' }
    $ui.PanelConfirmar.Visibility = 'Visible'
}
function Invoke-RespuestaConfirmacion([ValidateSet('Si','B','Cancelar')][string]$Respuesta) {
    $ui.PanelConfirmar.Visibility='Collapsed'
    $accion=switch($Respuesta){'Si'{$Global:ConfirmarSi};'B'{$Global:ConfirmarB};'Cancelar'{$Global:ConfirmarCancelar}}
    # Limpiar ANTES del callback: este puede abrir otra confirmación (p. ej. guardar registro).
    $Global:ConfirmarSi=$null;$Global:ConfirmarB=$null;$Global:ConfirmarCancelar=$null
    if($accion){& $accion}elseif($Respuesta -eq 'Cancelar'){Show-Banner 'Operación cancelada.' 'info'}
}
$ui.BtnCancelar.Add_Click({Invoke-RespuestaConfirmacion 'Cancelar'})
$ui.BtnConfirmar.Add_Click({Invoke-RespuestaConfirmacion 'Si'})
$ui.BtnConfirmar2.Add_Click({Invoke-RespuestaConfirmacion 'B'})

# ===================== Tareas en segundo plano (carriles independientes) =====================
# Cada carril tiene su propio runspace y su propia cola: 'principal' (aplicar, desinstalar...),
# 'deteccion' (estado de los ajustes), 'host' (componentes) e 'inicio' (programas de inicio).
# Así Host e Inicio nunca esperan a la detección, y la detección nunca bloquea «Aplicar cambios».
$Global:Sync = [hashtable]::Synchronized(@{ Cola = New-Object 'System.Collections.Concurrent.ConcurrentQueue[string]'; Estado = ''; Progreso = 0 })
$Global:Carriles = 'principal','deteccion','inicio','host','copias'
$Global:Tareas = @{}
$Global:Colas = @{}
foreach ($k in $Global:Carriles) { $Global:Colas[$k] = New-Object System.Collections.Queue }
$Global:BotonesBloqueables = 'BtnBoostExplorer','BtnBoostTemporales','BtnBoostDns','BtnEliminarPuntos','BtnActualizarPuntos','BtnBoostLimpiar','BtnDesinstalar','BtnSoloRestos',
    'BtnEliminarRastros','BtnInicioDesinstalar','BtnInicioHuerfanas','BtnInicioDesactivar','BtnInicioActivar','BtnCrearPunto','BtnExportarCopias','BtnUsarRestauracion'
$Global:NPendientes = 0
function Update-BotonAplicar { $ui.BtnEjecutar.IsEnabled = ($Global:NPendientes -gt 0 -and -not $Global:Tareas['principal']) }
function Set-Ocupado([bool]$Si) {
    foreach($b in $Global:BotonesBloqueables){if($ui[$b]){$ui[$b].IsEnabled=-not $Si}}
    Update-BotonAplicar
}

function Start-Tarea {
    param([scriptblock]$Codigo, [hashtable]$Parametros = @{}, [scriptblock]$AlTerminar = {}, [string]$Nombre = 'tarea', [int]$MaxSegundos = 0,
          [string]$Carril = 'principal', [scriptblock]$AlParcial = $null, [switch]$EsAplicacion)
    if($EsAplicacion -and $Carril -ne 'principal'){throw 'Aplicar cambios solo puede usar el carril principal.'}
    $t = $Global:Tareas[$Carril]; $cola = $Global:Colas[$Carril]
    if ($Carril -eq 'principal' -and $t) { Show-Banner 'Espera a que termine la operación actual antes de iniciar otra.' 'aviso'; return }
    if ($t -and $t.Nombre -eq $Nombre) { Write-Log "'$Nombre' ya está en marcha; se ignora la repetición."; return }
    foreach ($q in $cola.ToArray()) { if ($q.Nombre -eq $Nombre) { Write-Log "'$Nombre' ya está en cola; se ignora la repetición."; return } }
    if ($t) {
        $cola.Enqueue(@{ Codigo = $Codigo; Parametros = $Parametros; AlTerminar = $AlTerminar; Nombre = $Nombre; MaxSegundos = $MaxSegundos; AlParcial = $AlParcial })
        Write-Log ("En cola: {0} (esperando a '{1}', en marcha desde hace {2:N0} s)." -f $Nombre, $t.Nombre, ((Get-Date) - $t.Inicio).TotalSeconds)
        return
    }
    if($EsAplicacion){Start-RegistroAplicacion}
    Write-Log "Iniciando tarea: $Nombre [$Carril]"
    $sync = [hashtable]::Synchronized(@{ Cola = $Global:Sync.Cola; Estado = 'Trabajando...'; Progreso = 0; MostrarRegistro = [bool]$EsAplicacion; Parciales = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]' })
    $rs = [runspacefactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'; $rs.ThreadOptions = 'ReuseThread'; $rs.Open()
    foreach ($v in 'Catalogo','RutaLog','Raiz','Version','DirectorioCopias') { $rs.SessionStateProxy.SetVariable($v, (Get-Variable -Name $v -Scope Global -ValueOnly)) }
    $rs.SessionStateProxy.SetVariable('Sync', $sync)
    $rs.SessionStateProxy.SetVariable('EnSegundoPlano', $true)
    $ps = [powershell]::Create(); $ps.Runspace = $rs
    # Un único script (sin AddStatement: las invocaciones por lotes pueden quedarse colgadas en BeginInvoke)
    $rs.SessionStateProxy.SetVariable('CodigoTarea', $Codigo.ToString())
    $rs.SessionStateProxy.SetVariable('ParametrosTarea', $Parametros)
    $rs.SessionStateProxy.SetVariable('NombreTarea', $Nombre)
    [void]$ps.AddScript(". (Join-Path `$Raiz 'Engine.ps1'); . (Join-Path `$Raiz 'Actions.ps1'); if(`$NombreTarea -ne 'métricas de Inicio'){Write-Log ""  [`$NombreTarea] hilo de trabajo listo.""}`n`$p = `$ParametrosTarea; & ([scriptblock]::Create(`$CodigoTarea)) @p", $false)
    $Global:Tareas[$Carril] = @{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke(); AlTerminar = $AlTerminar; AlParcial = $AlParcial; Nombre = $Nombre
                                 Inicio = (Get-Date); MaxSegundos = $MaxSegundos; Sync = $sync; Carril = $Carril; EsAplicacion = [bool]$EsAplicacion }
    if ($Carril -eq 'principal') { Set-Ocupado $true }
    Update-Actividad
}
function Stop-Carril([string]$Carril, [string]$Motivo = '') {
    $t = $Global:Tareas[$Carril]; if (-not $t) { return }
    $Global:Tareas.Remove($Carril)
    try { [void]$t.PS.BeginStop($null, $null) } catch {}
    Write-Log "Tarea '$($t.Nombre)' detenida. $Motivo" 'AVISO'
    if ($Carril -eq 'principal') { Set-Ocupado $false }
}

function Invoke-TickCarril([string]$Carril) {
    $t = $Global:Tareas[$Carril]; if (-not $t) { return }
    $x = $null
    $lote=0
    while ($lote -lt 32 -and $t.Sync.Parciales.TryDequeue([ref]$x)) {
        $lote++
        if ($t.AlParcial) { try { & $t.AlParcial $x } catch { Write-Log "Error mostrando resultados parciales de '$($t.Nombre)': $($_.Exception.Message)" 'ERROR' } }
    }
    $seg = ((Get-Date) - $t.Inicio).TotalSeconds
    $agotada = ($t.MaxSegundos -gt 0 -and $seg -gt $t.MaxSegundos -and -not $t.Handle.IsCompleted)
    if (-not $t.Handle.IsCompleted -and -not $agotada) { return }
    $Global:Tareas.Remove($Carril)
    $res = @()
    if ($agotada) {
        Write-Log ("Tarea '{0}' sin terminar tras {1:N0} s: se detiene y se sigue con la cola." -f $t.Nombre, $seg) 'ERROR'
        try { [void]$t.PS.BeginStop($null, $null) } catch {}
        $Global:UltimosErrores = 1
    } else {
        $Global:FalloTarea = $false
        try { $res = @($t.PS.EndInvoke($t.Handle) | ForEach-Object { $_ }) }
        catch { Write-Log "Error en '$($t.Nombre)': $($_.Exception.Message)" 'ERROR'; $Global:FalloTarea = $true }
        foreach ($e in $t.PS.Streams.Error) { Write-Log "  [$($t.Nombre)] $($e.Exception.Message) (línea $($e.InvocationInfo.ScriptLineNumber))" 'ERROR' }
        $Global:UltimosErrores = $t.PS.Streams.Error.Count + [int][bool]$Global:FalloTarea
        try { $t.PS.Dispose(); $t.RS.Close(); $t.RS.Dispose() } catch {}
        Write-Log ("Tarea terminada: {0} ({1:N1} s, {2} resultados, {3} errores)" -f $t.Nombre, $seg, $res.Count, $Global:UltimosErrores)
    }
    if ($Carril -eq 'principal') { Set-Ocupado $false }
    if($t.EsAplicacion){Update-Actividad} # Nunca dejar una franja al finalizar, aunque siga detección/Host.
    try { & $t.AlTerminar $res } catch { Write-Log "Error al terminar '$($t.Nombre)': $($_.Exception.Message)" 'ERROR' }
    if($t.EsAplicacion -and -not $Global:EsperandoPunto){Complete-Aplicacion}
    $cola = $Global:Colas[$Carril]
    if (-not $Global:Tareas[$Carril] -and $cola.Count) {
        $s = $cola.Dequeue()
        Start-Tarea -Codigo $s.Codigo -Parametros $s.Parametros -AlTerminar $s.AlTerminar -Nombre $s.Nombre -MaxSegundos $s.MaxSegundos -Carril $Carril -AlParcial $s.AlParcial
    }
}

# Registro en pantalla: las líneas que empiezan por el carácter 1 son «vivas» y sustituyen a la anterior viva.
$Global:VivaInicio = -1
function Add-LineaLog([string]$linea) {
    $tb = $Global:TxtLog
    if ($linea.Length -gt 0 -and $linea[0] -eq [char]1) {
        $texto = $linea.Substring(1) + [Environment]::NewLine
        if ($Global:VivaInicio -ge 0 -and $Global:VivaInicio -le $tb.Text.Length) { $tb.Text = $tb.Text.Substring(0, $Global:VivaInicio) + $texto }
        else { $Global:VivaInicio = $tb.Text.Length; $tb.AppendText($texto) }
    } else {
        $Global:VivaInicio = -1
        $tb.AppendText($linea + [Environment]::NewLine)
    }
}
# Solo Invoke-Plan solicita EsAplicacion. Lectores y acciones de Acelerar no abren esta UI.
$Global:RegistroAplicacionAbierto=$false;$Global:GuardarLogPendiente=$false;$Global:EsperandoPunto=$false
function Update-Actividad {
    $t=$Global:Tareas['principal']
    $ui.PanelActividad.Visibility=if($t -and $t.EsAplicacion){'Visible'}else{'Collapsed'}
}
function Start-RegistroAplicacion {
    if(-not $Global:RegistroAplicacionAbierto){$ui.TxtLog.Clear();$Global:VivaInicio=-1}
    $Global:RegistroAplicacionAbierto=$true;$Global:GuardarLogPendiente=$false
    $ui.ExpRegistro.IsExpanded=$false
}
function Complete-EleccionRegistro {
    $Global:GuardarLogPendiente=$false;$Global:RegistroAplicacionAbierto=$false
    $ui.TxtLog.Clear();$Global:VivaInicio=-1
    $descartada=$null;while($Global:Sync.Cola.TryDequeue([ref]$descartada)){}
    $ui.ExpRegistro.IsExpanded=$false
    Update-Actividad
}
function Show-EleccionRegistro {
    Request-Confirmacion -Titulo 'Aplicación de cambios finalizada' -Texto '¿Quieres guardar el registro de actividad de esta sesión? Cancelar cierra la vista sin guardar.' -Boton 'Guardar registro…' -Si {Save-RegistroActividad} -AlCancelar {Complete-EleccionRegistro}
}
function Complete-Aplicacion {
    Update-Actividad
    if(-not $Global:RegistroAplicacionAbierto -or $Global:GuardarLogPendiente){return}
    $Global:GuardarLogPendiente=$true
    Show-EleccionRegistro # Tarjeta flotante PanelConfirmar, nunca una barra bajo el registro.
}
function Get-RutaRegistroActividad {
    $dialogo=New-Object Microsoft.Win32.SaveFileDialog
    $dialogo.FileName='OptimiZation_registro_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'.txt'
    $dialogo.Filter='Registro de texto|*.txt';$dialogo.Title='Guardar registro de actividad'
    if($dialogo.ShowDialog($Global:Ventana)){return $dialogo.FileName}
    return $null
}
function Save-RegistroActividad {
    try {
        $destino=Get-RutaRegistroActividad
        if(-not $destino){Complete-EleccionRegistro;return} # Cancelar el selector también descarta la vista.
        Copy-Item -LiteralPath $Global:RutaLog -Destination $destino -Force -ErrorAction Stop
        Complete-EleccionRegistro;Show-Banner 'Registro guardado.' 'ok'
    } catch {
        Show-Banner "No se pudo guardar el registro: $($_.Exception.Message)" 'error'
        Show-EleccionRegistro # Permite reintentar o cancelar sin declarar éxito falso.
    }
}
$Global:Reloj = New-Object System.Windows.Threading.DispatcherTimer
$Global:Reloj.Interval = [TimeSpan]::FromMilliseconds(200)
$Global:Reloj.Add_Tick({
  try {
    $linea = $null
    $nLog=0
    while ($nLog -lt 100 -and $Global:Sync.Cola.TryDequeue([ref]$linea)) { Add-LineaLog $linea; $nLog++ }
    if($nLog){
        # El archivo de registro sigue completo; solo se acota el texto visible.
        if($Global:TxtLog.Text.Length -gt 200000){$Global:TxtLog.Text=$Global:TxtLog.Text.Substring($Global:TxtLog.Text.Length-150000);$Global:VivaInicio=-1}
        $Global:TxtLog.ScrollToEnd()
    }
    foreach ($k in $Global:Carriles) { try { Invoke-TickCarril $k } catch { Write-Log "Error interno en el carril ${k}: $($_.Exception.Message)" 'ERROR' } }
    Update-Actividad
    if ($Global:PendientesSucio) { $Global:PendientesSucio = $false; Update-Pendientes }
    if ($Global:MetricasSucio) { $Global:MetricasSucio=$false; Update-Metricas }
    # Progreso compacto EXCLUSIVO del plan; las lecturas tienen sus indicadores por página.
    $mostrar=$Global:Tareas['principal']
    if($mostrar -and -not $mostrar.EsAplicacion){$mostrar=$null}
    if ($mostrar) { $txt = $mostrar.Sync.Estado; $pr = $mostrar.Sync.Progreso } else { $txt = 'Listo.'; $pr = 0 }
    $ui.TxtEstado.Text = $txt; $ui.Progreso.Value = $pr; $ui.TxtPorcentaje.Text = "$([int]$pr) %"; $ui.Progreso.Visibility=if($mostrar){'Visible'}else{'Collapsed'};$ui.TxtPorcentaje.Visibility=$ui.Progreso.Visibility
    $principal = $Global:Tareas['principal']
    $verToast = $principal -and ($principal.Nombre -eq 'crear punto de restauración' -or $principal.Sync.Estado -match '(?i)punto de restauración|protección del sistema')
    $ui.ToastProgreso.Visibility = if ($verToast) { 'Visible' } else { 'Collapsed' }
    if ($verToast) { $ui.TxtToastTitulo.Text = 'Creando punto de restauración'; $ui.TxtToastDetalle.Text = $principal.Sync.Estado; $ui.BarraToast.IsIndeterminate = $true }
    $d = $Global:Tareas['deteccion']
    if ($d) { $ui.TxtDetectando.Text = "⏳ $($d.Sync.Estado)  ($([int]$d.Sync.Progreso) %)"; $ui.ProgresoDeteccion.Value = $d.Sync.Progreso; $ui.ProgresoDeteccion.Visibility = 'Visible' }
    else { $ui.ProgresoDeteccion.Visibility = 'Collapsed' }
  } catch {
    if (-not $Global:ErrorTickAvisado) { Write-Log "Error interno del temporizador: $($_.Exception.Message)" 'ERROR'; $Global:ErrorTickAvisado = $true }
  }
})
$Global:Reloj.Start()

$Global:IconosTrazo=@{
    host='M5,4 L19,4 19,20 5,20 Z M8,13 L10,10 12,15 14,9 16,12'
    optimizar='M4,17 A9,9 0 0 1 20,17 M12,16 L17,9 M5,13 L7,14 M8,8 L9,10 M16,8 L15,10'
    boost='M13,2 L5,13 11,13 10,22 20,9 13,9 Z'
    copias='M4,5 L4,11 10,11 M4,11 A8,8 0 1 1 5,18'
    ajustes='M8,3 L16,3 17,7 21,9 21,15 17,17 16,21 8,21 7,17 3,15 3,9 7,7 Z M16,12 A4,4 0 1 1 8,12 A4,4 0 1 1 16,12'
    inicio='M4,4 L20,4 20,20 4,20 Z M9,8 L16,12 9,16 Z'
    desinstalador='M5,6 L19,6 M9,6 L9,3 15,3 15,6 M7,6 L8,21 16,21 17,6'
    cpu='M6,6 L18,6 18,18 6,18 Z M9,9 L15,9 15,15 9,15 Z M9,2 L9,6 M15,2 L15,6 M9,18 L9,22 M15,18 L15,22 M2,9 L6,9 M18,9 L22,9 M2,15 L6,15 M18,15 L22,15'
    gpu='M3,6 L21,6 21,18 3,18 Z M8,10 A3,3 0 1 1 8,16 A3,3 0 1 1 8,10 M16,10 L19,10 M16,14 L19,14'
    ram='M5,3 L9,3 9,21 5,21 Z M14,3 L18,3 18,21 14,21 Z M5,7 L9,7 M14,7 L18,7'
    discos='M3,8 L21,8 21,16 3,16 Z M6,12 L7,12 M17,12 L18,12'
    volumenes='M3,7 L10,7 12,4 21,4 21,20 3,20 Z'
    sistema='M3,4 L21,4 21,17 3,17 Z M12,17 L12,21 M8,21 L16,21'
    pantalla='M3,4 L21,4 21,17 3,17 Z M12,17 L12,21 M8,21 L16,21'
    placa='M4,3 L20,3 20,21 4,21 Z M8,7 L14,7 14,13 8,13 Z M17,7 L17,17 M8,17 L12,17'
    seguridad='M13,2 L5,13 11,13 10,22 20,9 13,9 Z'
}
function New-Icono([string]$Id,[int]$Tam=20,[string]$Color='#D58A2E') {
    $p=New-Object Windows.Shapes.Path;$p.Width=$Tam;$p.Height=$Tam;$p.Stretch='Uniform';$p.StrokeThickness=1.5;$p.Stroke=Get-Pincel $Color;$p.Data=[Windows.Media.Geometry]::Parse($(if($Global:IconosTrazo[$Id]){$Global:IconosTrazo[$Id]}else{$Global:IconosTrazo['host']}));return $p
}

# ===================== Navegación: siete destinos y el logo como Inicio =====================
$Global:PaginasInfo = [ordered]@{}
function Add-Pagina($id, $nombre, $desc, $elemento, [bool]$Navegable = $true) {
    $Global:PaginasInfo[$id] = @{ Nombre=$nombre; Desc=$desc; Elemento=$elemento }
    if (-not $Navegable) { return }
    $item = New-Object System.Windows.Controls.ListBoxItem
    $sp = New-Object System.Windows.Controls.StackPanel
    $ti=New-Icono $id 20;$ti.HorizontalAlignment='Center'
    $bind=New-Object Windows.Data.Binding 'Foreground';$bind.RelativeSource=[Windows.Data.RelativeSource]::new([Windows.Data.RelativeSourceMode]::FindAncestor,[Windows.Controls.ListBoxItem],1);[void]$ti.SetBinding([Windows.Shapes.Shape]::StrokeProperty,$bind)
    $tn=New-Texto $nombre 10;$tn.TextAlignment='Center';$tn.Margin='0,6,0,0'
    $bt=New-Object Windows.Data.Binding 'Foreground';$bt.RelativeSource=[Windows.Data.RelativeSource]::new([Windows.Data.RelativeSourceMode]::FindAncestor,[Windows.Controls.ListBoxItem],1);[void]$tn.SetBinding([Windows.Controls.TextBlock]::ForegroundProperty,$bt)
    [void]$sp.Children.Add($ti);[void]$sp.Children.Add($tn)
    $item.Content=$sp; $item.Tag=$id; $item.ToolTip=$nombre
    [void]$ui.Nav.Items.Add($item)
}
function Show-Pagina($id) {
    $p=$Global:PaginasInfo[$id]; if (-not $p) { return }
    foreach ($v in $Global:PaginasInfo.Values) { $v.Elemento.Visibility='Collapsed' }
    $Global:PaginaActual=$id
    $p.Elemento.Visibility='Visible';$ui.TxtTitulo.Text=if($id -eq 'optimizar'){'Optimizaciones'}else{$p.Nombre};$ui.TxtDescripcion.Text=$p.Desc
    $ui.TxtTitulo.Visibility=if($id -eq 'resumen'){'Collapsed'}else{'Visible'};$ui.TxtDescripcion.Visibility=if($id -in 'resumen','ajustes','optimizar'){'Collapsed'}else{'Visible'}
    # Salir permanece fijo; Aplicar cambios solo pertenece a los dos modos Manuales.
    $ui.BtnEjecutar.Visibility=if($id -eq 'optimizar' -and $Global:ModoOptimizar -in 'manual-recurrentes','manual-unicas'){'Visible'}else{'Collapsed'}
    $ui.TxtContador.Visibility=$ui.BtnEjecutar.Visibility
    if($id -ne 'optimizar'){$ui.BarraModoOptimizar.Visibility='Collapsed';$ui.BuscadorAjustes.Visibility='Collapsed'}
    if($id -eq 'optimizar'){Show-ModoOptimizar 'elegir'}
    if ($id -eq 'inicio' -and -not $Global:InicioCargado) { Update-Inicio }
    if ($id -eq 'host' -and -not $Global:HostCargado) { Update-Host }
    if ($id -eq 'desinstalador' -and -not $Global:TodasApps.Count) { Update-Apps }
    if ($id -eq 'copias') { Update-Puntos }
}
function Select-Pagina($id) {
    foreach ($it in $ui.Nav.Items) { if ($it.Tag -eq $id) {
        if ($ui.Nav.SelectedItem -eq $it) { Show-Pagina $id } else { $ui.Nav.SelectedItem=$it }; return
    } }
    Show-Pagina $id
}
$Global:Controles=[ordered]@{}; $Global:Cargando=$false
function Get-Plan {
    $plan=@{Aplicar=@(); Revertir=@(); Acciones=@()}
    foreach($c in $Global:Controles.Values){
        if(-not $c.Cb.IsEnabled -or -not $c.Compatible){continue}
        # Una selección del otro modo Manual se conserva, pero nunca se aplica oculta.
        if($Global:ModoOptimizar -in 'manual-recurrentes','manual-unicas' -and $c.Ajuste.tipo -ne (Get-TipoManual)){continue}
        $m=[bool]$c.Cb.IsChecked
        if($c.Ajuste.tipo -eq 'interruptor'){
            if($m -and $c.Estado -ne $true){$plan.Aplicar+= $c.Ajuste}
            elseif(-not $m -and $c.Estado -eq $true -and $c.Tocado){$plan.Revertir+= $c.Ajuste}
        } elseif($m -and $c.Estado -ne $true){$plan.Acciones+= $c.Ajuste}
    }
    # Cambiar a un ajuste excluyente ya sustituye al anterior; no revertirlo después.
    $sustituidos=@($plan.Aplicar | ForEach-Object {$_.excluyeCon})
    $plan.Revertir=@($plan.Revertir | Where-Object {$_.id -notin $sustituidos})
    return $plan
}
function Update-Pendientes {
    foreach($c in $Global:Controles.Values){Update-Insignia $c}
    $p=Get-Plan; $n=$p.Aplicar.Count+$p.Revertir.Count+$p.Acciones.Count
    $Global:NPendientes=$n; Update-BotonAplicar
    $ui.TxtContador.Text=if($n){"$n pendientes · $($p.Aplicar.Count) activar · $($p.Revertir.Count) deshacer · $($p.Acciones.Count) acciones"}else{'Sin cambios pendientes · los ya aplicados no se repiten'}
    $Global:MetricasSucio=$true
    if($Global:FiltroActual -in 'activas','desactivadas'){Update-Chips;Update-FiltroAjustes}
}
# ===================== Presentación: tarjetas compactas, sin cambiar las acciones =====================
function New-Rejilla([string[]]$Columnas, [int]$Filas=0) {
    $g=New-Object Windows.Controls.Grid
    foreach($w in $Columnas){$cd=New-Object Windows.Controls.ColumnDefinition;$cd.Width=[Windows.GridLengthConverter]::new().ConvertFromInvariantString($w);$g.ColumnDefinitions.Add($cd)}
    for($i=0;$i -lt $Filas;$i++){$rd=New-Object Windows.Controls.RowDefinition;$rd.Height=[Windows.GridLength]::Auto;$g.RowDefinitions.Add($rd)}
    return $g
}
function Get-EsRecomendado($a) {
    return ($a.nivel -eq 'Seguro' -and -not $a.fueraDePreset -and $a.id -notin 'pers_claro','red_dns_google')
}
# Objetivos estáticos por perfil: cacheados; nunca vuelven a seleccionar ni ejecutar ajustes.
function Get-ObjetivosPreset([ValidateSet('juegos','alto','recomendadas','maximo')][string]$Id) {
    if(-not $Global:CacheObjetivosPreset -or -not [object]::ReferenceEquals($Global:CacheObjetivosPreset.Catalogo,$Global:Catalogo) -or $Global:CacheObjetivosPreset.Version -ne $Global:Version){
        $Global:CacheObjetivosPreset=@{Catalogo=$Global:Catalogo;Version=$Global:Version;Datos=@{}}
    }
    if(-not $Global:CacheObjetivosPreset.Datos.ContainsKey($Id)){
        $alto=@('rend_alto','rend_efectos','rend_segundo_plano','game_modo','rend_gamedvr','game_gamebar_captura','rend_hags','game_prioridad','game_usb_suspend','game_teclas_especiales','game_teclas_filtro')
        $Global:CacheObjetivosPreset.Datos[$Id]=@($Global:Catalogo.ajustes | Where-Object {
            $a=$_
            $permitido=switch($Id){
                'juegos'{$a.id -in $Global:Catalogo.presetGaming -and $a.nivel -ne 'Agresivo'}
                'alto'{$a.id -in $alto -and $a.nivel -ne 'Agresivo'}
                'recomendadas'{Get-EsRecomendado $a}
                'maximo'{$a.id -notin 'pers_claro','red_dns_google','rend_alto'}
            }
            $permitido -and $a.tipo -eq 'interruptor' -and $a.comprobar -and -not $a.fueraDePreset -and (-not $Global:Version -or $a.compatibilidad -contains $Global:Version)
        })
    }
    return $Global:CacheObjetivosPreset.Datos[$Id]
}
function Get-PresetReferencia {
    $null=Get-ObjetivosPreset 'alto' # invalida el cache si cambió catálogo/Windows
    if($Global:CacheObjetivosPreset.ContainsKey('Referencia')){return $Global:CacheObjetivosPreset.Referencia}
    # Alto gana los empates; con este catálogo Recomendadas tiene más interruptores comprobables (53 en Windows 11).
    $mejor='alto';$cuenta=-1
    foreach($id in 'alto','recomendadas','juegos'){$n=@(Get-ObjetivosPreset $id).Count;if($n -gt $cuenta){$mejor=$id;$cuenta=$n}}
    $Global:CacheObjetivosPreset.Referencia=$mejor
    return $mejor
}
function Get-CoberturaPreset([string[]]$Ids) {
    $activos=0
    foreach($id in $Ids){if($Global:Controles[$id] -and $Global:Controles[$id].Estado -eq $true){$activos++}}
    return [pscustomobject]@{Total=$Ids.Count;Activos=$activos;Proporcion=$(if($Ids.Count){$activos/$Ids.Count}else{0})}
}
function Get-PorcentajeOptimizado {
    $ref=Get-PresetReferencia;$ids=@((Get-ObjetivosPreset $ref).id);$c=Get-CoberturaPreset $ids
    $pct=if($c.Total){[Math]::Min(89,[int][Math]::Round(90*$c.Proporcion))}else{0}
    # La referencia completa también se reconoce si se alcanzó manualmente; no es una promesa de FPS.
    if($c.Total -and $c.Activos -eq $c.Total){$pct=90}
    $ultimo=$Global:UltimoPresetAplicado
    if($ultimo -and $ultimo.Id -in 'juegos','alto','recomendadas','maximo'){
        $permitidos=@((Get-ObjetivosPreset $ultimo.Id).id)
        $objetivos=@($ultimo.Objetivos | Where-Object {$_ -in $permitidos} | Select-Object -Unique)
        $u=Get-CoberturaPreset $objetivos
        # Solo un conjunto sustancial verificado, nunca el simple click en un perfil.
        if($permitidos.Count -and $u.Total -ge [Math]::Ceiling(0.9*$permitidos.Count)){
            if($ultimo.Id -eq $ref -and $u.Activos -eq $u.Total){$pct=90}
            if($ultimo.Id -eq 'maximo' -and $u.Proporcion -ge 0.95){
                $agresivos=@((Get-ObjetivosPreset 'maximo' | Where-Object nivel -eq 'Agresivo').id | Where-Object {$_ -in $objetivos})
                $ag=Get-CoberturaPreset $agresivos
                if($ag.Total -and $ag.Proporcion -ge 0.95){$pct=100}
            }
        }
    }
    return $pct
}
function Get-RutaProgresoPreset {
    return Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Optimization\perfil-aplicado.json'
}
function Read-ProgresoPreset {
    $Global:UltimoPresetAplicado=$null
    try {
        $ruta=Get-RutaProgresoPreset
        if(Test-Path -LiteralPath $ruta){
            $p=Get-Content -LiteralPath $ruta -Raw -Encoding UTF8 | ConvertFrom-Json
            if($p.Id -in 'juegos','alto','recomendadas','maximo'){
                $ids=@((Get-ObjetivosPreset $p.Id).id)
                $Global:UltimoPresetAplicado=@{Id=[string]$p.Id;Objetivos=@($p.Objetivos | Where-Object {$_ -in $ids} | Select-Object -Unique)}
            }
        }
    } catch { $Global:UltimoPresetAplicado=$null }
}
function Complete-PresetAplicado($Preset) {
    if(-not $Preset -or $Preset.Id -notin 'juegos','alto','recomendadas','maximo'){return}
    $Global:UltimoPresetAplicado=@{Id=$Preset.Id;Objetivos=@($Preset.Objetivos)}
    try {
        $ruta=Get-RutaProgresoPreset;$dir=Split-Path $ruta -Parent
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $Global:UltimoPresetAplicado | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ruta -Encoding UTF8
    } catch {Write-Log 'No se pudo guardar la referencia del último perfil; se conserva durante esta sesión.' 'AVISO'}
}
function Get-NombreGrupo([string]$id) {
    return ($Global:Catalogo.gruposVisuales | Where-Object {$_.id -eq $id} | Select-Object -First 1).nombre
}
function Update-Insignia($c) {
    $m=[bool]$c.Cb.IsChecked;$a=$c.Ajuste;$activo=$c.Estado -eq $true
    # No se reasignan textos/pinceles de las otras 128 tarjetas al tocar un interruptor.
    $clave="$m|$($c.Estado)|$($c.Compatible)|$($Global:Detectando)"
    if($c.Presentacion -eq $clave){return};$c.Presentacion=$clave
    $c.Card.Background=Get-Pincel $(if($activo){'#10151E'}else{'#121722'})
    $c.Titulo.Foreground=Get-Pincel $(if($activo){'#929CAA'}else{'#E4E9F0'})
    $c.Descripcion.Foreground=Get-Pincel $(if($activo){'#667284'}else{'#8D98A9'})
    $texto='';$color='#7E8A9B';$etiqueta=if($a.tipo -eq 'interruptor'){'Activar'}else{'Ejecutar'}
    if(-not $c.Compatible){$texto='No disponible en tu Windows';$etiqueta='No disponible'}
    elseif($activo){
        $etiqueta='Activo'
        if($a.tipo -eq 'interruptor' -and -not $m){$texto='Pendiente de deshacer';$color='#FFAD4A';$etiqueta='Deshacer'}
    } elseif($m){$texto='Preparado · pulsa Aplicar cambios';$color='#FFAD4A'}
    elseif($a.comprobar -and $null -eq $c.Estado){$texto=if($Global:Detectando){'Comprobando estado…'}else{'Estado sin comprobar'}}
    elseif(-not $a.comprobar){$texto='Acción puntual · requiere confirmación'}
    $c.Insignia.Child.Text=$texto;$c.Insignia.Child.Foreground=Get-Pincel $color
    $c.Insignia.Visibility=if($texto){'Visible'}else{'Collapsed'}
    $c.Cb.ToolTip="$etiqueta. $texto Prepara la selección; nada se ejecuta hasta confirmar Aplicar cambios. Pulsa ⓘ para conocer el cambio."
    $c.Etiqueta.Text=$etiqueta;$c.Etiqueta.Foreground=Get-Pincel $(if($activo -and $m){'#7FAEFF'}else{'#8D98A9'})
}
function New-TarjetaAjuste($a) {
    # Vista normal: nombre, tres puntos de impacto y selector. Explicaciones solo tras ⓘ.
    $card=New-Tarjeta;$card.Padding='12,12';$card.MinWidth=0;$card.MinHeight=80;$card.CornerRadius='8'
    $g=New-Rejilla @('*') 2
    $top=New-Rejilla @('*','Auto','Auto')
    $nombre=New-Object Windows.Controls.StackPanel;$nombre.Margin='0,0,8,0';$nombre.VerticalAlignment='Center'
    $titulo=New-Texto $a.ui.titulo 13 '#E4E9F0' -Negrita;[void]$nombre.Children.Add($titulo)
    $impact=New-Object Windows.Controls.StackPanel;$impact.Orientation='Horizontal';$impact.Margin='0,6,0,0';$impact.VerticalAlignment='Center'
    $impact.ToolTip='Riesgo / impacto del cambio: Bajo = limitado; Medio = moderado; Alto = agresivo. No mide ganancias de velocidad ni FPS. Pulsa ⓘ para revisar las consecuencias.'
    $num=switch($a.ui.impacto){'Alto'{3};'Medio'{2};default{1}};$color=switch($num){3{'#E28980'};2{'#D9AB62'};default{'#8293A8'}}
    for($i=1;$i -le 3;$i++){$dot=New-Object Windows.Shapes.Ellipse;$dot.Width=4;$dot.Height=4;$dot.VerticalAlignment='Center';$dot.Margin='0,0,3,0';$dot.Fill=Get-Pincel $(if($i -le $num){$color}else{'#344052'});[void]$impact.Children.Add($dot)}
    $it=New-Texto $a.ui.impacto 10 $color;$it.Margin='3,0,0,0';[void]$impact.Children.Add($it);[void]$nombre.Children.Add($impact);[void]$top.Children.Add($nombre)
    $info=New-Object Windows.Controls.Primitives.ToggleButton;$info.Style=$Global:Ventana.FindResource('BotonInfo');$info.VerticalAlignment='Center';$info.Margin='0,0,8,0';[Windows.Controls.Grid]::SetColumn($info,1)
    $info.SetValue([Windows.Automation.AutomationProperties]::NameProperty,"Información de $($a.ui.titulo)")
    $info.ToolTip='Pulsa para ver qué hace, qué toca y cómo deshacerlo.'
    [void]$top.Children.Add($info)
    $cb=New-Object Windows.Controls.CheckBox;$cb.Style=$Global:Ventana.FindResource($(if($a.tipo -eq 'accion'){'Casilla'}else{'Interruptor'}));$cb.Tag=$a.id;$cb.VerticalAlignment='Center';[Windows.Controls.Grid]::SetColumn($cb,2)
    $cb.ToolTip='Prepara el cambio; se aplica solo después de confirmar.';$cb.SetValue([Windows.Automation.AutomationProperties]::NameProperty,$a.ui.titulo)
    $compatible=$a.compatibilidad -contains $Global:Version;$cb.IsEnabled=$compatible
    [void]$top.Children.Add($cb);[void]$g.Children.Add($top)
    $texto="QUÉ HACE`n$($a.ui.hace)`n`nQUÉ TOCA`n$($a.ui.toca)`n`nTEN EN CUENTA`n$($a.riesgos)`n`nCÓMO VOLVER ATRÁS`n$($a.comoDeshacer)`n`nCAMBIO EXACTO`n$($a.aplicar)`n`nID: $($a.id) · $($a.compatibilidad -join ', ')"
    if($a.ui.energia){$texto+="`nPuede consumir más energía."}
    if($a.reiniciaExplorador){$texto+="`nReinicia el Explorador de Windows al aplicar."}
    $det=New-Object Windows.Controls.Border;$det.Background=Get-Pincel '#0C1119';$det.Padding='10';$det.Margin='0,12,0,0';$det.CornerRadius='5';$det.Visibility='Collapsed'
    $detalle=New-Object Windows.Controls.StackPanel
    $label=New-Texto 'Activar' 10 '#8D98A9';[void]$detalle.Children.Add($label)
    $ins=New-Object Windows.Controls.Border;$ins.Margin='0,5,0,8';$ins.Child=New-Texto '' 10 '#7E8A9B';[void]$detalle.Children.Add($ins)
    $desc=New-Texto $texto 11 '#A5B1C2';[void]$detalle.Children.Add($desc)
    $det.Child=$detalle;[Windows.Controls.Grid]::SetRow($det,1);[void]$g.Children.Add($det)
    $info.Tag=$det;$info.Add_Checked({$this.Tag.Visibility='Visible'});$info.Add_Unchecked({$this.Tag.Visibility='Collapsed'})
    $card.Child=$g
    $Global:Controles[$a.id]=@{Ajuste=$a;Cb=$cb;Insignia=$ins;Card=$card;Estado=$null;Tocado=$false;Compatible=$compatible;Titulo=$titulo;Descripcion=$desc;Etiqueta=$label}
    $cb.Add_Checked({if(-not $Global:Cargando){$c=$Global:Controles[$this.Tag];$c.Tocado=$true;$o=$c.Ajuste.excluyeCon;if($o -and $Global:Controles[$o]){$Global:Controles[$o].Cb.IsChecked=$false};Update-Pendientes}})
    $cb.Add_Unchecked({if(-not $Global:Cargando){$Global:Controles[$this.Tag].Tocado=$true;Update-Pendientes}})
    return $card
}
function Update-Metricas {
    $cs=@($Global:Controles.Values | Where-Object {$_.Compatible -and $_.Ajuste.comprobar})
    $act=@($cs | Where-Object {$_.Estado -eq $true}).Count;$des=@($cs | Where-Object {$null -eq $_.Estado}).Count
    $rec=@($Global:Controles.Values | Where-Object {$_.Compatible -and $_.Estado -ne $true -and (Get-EsRecomendado $_.Ajuste)}).Count
    $pct=Get-PorcentajeOptimizado
    $ui.TxtOptimizado.Text=if($Global:Detectando){'…'}else{"$pct %"};$ui.MetricaActivos.Text="$act";$ui.MetricaPendientes.Text="$rec";$ui.MetricaTotal.Text="$($Global:Controles.Count)"
    $ui.TxtHomePendientes.Text="$rec recomendados por revisar · $des estados sin comprobar"
    $claveAnillo="$pct|$($Global:Detectando)"
    if($Global:ClaveAnillo -ne $claveAnillo){
        $Global:ClaveAnillo=$claveAnillo
        if($pct -eq 0 -or $Global:Detectando){$ui.AnilloProgreso.Data=$null}else{
            $ang=2*[Math]::PI*[Math]::Min($pct,99.99)/100;$x=76+64*[Math]::Sin($ang);$y=76-64*[Math]::Cos($ang);$inv=[Globalization.CultureInfo]::InvariantCulture
            $d='M 76,12 A 64,64 0 '+$(if($pct -gt 50){'1'}else{'0'})+' 1 '+$x.ToString('F3',$inv)+','+$y.ToString('F3',$inv)
            $geo=[Windows.Media.Geometry]::Parse($d);$geo.Freeze();$ui.AnilloProgreso.Data=$geo
        }
    }
    if($Global:Chips){Update-Chips}
}
function Update-ResumenGrupos {
    $ui.PanelResumenGrupos.Children.Clear()
    foreach($g in $Global:Catalogo.gruposVisuales){
        $cs=@($Global:Controles.Values | Where-Object {$_.Compatible -and $_.Ajuste.comprobar -and $_.Ajuste.ui.grupo -eq $g.id});$ok=@($cs | Where-Object {$_.Estado -eq $true}).Count
        $b=New-Tarjeta;$b.Width=215;$b.Margin='0,12,12,0';$st=New-Object Windows.Controls.StackPanel;[void]$st.Children.Add((New-Texto $g.nombre 12 '#CAD1DB' -Negrita));[void]$st.Children.Add((New-Texto "$ok de $($cs.Count) comprobables aplicados" 10 '#929CAB'));$b.Child=$st;[void]$ui.PanelResumenGrupos.Children.Add($b)
    };$Global:MetricasSucio=$true
}
$Global:Rejillas=New-Object Collections.ArrayList;$Global:NumColumnas=3;$Global:FiltroActual='';$Global:GrupoActual='';$Global:TipoManual='interruptor';$Global:Chips=[ordered]@{};$Global:BotonesCategorias=[ordered]@{}
# Agrupar por filas mantiene tres/dos/una columnas sin medir toda la lista fuera de pantalla.
function Get-FilasAjustes([object[]]$Tarjetas,[int]$Columnas) {
    if($Columnas -lt 1){throw 'El número de columnas debe ser mayor que cero.'}
    for($i=0;$i -lt $Tarjetas.Count;$i+=$Columnas){
        [pscustomobject]@{Tarjetas=@($Tarjetas[$i..([Math]::Min($i+$Columnas-1,$Tarjetas.Count-1))])}
    }
}
function Get-AnclaAjustes {
    # Solo consulta contenedores YA realizados; no usa UpdateLayout ni mide los 129 ajustes.
    for($i=0;$i -lt $ui.PanelAjustes.Items.Count;$i++){
        $item=$ui.PanelAjustes.Items[$i];if(-not $item.Tag){continue}
        $contenedor=$ui.PanelAjustes.ItemContainerGenerator.ContainerFromIndex($i)
        if($null -eq $contenedor){continue}
        $y=$contenedor.TranslatePoint([Windows.Point]::new(0,0),$ui.PanelAjustes).Y
        if($y+$contenedor.ActualHeight -gt 0){return @{Id=[string]$item.Tag;Y=$y}}
    }
    return $null
}
function Set-Columnas([int]$n,[switch]$Forzar,[bool]$ConservarPosicion=$true) {
    if($n -lt 1 -or $n -gt 3){throw 'Solo se admiten 1, 2 o 3 columnas.'}
    if($n -eq $Global:NumColumnas -and -not $Forzar){return}
    $modelos=New-Object Collections.ArrayList
    foreach($r in $Global:Rejillas){
        $cards=@($r.Tarjetas | Where-Object {$_.Visibility -eq 'Visible'})
        foreach($modelo in @(Get-FilasAjustes $cards $n)){
            [void]$modelos.Add(@{Tarjetas=$modelo.Tarjetas;Grupo=$r;Cambiar=$true})
        }
    }
    # Una notificación repetida de filtros no reconstruye la misma vista.
    $clave="$n|$(@($modelos | ForEach-Object {$_.Tarjetas.Tag -join ','}) -join ';')|$($Global:TextoSinResultados.Visibility)"
    if($Global:ClaveFilasAjustes -eq $clave){return}
    $ancla=if($ConservarPosicion){Get-AnclaAjustes}else{$null}
    $Global:NumColumnas=$n;$Global:RevisionFilas++;$revision=$Global:RevisionFilas
    $ui.PanelAjustes.IsHitTestVisible=$false
    $destino=$null
    try {
        # Reutilizar filas y contenedores: nunca Items.Clear (que reiniciaría la virtualización/scroll).
        if($ui.PanelAjustes.Items.Contains($Global:TextoSinResultados)){[void]$ui.PanelAjustes.Items.Remove($Global:TextoSinResultados)}
        $anteriores=@($ui.PanelAjustes.Items)
        # Desvincular primero todas las filas que cambian: una tarjeta solo admite un padre WPF.
        for($i=0;$i -lt $anteriores.Count;$i++){
            $fila=$anteriores[$i]
            if($i -ge $modelos.Count){$fila.Children.Clear();continue}
            $modelo=$modelos[$i]
            $igual=($fila.ColumnDefinitions.Count -eq $n -and $fila.Children.Count -eq $modelo.Tarjetas.Count)
            if($igual){for($j=0;$j -lt $modelo.Tarjetas.Count;$j++){if(-not [object]::ReferenceEquals($fila.Children[$j],$modelo.Tarjetas[$j])){$igual=$false;break}}}
            $modelo.Cambiar=-not $igual
            if(-not $igual){$fila.Children.Clear()}
        }
        foreach($r in $Global:Rejillas){$r.Filas=@()}
        for($i=0;$i -lt $modelos.Count;$i++){
            $modelo=$modelos[$i]
            $fila=if($i -lt $anteriores.Count){$anteriores[$i]}else{New-Rejilla (@('*')*$n)}
            if($modelo.Cambiar){
                while($fila.ColumnDefinitions.Count -gt $n){$fila.ColumnDefinitions.RemoveAt($fila.ColumnDefinitions.Count-1)}
                while($fila.ColumnDefinitions.Count -lt $n){$col=New-Object Windows.Controls.ColumnDefinition;$col.Width=[Windows.GridLength]::new(1,[Windows.GridUnitType]::Star);[void]$fila.ColumnDefinitions.Add($col)}
                $fila.Tag=[string]$modelo.Tarjetas[0].Tag
                for($j=0;$j -lt $modelo.Tarjetas.Count;$j++){
                    $card=$modelo.Tarjetas[$j];$card.Margin=if($j -lt $n-1){'0,0,12,12'}else{'0,0,0,12'}
                    [Windows.Controls.Grid]::SetColumn($card,$j);[void]$fila.Children.Add($card)
                }
            }
            if($ancla -and $ancla.Id -in @($modelo.Tarjetas.Tag)){$destino=$fila}
            $modelo.Grupo.Filas+= $fila
            if($i -ge $anteriores.Count){[void]$ui.PanelAjustes.Items.Add($fila)}
        }
        while($ui.PanelAjustes.Items.Count -gt $modelos.Count){$ui.PanelAjustes.Items.RemoveAt($ui.PanelAjustes.Items.Count-1)}
        if($Global:TextoSinResultados.Visibility -eq 'Visible'){[void]$ui.PanelAjustes.Items.Add($Global:TextoSinResultados)}
        $Global:ClaveFilasAjustes=$clave
    } finally { $ui.PanelAjustes.IsHitTestVisible=$true }
    if($destino -and $ui.PanelAjustes.IsVisible){
        # Realiza solo la fila del ancla y corrige su posición tras layout, sin LayoutUpdated permanente.
        $lista=$ui.PanelAjustes;$lista.ScrollIntoView($destino)
        $restaurar={
            if($revision -ne $Global:RevisionFilas){return}
            $c=$lista.ItemContainerGenerator.ContainerFromItem($destino)
            $scroll=$lista.Template.FindName('PART_ScrollViewer',$lista)
            if($c -and $scroll){$y=$c.TranslatePoint([Windows.Point]::new(0,0),$lista).Y;$scroll.ScrollToVerticalOffset([Math]::Max(0,$scroll.VerticalOffset+$y-$ancla.Y))}
        }.GetNewClosure()
        [void]$lista.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::Loaded,[Action]$restaurar)
    } elseif(-not $ConservarPosicion -and $ui.PanelAjustes.IsVisible -and $ui.PanelAjustes.Items.Count){
        $ui.PanelAjustes.ScrollIntoView($ui.PanelAjustes.Items[0])
    }
}
function Get-TipoManual([string]$Modo=$Global:ModoOptimizar) {
    # Una sola correspondencia para navegación, categorías, tarjetas y plan de aplicación.
    if($Modo -eq 'manual-unicas'){return 'accion'}
    if($Modo -eq 'manual-recurrentes'){return 'interruptor'}
    return $Global:TipoManual
}
function Test-FiltroChip($c,[string]$id) {
    switch($id){'activas'{return ($c.Estado -eq $true)};'desactivadas'{return ($c.Estado -ne $true)};default{return $true}}
}
function Test-ContextoManual($c) {
    return ($c.Ajuste.tipo -eq (Get-TipoManual) -and $c.Ajuste.ui.grupo -eq $Global:GrupoActual -and ($ui.ChkAvanzados.IsChecked -or $c.Ajuste.nivel -ne 'Agresivo'))
}
function Get-CategoriasManual {
    if(-not $Global:CacheCategorias -or -not [object]::ReferenceEquals($Global:CacheCategorias.Catalogo,$Global:Catalogo)){
        $mapa=@{interruptor=@{};accion=@{}}
        foreach($a in $Global:Catalogo.ajustes){$mapa[$a.tipo][$a.ui.grupo]=$true}
        $datos=@{}
        foreach($tipo in 'interruptor','accion'){$datos[$tipo]=@($Global:Catalogo.gruposVisuales | Where-Object {$mapa[$tipo].ContainsKey([string]$_.id)})}
        $Global:CacheCategorias=@{Catalogo=$Global:Catalogo;Datos=$datos}
    }
    return $Global:CacheCategorias.Datos[(Get-TipoManual)]
}
function Update-Categorias {
    $grupos=@(Get-CategoriasManual)
    if($Global:GrupoActual -notin @($grupos.id)){$Global:GrupoActual=if($grupos.Count){[string]$grupos[0].id}else{''}}
    foreach($id in $Global:BotonesCategorias.Keys){$b=$Global:BotonesCategorias[$id];$b.Visibility=if($id -in @($grupos.id)){'Visible'}else{'Collapsed'};$b.IsChecked=($id -eq $Global:GrupoActual)}
    $ui.TxtCategoriaActual.Text=Get-NombreGrupo $Global:GrupoActual
}
function Set-Categoria([string]$id) {
    $Global:GrupoActual=$id;Update-Categorias;Update-Chips;Update-FiltroAjustes
}
function Update-Chips {
    # Los dos estados se cuentan DENTRO del modo, categoría, búsqueda y permiso elegidos.
    $cuentas=@{activas=0;desactivadas=0};$buscar=$ui.TxtBuscarAjuste.Text.Trim()
    foreach($c in $Global:Controles.Values){
        if(-not (Test-ContextoManual $c)){continue}
        $contenido=$c.Ajuste.ui.titulo+' '+$c.Ajuste.descripcion+' '+$c.Ajuste.id
        if($buscar -and $contenido.IndexOf($buscar,[StringComparison]::CurrentCultureIgnoreCase) -lt 0){continue}
        if($c.Estado -eq $true){$cuentas.activas++}else{$cuentas.desactivadas++}
    }
    foreach($id in $Global:Chips.Keys){$b=$Global:Chips[$id];$b.Content="$($b.DataContext) · $($cuentas[$id])";$b.IsChecked=($id -eq $Global:FiltroActual)}
}
function Update-FiltroAjustes {
    $buscar=$ui.TxtBuscarAjuste.Text.Trim();$cambio=$false;$total=0
    foreach($r in $Global:Rejillas){
        foreach($card in $r.Tarjetas){$c=$Global:Controles[$card.Tag];$contenido=$c.Ajuste.ui.titulo+' '+$c.Ajuste.descripcion+' '+$c.Ajuste.id
            $ver=((Test-ContextoManual $c) -and (Test-FiltroChip $c $Global:FiltroActual) -and (-not $buscar -or $contenido.IndexOf($buscar,[StringComparison]::CurrentCultureIgnoreCase) -ge 0))
            $v=if($ver){'Visible'}else{'Collapsed'};if("$($card.Visibility)" -ne $v){$cambio=$true};$card.Visibility=$v;if($ver){$total++}
        }
    }
    $ui.TxtCantidadAjustes.Text="$total ajustes en esta vista · desactivadas incluye estados sin comprobar; consulta ⓘ."
    $Global:TextoSinResultados.Visibility=if($total){'Collapsed'}else{'Visible'}
    if($cambio -or -not $Global:NumColumnas){$n=[Math]::Max(1,$Global:NumColumnas);Set-Columnas $n -Forzar -ConservarPosicion $false}
}
function Set-FiltroChip([string]$id){$Global:FiltroActual=if($Global:FiltroActual -eq $id){''}else{$id};Update-Chips;Update-FiltroAjustes}
# Objetos persistentes para los 129 ajustes. El modo filtra por tipo ANTES de categorías/estado.
foreach($tipo in 'interruptor','accion'){
    foreach($g in $Global:Catalogo.gruposVisuales){
        $ajustes=@($Global:Catalogo.ajustes | Where-Object {$_.ui.grupo -eq $g.id -and $_.tipo -eq $tipo})
        if(-not $ajustes.Count){continue}
        $cards=@(foreach($a in $ajustes){$card=New-TarjetaAjuste $a;$card.Tag=$a.id;$card})
        [void]$Global:Rejillas.Add(@{Tarjetas=$cards;Filas=@();Tipo=$tipo;Grupo=$g.id})
    }
}
$Global:TextoSinResultados=New-Texto 'No hay ajustes que coincidan. Cambia de categoría, desmarca el estado o borra la búsqueda. Las opciones agresivas solo aparecen si las aceptas al abrir Manuales.' 13 '#929CAB';$Global:TextoSinResultados.Margin='0,25,0,0'
foreach($g in $Global:Catalogo.gruposVisuales){$b=New-Object Windows.Controls.Primitives.ToggleButton;$b.Style=$Global:Ventana.FindResource('Categoria');$b.Tag=$g.id;$b.Content=$g.nombre;$b.Add_Click({Set-Categoria $this.Tag});$Global:BotonesCategorias[$g.id]=$b;[void]$ui.PanelCategorias.Children.Add($b)}
foreach($o in @(@{id='activas';nombre='Activas'},@{id='desactivadas';nombre='Desactivadas'})){$b=New-Object Windows.Controls.Primitives.ToggleButton;$b.Style=$Global:Ventana.FindResource('Chip');$b.Tag=$o.id;$b.DataContext=$o.nombre;$b.Add_Click({Set-FiltroChip $this.Tag});$Global:Chips[$o.id]=$b;[void]$ui.PanelChips.Children.Add($b)}
Update-Categorias

Add-Pagina 'resumen' 'Inicio' 'El estado de tu equipo, sin complicaciones.' $ui.PagResumen $false
Add-Pagina 'optimizar' 'Optimizar' 'Elige cambios. Los que ya están aplicados se muestran en gris y no se repiten.' $ui.PagOptimizar $true
Add-Pagina 'boost' 'Acelerar' 'Una limpieza de Windows, con tu permiso y sin tocar tus documentos.' $ui.PagBoost
Add-Pagina 'copias' 'Copias' 'Puntos de restauración y copias del registro.' $ui.PagCopias
Add-Pagina 'inicio' 'Inicio programas' 'Controla qué se abre al encender y quita entradas de programas que ya no existen.' $ui.PagInicio
Add-Pagina 'desinstalador' 'Desinstalador' 'Desinstala con la herramienta oficial y revisa los rastros antes de borrarlos.' $ui.PagDesinstalador
Add-Pagina 'host' 'Escáner' 'Los componentes de tu ordenador · solo lectura · valores al escanear.' $ui.PagHost
Add-Pagina 'ajustes' 'Ajustes' 'Preferencias y avisos de seguridad.' $ui.PagAjustes
$ui.BtnInicioLogo.Add_Click({$ui.Nav.SelectedItem=$null;Show-Pagina 'resumen'})
$ui.Nav.Add_SelectionChanged({if($ui.Nav.SelectedItem){Show-Pagina $ui.Nav.SelectedItem.Tag}})
$Global:RelojBuscar=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
$Global:RelojBuscar.Interval=[TimeSpan]::FromMilliseconds(160)
$Global:RelojBuscar.Add_Tick({$Global:RelojBuscar.Stop();Update-Chips;Update-FiltroAjustes})
$ui.TxtBuscarAjuste.Add_TextChanged({$Global:RelojBuscar.Stop();$Global:RelojBuscar.Start()})
function Set-OpcionesAgresivas([bool]$Mostrar) {
    $ui.ChkAvanzados.IsChecked=$Mostrar
    if(-not $Mostrar){
        $Global:Cargando=$true
        try {foreach($c in $Global:Controles.Values){if($c.Ajuste.nivel -eq 'Agresivo'){$c.Cb.IsChecked=($c.Estado -eq $true);$c.Tocado=$false}}}finally{$Global:Cargando=$false}
        Update-Pendientes
    }
    Update-Chips;Update-FiltroAjustes
}
function Get-ClaveDisposicion([double]$Ancho) {
    if($Ancho -le 0){return ''}
    # El mínimo 1360×780 admite ya la composición amplia (sidebar fija de 96).
    # No quedan breakpoints que remonten tarjetas o muevan Inicio durante el arrastre.
    return 'manual3-host3-modos3-preset2-metricas4'
}
function Request-Disposicion {
    if($ui.Paginas.ActualWidth -le 0){return}
    if((Get-ClaveDisposicion $ui.Paginas.ActualWidth) -eq $Global:ClaveDisposicion){if($Global:RelojDisposicion.IsEnabled){$Global:RelojDisposicion.Stop()};return}
    # Throttle de inicialización, nunca debounce reiniciado en cada píxel.
    if(-not $Global:RelojDisposicion.IsEnabled){$Global:RelojDisposicion.Start()}
}
function Update-Disposicion {
    $clave=Get-ClaveDisposicion $ui.Paginas.ActualWidth
    if(-not $clave -or $Global:ClaveDisposicion -eq $clave){return}
    Set-Columnas 3
    # WPF distribuye los anchos Star de forma continua; no se fuerzan medidas ni filas nuevas.
    if($ui.ModosOptimizar.Columns -ne 3){$ui.ModosOptimizar.Columns=3}
    if($ui.PanelHost.Columns -ne 3){$ui.PanelHost.Columns=3}
    if($ui.TarjetasPreset.Columns -ne 2){$ui.TarjetasPreset.Columns=2}
    if($ui.HomeMetricas.Columns -ne 4){$ui.HomeMetricas.Columns=4}
    if($ui.TxtBuscarAjuste.Width -ne 205){$ui.TxtBuscarAjuste.Width=205}
    $Global:ClaveDisposicion=$clave
}
Read-ProgresoPreset
# Filtrar primero: evita construir 129 filas invisibles para descartarlas al instante.
Update-Chips;Update-FiltroAjustes
$Global:RelojDisposicion=[Windows.Threading.DispatcherTimer]::new([Windows.Threading.DispatcherPriority]::Background)
$Global:RelojDisposicion.Interval=[TimeSpan]::FromMilliseconds(80)
$Global:RelojDisposicion.Add_Tick({$Global:RelojDisposicion.Stop();Update-Disposicion})
# Compartir un único throttle de 80 ms; después de inicializar, cualquier arrastre conserva la misma clave.
$ui.Paginas.Add_SizeChanged({param($sender,$e) if($e.WidthChanged){Request-Disposicion}})
$Global:Ventana.Add_SizeChanged({param($sender,$e) if($e.WidthChanged){Request-Disposicion}})

# ===================== Detección del estado real =====================
function Set-EstadoControl([string]$l) {
    $p = $l -split '\|'; if ($p.Count -ne 2) { return }
    $c = $Global:Controles[$p[0]]; if (-not $c) { return }
    $Global:Cargando = $true
    try {
        $c.Estado = if ($p[1] -eq 'True') { $true } elseif ($p[1] -eq 'False') { $false } else { $null }
        if (-not $c.Tocado) {   # si el usuario ya lo ha cambiado, se respeta su elección
            if ($c.Ajuste.tipo -eq 'interruptor') { $c.Cb.IsChecked = ($c.Estado -eq $true) }
            elseif ($c.Estado -eq $true) { $c.Cb.IsChecked = $true; $c.Cb.IsEnabled = $false }
        }
        if ($c.Estado -eq $true -and $c.Ajuste.tipo -ne 'interruptor') { $c.Cb.IsChecked = $true; $c.Cb.IsEnabled = $false }
        if ($c.Ajuste.tipo -ne 'interruptor' -and $c.Estado -ne $true -and $c.Ajuste.compatibilidad -contains $Global:Version) { $c.Cb.IsEnabled = $true }
    } finally { $Global:Cargando = $false }
    $Global:PendientesSucio = $true
}
function Start-Deteccion {
    Select-Nivel @()
    $Global:Cargando = $true
    foreach ($c in $Global:Controles.Values) { $c.Tocado = $false; if ($c.Ajuste.comprobar) { $c.Estado = $null; $c.Cb.IsChecked = $false; $c.Cb.IsEnabled = $c.Compatible } }
    $Global:Cargando = $false
    $Global:Detectando = $true; $ui.TxtDetectando.Text = '⏳ Detectando el estado actual de cada ajuste...'; $ui.TxtDetectando.Visibility = 'Visible'; Update-Pendientes
    Start-Tarea -Nombre 'detección de estado' -Carril 'deteccion' -MaxSegundos 240 -Codigo { Get-EstadoAjustes -MaxSegundos 15 } -AlParcial { param($l) Set-EstadoControl "$l" } -AlTerminar {
        param($res)
        foreach ($l in $res) { Set-EstadoControl "$l" }
        $Global:Detectando = $false
        $ui.TxtDetectando.Visibility = 'Collapsed'
        Update-Pendientes; Update-ResumenGrupos
        $act = @($Global:Controles.Values | Where-Object { $_.Estado -eq $true }).Count
        $sin = @($Global:Controles.Values | Where-Object { $_.Compatible -and $_.Ajuste.comprobar -and $null -eq $_.Estado }).Count
        Show-Banner "Estado revisado: $act ya aplicados; $sin sin comprobar. Los aplicados se omiten." $(if ($sin) {'aviso'}else{'ok'})
    }
}

function Select-Nivel([string[]]$Niveles) {
    $Global:Cargando = $true
    foreach ($c in $Global:Controles.Values) {
        if (-not $c.Cb.IsEnabled) { continue }
        $quiere = ($Niveles -contains $c.Ajuste.nivel) -and -not ($c.Ajuste.id -in 'pers_claro','red_dns_google') -and -not ($c.Ajuste.id -eq 'rend_alto' -and $Niveles -contains 'Moderado') -and -not $c.Ajuste.fueraDePreset -and ($ui.ChkAvanzados.IsChecked -or $c.Ajuste.nivel -ne 'Agresivo')
        $otro = $c.Ajuste.excluyeCon
        if ($quiere -and $otro -and $Global:Controles[$otro].Estado -eq $true) { $quiere = $false }
        if ($c.Ajuste.tipo -eq 'interruptor') { $c.Cb.IsChecked = ($quiere -or $c.Estado -eq $true) }
        else { $c.Cb.IsChecked = $quiere }
        $c.Tocado = ($Niveles.Count -gt 0)
    }
    $Global:Cargando = $false
    Update-Pendientes
}

# ===================== Aplicar cambios =====================
$Global:CodigoAjustes = {
    param($Aplicar, $Revertir, [bool]$SinPunto)
    Set-Estado 'Creando punto de restauración...' 2
    if (-not $SinPunto) { if (-not (New-PuntoRestauracion 'OptimiZation · Versión 2 · antes de aplicar cambios')) { return ('FALLO_PUNTO|' + ($Global:UltimoErrorRestauracion -replace '[\r\n|]', ' ')) } }
    Set-Estado 'Copiando el registro...' 5
    [void](Backup-Registro)
    $trabajo = @($Aplicar | ForEach-Object { @{ A = $_; Modo = 'aplicar' } }) + @($Revertir | ForEach-Object { @{ A = $_; Modo = 'deshacer' } })
    $ok = 0; $err = 0; $explorador = $false; $i = 0; $tTotal = Get-Date
    foreach ($w in $trabajo) {
        $i++; $a = $w.A; $modo = $w.Modo
        $pg = [int](5 + 95 * ($i - 1) / [Math]::Max(1, $trabajo.Count))
        $Global:PrefijoEstado = "($i/$($trabajo.Count) · $pg %) "
        Set-Estado "($i/$($trabajo.Count)) $($a.nombre)" $pg
        $restante = if ($i -gt 1) { ' · ~' + (Format-Duracion (((Get-Date) - $tTotal).TotalSeconds / ($i - 1) * ($trabajo.Count - $i + 1))) + ' restante en total' } else { '' }
        Write-Log ('[{0}/{1} · {2} % · {3} transcurrido{4}]' -f $i, $trabajo.Count, $pg, (Format-Duracion ((Get-Date) - $tTotal).TotalSeconds), $restante)
        $tA = Get-Date
        try {
            if ($a.comprobar) {
                $ya = Test-AjusteAplicado $a
                if (($modo -eq 'aplicar' -and $ya) -or ($modo -eq 'deshacer' -and -not $ya)) {
                    Write-Log "  Se omite $($a.nombre): el estado ya coincide." 'OK'; continue
                }
            }
        } catch { Write-Log "  No se modifica $($a.nombre): $($_.Exception.Message)" 'ERROR'; $err++; continue }
        $codigo = $a.$modo
        if (-not $codigo) { Write-Log "$($a.nombre): no tiene acción para '$modo'." 'AVISO'; continue }
        Write-Log "$(if($modo -eq 'aplicar'){'Aplicando'}else{'Revirtiendo'}): $($a.nombre)"
        try { $errorAntes = $Error[0]; & ([ScriptBlock]::Create($codigo)); if ($Error.Count -and -not [object]::ReferenceEquals($Error[0], $errorAntes)) { throw 'La acción notificó errores. Consulta el registro; puede haberse aplicado solo una parte.' }; if ($a.comprobar) { $despues = Test-AjusteAplicado $a; if (($modo -eq 'aplicar' -and -not $despues) -or ($modo -eq 'deshacer' -and $despues)) { throw 'No se pudo confirmar el estado final. Revisa el registro.' } }; Write-Log ("  Hecho: {0} ({1})" -f $a.nombre, (Format-Duracion ((Get-Date) - $tA).TotalSeconds)) 'OK'; $ok++; if ($a.reiniciaExplorador) { $explorador = $true } }
        catch { Write-Log "  Error en $($a.nombre): $($_.Exception.Message)" 'ERROR'; $err++ }
    }
    if ($explorador) { Write-Log 'Reiniciando el Explorador para aplicar cambios visuales...'; Restart-Explorer }
    Set-Estado "Terminado: $ok correctos, $err con error." 100
    Write-Log "Terminado: $ok correctos, $err con error." 'OK'
    return "OK|$ok|$err"
}
function Invoke-Plan([bool]$SinPunto = $false) {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    $Global:EsperandoPunto=$false
    $p = $Global:PlanPendiente
    $Global:PresetEnEjecucion=$Global:PresetPlanPendiente
    $aplicar = @($p.Aplicar) + @($p.Acciones)
    if ($Global:Tareas['deteccion']) {
        Stop-Carril 'deteccion' 'Se interrumpe para aplicar tus cambios; se repetirá al terminar.'
        $Global:Detectando = $false; $ui.TxtDetectando.Visibility = 'Collapsed'
    }
    try { Start-Tarea -Nombre 'aplicar cambios' -EsAplicacion -Codigo $Global:CodigoAjustes -Parametros @{ Aplicar = $aplicar; Revertir = @($p.Revertir); SinPunto = $SinPunto } -AlTerminar {
        param($res)
        $r = "$($res | Select-Object -Last 1)"
        if ($r.StartsWith('FALLO_PUNTO|')) {
            $Global:EsperandoPunto=$true
            Request-Confirmacion -Titulo '⚠ No se pudo crear el punto de restauración' -Texto ($r.Substring(12) + "`n`nCancelar es lo recomendado. Puedes continuar sin punto bajo tu responsabilidad; se intentará copiar el registro.") -Boton 'Continuar sin punto' -Si { Invoke-Plan $true } -AlCancelar {$Global:EsperandoPunto=$false;Complete-Aplicacion}
            return
        }
        if ($r -notmatch '^OK\|\d+\|\d+$') { Show-Banner 'La tarea no terminó correctamente. Revisa el registro; no se da por aplicada.' 'error'; Start-Deteccion; return }
        $x = $r -split '\|'
        if([int]$x[2] -eq 0 -and $Global:PresetEnEjecucion){Complete-PresetAplicado $Global:PresetEnEjecucion}
        $Global:PresetEnEjecucion=$null
        Show-Banner "Terminado: $($x[1]) cambios correctos, $($x[2]) con error. Algunos cambios necesitan reiniciar el equipo. Volviendo a comprobar el estado…" $(if ([int]$x[2]) { 'aviso' } else { 'ok' })
        Start-Deteccion
    } } catch {
        Write-Log "No se pudo iniciar Aplicar cambios: $($_.Exception.Message)" 'ERROR'
        Show-Banner 'No se pudo iniciar la aplicación de cambios.' 'error'
        Complete-Aplicacion
    }
}
function Request-Ejecutar {
    $p = Get-Plan
    $Global:PresetPlanPendiente=$null
    if($Global:ModoOptimizar -eq 'preconfiguradas' -and $Global:PresetSeleccionado){
        $objetivos=@((Get-ObjetivosPreset $Global:PresetSeleccionado).id | Where-Object {$Global:Controles[$_] -and $Global:Controles[$_].Cb.IsChecked})
        $Global:PresetPlanPendiente=@{Id=$Global:PresetSeleccionado;Objetivos=$objetivos}
    }
    $n = $p.Aplicar.Count + $p.Revertir.Count + $p.Acciones.Count
    if(-not $n){
        if($Global:PresetPlanPendiente){
            $c=Get-CoberturaPreset @($Global:PresetPlanPendiente.Objetivos)
            if($c.Total -and $c.Activos -eq $c.Total){
                Request-Confirmacion -Titulo "¿Usar $(Get-NombrePreset $Global:PresetPlanPendiente.Id) ya activo?" -Texto 'Los objetivos del perfil ya están aplicados y comprobados. Confirmar solo actualiza el indicador de progreso; no repite cambios ni crea otra copia.' -Boton 'Usar perfil activo' -Si {Complete-PresetAplicado $Global:PresetPlanPendiente;Update-Metricas} -AlCancelar {$Global:PresetPlanPendiente=$null;$Global:PresetSeleccionado=$null}
                return
            }
        }
        Show-Banner 'No hay cambios pendientes: activa o desactiva interruptores, o marca casillas.' 'info';return
    }
    $Global:PlanPendiente = $p
    $lin = @()
    if ($p.Aplicar.Count)  { $lin += "ACTIVAR ($($p.Aplicar.Count)):";  $lin += ($p.Aplicar  | ForEach-Object { "   • [$($_.nivel)] $($_.nombre)" }) }
    if ($p.Revertir.Count) { $lin += "REVERTIR ($($p.Revertir.Count)):"; $lin += ($p.Revertir | ForEach-Object { "   • [$($_.nivel)] $($_.nombre)" }) }
    if ($p.Acciones.Count) { $lin += "QUITAR / EJECUTAR ($($p.Acciones.Count)):"; $lin += ($p.Acciones | ForEach-Object { "   • [$($_.nivel)] $($_.nombre)" }) }
    $rojos = @(@($p.Aplicar) + @($p.Acciones) | Where-Object { $_.nivel -eq 'Agresivo' }).Count
    if ($rojos) { $lin += ''; $lin += "⚠ Incluye $rojos ajuste(s) AGRESIVOS." }
    $lin += ''; $lin += 'Antes se creará un punto de restauración y una copia del registro.'
    $titulo=if($Global:PresetPlanPendiente){"¿Seguro que quieres activar $(Get-NombrePreset $Global:PresetPlanPendiente.Id)?"}else{"¿Aplicar $n cambio(s)?"}
    Request-Confirmacion -Titulo $titulo -Texto ($lin -join "`n") -Boton '▶ Aplicar ahora' -Si { Invoke-Plan $false } -AlCancelar {$Global:PresetPlanPendiente=$null;$Global:PresetSeleccionado=$null}
}
function Select-Gaming {
    Select-Nivel @()
    $ids = @($Global:Catalogo.presetGaming)
    $Global:Cargando = $true
    foreach ($id in $ids) {
        $c = $Global:Controles[$id]; if (-not $c -or -not $c.Cb.IsEnabled -or $c.Ajuste.nivel -eq 'Agresivo') { continue }
        $c.Cb.IsChecked = $true; $c.Tocado = $true
        $o = $c.Ajuste.excluyeCon; if ($o -and $Global:Controles[$o]) { $Global:Controles[$o].Cb.IsChecked = $false; $Global:Controles[$o].Tocado = $true }
    }
    $Global:Cargando = $false
    Update-Pendientes
}
# ===================== Optimizar: tres modos separados; perfiles confirman y aplican =====================
function Show-ModoOptimizar([ValidateSet('elegir','manual-recurrentes','manual-unicas','preconfiguradas')][string]$Modo='elegir', [switch]$OpcionesElegidas) {
    $manual=$Modo -in 'manual-recurrentes','manual-unicas'
    if($manual -and -not $OpcionesElegidas){
        if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
        # Rutas explícitas: la respuesta diferida conserva el tipo sin depender del scope del evento.
        if($Modo -eq 'manual-recurrentes'){
            $abrirSi={Set-OpcionesAgresivas $true;Show-ModoOptimizar 'manual-recurrentes' -OpcionesElegidas}
            $abrirNo={Set-OpcionesAgresivas $false;Show-ModoOptimizar 'manual-recurrentes' -OpcionesElegidas}
        }else{
            $abrirSi={Set-OpcionesAgresivas $true;Show-ModoOptimizar 'manual-unicas' -OpcionesElegidas}
            $abrirNo={Set-OpcionesAgresivas $false;Show-ModoOptimizar 'manual-unicas' -OpcionesElegidas}
        }
        Request-Confirmacion -Titulo '¿Mostrar opciones agresivas?' -Texto 'Pueden reducir la seguridad, detener actualizaciones o quitar funciones de Windows. No garantizan más velocidad ni FPS. «Sí, mostrarlas» abre el modo elegido con estas opciones; «No, solo seguras/moderadas» lo abre sin ellas y retira sus cambios pendientes, sin deshacer los ya activos. Puedes volver a «Elegir modo» y abrir Manuales otra vez para ocultarlas. Nada se aplica ahora.' -Boton 'Sí, mostrarlas' -BotonCancelar 'No, solo seguras/moderadas' -Si $abrirSi -AlCancelar $abrirNo
        return
    }
    $modoAnterior=$Global:ModoOptimizar
    $Global:ModoOptimizar=$Modo
    $Global:PresetSeleccionado=$null
    $Global:PresetPlanPendiente=$null
    if($ui.BtnEjecutar){$ui.BtnEjecutar.Visibility=if($Global:PaginaActual -eq 'optimizar' -and $manual){'Visible'}else{'Collapsed'};$ui.TxtContador.Visibility=$ui.BtnEjecutar.Visibility}
    $ui.PanelElegirModo.Visibility=if($Modo -eq 'elegir'){'Visible'}else{'Collapsed'}
    $ui.PanelPreconfiguradas.Visibility=if($Modo -eq 'preconfiguradas'){'Visible'}else{'Collapsed'}
    $ui.PanelManual.Visibility=if($manual){'Visible'}else{'Collapsed'}
    $ui.BarraModoOptimizar.Visibility=if($Modo -eq 'elegir'){'Collapsed'}else{'Visible'}
    $ui.BuscadorAjustes.Visibility=if($manual){'Visible'}else{'Collapsed'}
    $ui.TxtTitulo.Visibility=if($Modo -eq 'elegir'){'Visible'}else{'Collapsed'}
    $ui.TxtModoOptimizar.Text=switch($Modo){'manual-recurrentes'{'Manuales Recurrentes'};'manual-unicas'{'Manuales Únicas'};'preconfiguradas'{'Preconfiguradas'};default{''}}
    if($manual){
        $Global:TipoManual=Get-TipoManual $Modo
        if($modoAnterior -ne $Modo){$Global:GrupoActual='';$Global:FiltroActual='';$ui.TxtBuscarAjuste.Text=''}
        Update-Categorias;Update-Chips;Update-FiltroAjustes;Update-Pendientes
    }
}
function Select-IdsPreset([string[]]$Ids) {
    Select-Nivel @()
    $Global:Cargando=$true
    try {
        foreach($id in $Ids){
            $c=$Global:Controles[$id]
            if(-not $c -or -not $c.Compatible -or -not $c.Cb.IsEnabled -or $c.Ajuste.nivel -eq 'Agresivo' -or $c.Ajuste.fueraDePreset){continue}
            $c.Cb.IsChecked=$true;$c.Tocado=$true
            $otro=$c.Ajuste.excluyeCon
            if($otro -and $Global:Controles[$otro]){$Global:Controles[$otro].Cb.IsChecked=$false;$Global:Controles[$otro].Tocado=$true}
        }
    } finally {$Global:Cargando=$false}
    Update-Pendientes
}
function Get-NombrePreset([string]$Id) {
    switch($Id){'juegos'{'Juegos'};'alto'{'Alto Rendimiento'};'recomendadas'{'Recomendadas'};'maximo'{'Máximo rendimiento'}}
}
function Select-Preset([ValidateSet('juegos','alto','maximo','recomendadas')][string]$Id) {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    $Global:PresetSeleccionado=$Id
    if($Id -eq 'maximo'){
        Request-Confirmacion -Titulo '¿Seguro que quieres activar Máximo rendimiento?' -Texto 'Este perfil incluye ajustes agresivos. Puede reducir la seguridad, quitar funciones y cambiar actualizaciones. También puede aumentar consumo, calor o ruido. No es overclock ni garantiza más FPS. No lo uses si no sabes volver atrás. Al continuar verás la confirmación final de los cambios. Confirmar «Aplicar ahora» crea el punto y la copia de seguridad y aplica el perfil automáticamente, sin entrar en Manuales.' -Boton 'Entiendo el riesgo: continuar' -Si {
            $ui.ChkAvanzados.IsChecked=$true
            Select-Nivel @('Seguro','Moderado','Agresivo')
            Show-RevisionPreset 'Máximo rendimiento'
        }
        return
    }
    switch($Id){
        'juegos' {Select-Gaming;$nombre='Juegos'}
        'alto' {
            Select-IdsPreset @((Get-ObjetivosPreset 'alto').id)
            $nombre='Alto Rendimiento'
        }
        'recomendadas' {Select-Nivel @('Seguro');$nombre='Recomendadas'}
    }
    Show-RevisionPreset $nombre
}
function Show-RevisionPreset([string]$Nombre) {
    # Un perfil abre directamente la confirmación de aplicación, nunca la lista Manual.
    # La misma ruta conserva punto obligatorio, copia de registro y registro solo al aplicar.
    if($ui.TxtModoOptimizar){$ui.TxtModoOptimizar.Text="Preconfiguradas · $Nombre"}
    Request-Ejecutar
}
$ui.BtnModoRecurrentes.Add_Click({Show-ModoOptimizar $this.Tag})
$ui.BtnModoUnicas.Add_Click({Show-ModoOptimizar $this.Tag})
$ui.BtnModoPreconfiguradas.Add_Click({Show-ModoOptimizar 'preconfiguradas'})
$ui.BtnVolverModos.Add_Click({Show-ModoOptimizar 'elegir'})
$ui.BtnPresetJuegos.Add_Click({Select-Preset 'juegos'})
$ui.BtnPresetAlto.Add_Click({Select-Preset 'alto'})
$ui.BtnPresetMaximo.Add_Click({Select-Preset 'maximo'})
$ui.BtnPresetRecomendadas.Add_Click({Select-Preset 'recomendadas'})

$ui.BtnEjecutar.Add_Click({ Request-Ejecutar })
$ui.BtnSalir.Add_Click({ $Global:Ventana.Close() })

# ===================== Escáner 3 × 3, sin datos simulados =====================
$Global:HostTexto='';$Global:ScannerDatos=@{};$Global:HostCards=@{}
function Initialize-ScannerCards {
    $ui.PanelHost.Children.Clear();$Global:HostCards=@{}
    foreach($s in @(@('cpu','PROCESADOR'),@('gpu','GRÁFICA'),@('ram','MEMORIA'),@('discos','ALMACENAMIENTO'),@('volumenes','VOLÚMENES'),@('sistema','SISTEMA'),@('pantalla','PANTALLA'),@('placa','PLACA'),@('seguridad','ENERGÍA Y SEGURIDAD'))){
        $card=New-Tarjeta;$card.Margin='4,0,4,12';$card.Padding='18';$card.MinHeight=203
        $st=New-Object Windows.Controls.StackPanel;$header=New-Object Windows.Controls.StackPanel;$header.Orientation='Horizontal';$ico=New-Icono $s[0] 17;$ico.Margin='0,0,9,0';[void]$header.Children.Add($ico);$t=New-Texto $s[1] 9 '#8C98A8';$t.VerticalAlignment='Center';[void]$header.Children.Add($t);[void]$st.Children.Add($header)
        $h=New-Texto 'Leyendo…' 13 '#D8E1EC' -Negrita;$h.Margin='0,17,0,10';[void]$st.Children.Add($h)
        $rows=New-Object Windows.Controls.StackPanel;[void]$st.Children.Add($rows);$card.Child=$st;[void]$ui.PanelHost.Children.Add($card);$Global:HostCards[$s[0]]=@{Titulo=$h;Filas=$rows}
    }
}
function Add-HostResultado($obj) {
    if(-not $obj -or -not $Global:HostCards.ContainsKey([string]$obj.Id)){return}
    $Global:ScannerDatos[$obj.Id]=$obj;$c=$Global:HostCards[$obj.Id];$c.Titulo.Text=$obj.Resumen;$c.Filas.Children.Clear()
    foreach($par in $obj.Filas){
        $g=New-Rejilla @('0.95*','1.2*');$g.Margin='0,3';$k=New-Texto $par[0] 10 '#778497';$k.Margin='0,0,8,0';$v=New-Texto $par[1] 10 '#BAC6D7';$v.TextAlignment='Right';[Windows.Controls.Grid]::SetColumn($v,1);[void]$g.Children.Add($k);[void]$g.Children.Add($v);[void]$c.Filas.Children.Add($g)
    }
    # El contador de procesos es una instantánea del escáner, sin otro lector periódico.
    if($obj.Id -eq 'sistema' -and $obj.Datos -and $obj.Datos.ContainsKey('Procesos')){$ui.MetricaProcesos.Text="$($obj.Datos.Procesos)"}
}
function Update-Salud {
    $ui.PanelSalud.Children.Clear();$hayAviso=$false
    $faltan=@($Global:ScannerDatos.Values | Where-Object {$_.Error}).Count+(9-$Global:ScannerDatos.Count)
    if($faltan){[void]$ui.PanelSalud.Children.Add((New-Texto "⚠ $faltan secciones sin lectura completa. Los valores no disponibles no se sustituyen por ejemplos." 11 '#E2A65C'));$hayAviso=$true}
    $v=$Global:ScannerDatos['volumenes'];if($v -and $v.Datos.PocoEspacio.Count){[void]$ui.PanelSalud.Children.Add((New-Texto ('⚠ Menos del 15 % libre en: '+($v.Datos.PocoEspacio -join ', ')+'. Revisa archivos antes de limpiar.') 11 '#E2A65C'));$hayAviso=$true}
    elseif($v -and -not $v.Error){[void]$ui.PanelSalud.Children.Add((New-Texto '✓ Las unidades leídas tienen al menos un 15 % libre.' 11 '#48B890'))}
    $r=$Global:ScannerDatos['ram'];if($r -and $r.Datos.RamUso -ge 85){[void]$ui.PanelSalud.Children.Add((New-Texto '⚠ La memoria estaba por encima del 85 % al escanear. Revisa las apps abiertas.' 11 '#E2A65C'));$hayAviso=$true}
    $d=$Global:ScannerDatos['discos'];if($d -and $d.Datos.DiscosAviso){[void]$ui.PanelSalud.Children.Add((New-Texto '⚠ Windows informa un aviso en un disco. Haz copia y revisa su herramienta de diagnóstico.' 11 '#E2A65C'));$hayAviso=$true}
    $s=$Global:ScannerDatos['seguridad'];if($s -and $s.Datos.ArranqueSeguro -eq 'Desactivado'){[void]$ui.PanelSalud.Children.Add((New-Texto '⚠ Arranque seguro desactivado. Cambiarlo requiere revisar la compatibilidad del firmware.' 11 '#E2A65C'));$hayAviso=$true}
    if(-not $hayAviso -and $Global:ScannerDatos.Count -eq 9){[void]$ui.PanelSalud.Children.Add((New-Texto '✓ Sin avisos en estas comprobaciones básicas. No sustituye un diagnóstico completo.' 11 '#48B890'))}
    $nota=New-Texto 'Son lecturas de una instantánea. WMI puede omitir datos o limitar la VRAM; no es una prueba de velocidad ni de estabilidad.' 10 '#748196';$nota.Margin='0,10,0,0';[void]$ui.PanelSalud.Children.Add($nota)
}
function Update-Host {
    if($Global:Tareas['host']){return}
    $Global:HostCargado=$false;$Global:HostTexto='';$Global:ScannerDatos=@{};Initialize-ScannerCards
    $ui.BtnHostActualizar.IsEnabled=$false;$ui.BtnHostCopiar.IsEnabled=$false;$ui.BtnHostExportar.IsEnabled=$false
    $ui.PanelSalud.Children.Clear();[void]$ui.PanelSalud.Children.Add((New-Texto 'Escaneando componentes… Las tarjetas se completan a medida que Windows responde.' 11 '#929CAB'))
    $ui.MetricaProcesos.Text='—'
    Start-Tarea -Nombre 'leer componentes' -Carril 'host' -MaxSegundos 180 -Codigo {Get-ScannerInfo} -AlParcial {param($obj) Add-HostResultado $obj} -AlTerminar {
        param($res)
        foreach($obj in $res){if(-not $Global:ScannerDatos.ContainsKey([string]$obj.Id)){Add-HostResultado $obj}}
        foreach($id in $Global:HostCards.Keys){if(-not $Global:ScannerDatos.ContainsKey($id)){$Global:HostCards[$id].Titulo.Text='Sin lectura · vuelve a escanear'}}
        $txt=New-Object Text.StringBuilder;[void]$txt.AppendLine("OptimiZation · Versión 2 · $env:COMPUTERNAME · $(Get-Date -Format 'dd/MM/yyyy HH:mm') (hora local del equipo)")
        foreach($id in 'cpu','gpu','ram','discos','volumenes','sistema','pantalla','placa','seguridad'){$o=$Global:ScannerDatos[$id];if(-not $o){continue};[void]$txt.AppendLine("`n$($o.Categoria): $($o.Resumen)");foreach($p in $o.Filas){[void]$txt.AppendLine("  $($p[0]): $($p[1])")}}
        $Global:HostTexto=$txt.ToString()
        $Global:HostCargado=(@($Global:ScannerDatos.Values | Where-Object {-not $_.Error}).Count -gt 0)
        $ui.BtnHostActualizar.IsEnabled=$true;$ui.BtnHostCopiar.IsEnabled=$true;$ui.BtnHostExportar.IsEnabled=$true
        if(-not $Global:HostCargado){Show-Banner 'No se pudieron leer los componentes. Vuelve a escanear; revisa que WMI esté disponible en Windows.' 'aviso'}
        Update-Salud
    }
}
Initialize-ScannerCards

$ui.BtnHostActualizar.Add_Click({ Update-Host })
$ui.BtnHostCopiar.Add_Click({ if ($Global:HostTexto) { [System.Windows.Clipboard]::SetText($Global:HostTexto); Show-Banner 'Información del equipo copiada al portapapeles.' 'ok' } })
$ui.BtnHostExportar.Add_Click({
    if (-not $Global:HostTexto) { Show-Banner 'Aún se están leyendo los componentes.' 'info'; return }
    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.FileName = "Equipo_$($env:COMPUTERNAME)_" + (Get-Date -Format 'yyyyMMdd_HHmm') + '.txt'; $dlg.Filter = 'Texto|*.txt'; $dlg.Title = 'Guardar información del equipo (este archivo lo gestionas tú)'
    if (-not $dlg.ShowDialog()) { return }
    $f = $dlg.FileName
    Set-Content -Path $f -Value $Global:HostTexto -Encoding UTF8
    Show-Banner "Exportado a $f" 'ok'
})

# ===================== Desinstalador =====================
$Global:TodasApps = @()
function Set-FiltroApps {
    $f = $ui.TxtBuscarApp.Text
    $ui.GridApps.ItemsSource = if ($f) { [FilaOpt[]]@($Global:TodasApps | Where-Object { $_.Nombre -like "*$f*" -or $_.Detalle -like "*$f*" }) } else { $Global:TodasApps }
}
function Update-Apps([scriptblock]$Despues = {}) {
    $Global:DespuesApps = $Despues
    Start-Tarea -Nombre 'leer programas' -MaxSegundos 180 -Codigo { param($Appx) Set-Estado 'Leyendo programas instalados...' 30; Get-AppsInstaladas -IncluirAppx:$Appx; Set-Estado 'Lista de programas actualizada.' 100 } `
        -Parametros @{ Appx = [bool]$ui.ChkAppx.IsChecked } -AlTerminar {
            param($res)
            $Global:TodasApps = [FilaOpt[]]@($res | Where-Object { $_ -is [FilaOpt] })
            Set-FiltroApps
            $ui.TxtEstado.Text = "$($Global:TodasApps.Count) programas encontrados."
            & $Global:DespuesApps
        }
}
function Start-BusquedaRestos($app) {
    $Global:AppRestos = $app
    Start-Tarea -Nombre 'eliminar rastros (escaneo)' -Codigo { param($App, $Todas) Set-Estado "Buscando rastros de $($App.Nombre)..." 40; Find-Restos -App $App -TodasLasApps $Todas; Set-Estado 'Escaneo terminado.' 100 } `
        -Parametros @{ App = $app; Todas = $Global:TodasApps } -AlTerminar {
            param($res)
            $r = [FilaOpt[]]@($res | Where-Object { $_ -is [FilaOpt] })
            $ui.GridRestos.ItemsSource = $r
            $alta = @($r | Where-Object Seleccionado).Count
            Select-Pagina 'desinstalador'
            Show-Banner "$($r.Count) posibles rastros de $($Global:AppRestos.Nombre) ($alta de confianza alta, ya marcados). Revísalos y pulsa «Eliminar rastros marcados»." 'info'
        }
}
function Start-EliminarRastros {
    $Global:RestosElegidos = @($ui.GridRestos.ItemsSource | Where-Object Seleccionado)
    if (-not $Global:RestosElegidos) { Show-Banner 'No hay rastros marcados.' 'info'; return }
    $bajos = @($Global:RestosElegidos | Where-Object { $_.Confianza -ne 'Alta' }).Count
    $txt = "Se eliminarán $($Global:RestosElegidos.Count) elemento(s) de forma DEFINITIVA (Papelera si se puede; el registro se exporta a un .reg temporal y se borra)."
    if ($bajos) { $txt += "`n`n⚠ $bajos son de confianza Media/Baja: comprueba que no pertenecen a otro programa." }
    $nombre = if ($Global:AppRestos) { $Global:AppRestos.Nombre } else { 'programa' }
    Request-Confirmacion -Titulo '¿Eliminar rastros?' -Texto $txt -Boton '🗑 Eliminar rastros' -Si {
        Start-Tarea -Nombre 'eliminar rastros' -Codigo { param($Restos, $Nombre) Set-Estado 'Eliminando rastros...' 20; Remove-Restos -Restos $Restos -NombreApp $Nombre } `
            -Parametros @{ Restos = $Global:RestosElegidos; Nombre = $Global:AppRestos.Nombre } -AlTerminar {
                param($res)
                $r = "$($res | Select-Object -Last 1)" -split '\|'
                if ($r.Count -eq 3 -and $r[0] -eq 'RESTOS') { Show-Banner "$($r[1]) rastros eliminados; $($r[2]) con error. Revisa el registro si alguna carpeta sigue en uso." $(if ([int]$r[2]) {'aviso'}else{'ok'}) } else { Show-Banner 'La eliminación no terminó. Revisa el registro.' 'error' }
                $ui.GridRestos.ItemsSource = $null; $Global:InicioCargado = $false; Update-Apps
            }
    }
}
function Start-Desinstalacion($app, [bool]$SinPunto = $false) {
    $Global:AppDesinstalando=$app
    Start-Tarea -Nombre 'desinstalar' -Codigo {
        param($App, $SinPunto)
        if(-not $SinPunto -and -not (New-PuntoRestauracion "OptimiZation · Versión 2 · antes de desinstalar $($App.Nombre)")){return ('FALLO_PUNTO|' + ($Global:UltimoErrorRestauracion -replace '[\r\n|]',' '))}
        Set-Estado "Ejecutando el desinstalador oficial de $($App.Nombre)..." 40
        $c=Invoke-DesinstaladorOficial $App.Datos
        Write-Log "Desinstalador terminado (código $c)."
        Set-Estado 'Desinstalador oficial terminado.' 100
        return "DESINSTALAR|$c"
    } -Parametros @{App=$app;SinPunto=$SinPunto} -AlTerminar {
        param($res)
        $r="$($res | Select-Object -Last 1)"
        if($r.StartsWith('FALLO_PUNTO|')){Request-Confirmacion -Titulo 'No se pudo crear el punto' -Texto ($r.Substring(12)+"`nNo se ha desinstalado nada. Se recomienda cancelar.") -Boton 'Desinstalar sin punto' -Si {Start-Desinstalacion $Global:AppDesinstalando $true};return}
        if($r -notmatch '^DESINSTALAR\|(0|1641|3010)$'){Show-Banner "La desinstalación no ha confirmado éxito ($r). No borres sus carpetas si sigue instalado." 'error';return}
        Request-Confirmacion -Titulo "¿Ha terminado el desinstalador de $($Global:AppDesinstalando.Nombre)?" -Texto 'Cuando su ventana se haya cerrado, puedes buscar y revisar los rastros. No borres carpetas de un programa que siga instalado.' -Boton 'Eliminar rastros' -Si {Start-BusquedaRestos $Global:AppDesinstalando}
    }
}
$ui.BtnRefrescarApps.Add_Click({ Update-Apps })
$ui.ChkAppx.Add_Click({ Update-Apps })
$ui.TxtBuscarApp.Add_TextChanged({ Set-FiltroApps })
$ui.BtnSoloRestos.Add_Click({
    $app = $ui.GridApps.SelectedItem
    if (-not $app) { Show-Banner 'Selecciona un programa de la lista.' 'info'; return }
    Start-BusquedaRestos $app
})
$ui.BtnDesinstalar.Add_Click({
    $Global:AppElegida = $ui.GridApps.SelectedItem
    if (-not $Global:AppElegida) { Show-Banner 'Selecciona un programa de la lista.' 'info'; return }
    Request-Confirmacion -Titulo "¿Desinstalar «$($Global:AppElegida.Nombre)»?" -Texto 'Se creará un punto de restauración, se lanzará su desinstalador oficial y después podrás escanear y eliminar los rastros que queden.' -Boton '🗑 Desinstalar' -Si { Start-Desinstalacion $Global:AppElegida }
})
$ui.BtnEliminarRastros.Add_Click({ Start-EliminarRastros })

# ===================== Programas de inicio =====================
function Set-FilasInicio($filas, [switch]$Parcial) {
    $ui.GridInicio.ItemsSource = [FilaOpt[]]@($filas | Where-Object { $_ -is [FilaOpt] })
    if ($Parcial) { $ui.TxtInicioEstado.Text = "⏳ $(@($filas).Count) entradas leídas hasta ahora… (sigue leyendo tareas programadas)"; return }
    $ui.TxtInicioEstado.Text = ''
    $h = @($filas | Where-Object { $_.Confianza -eq 'Huérfana' }).Count
    $ui.TxtEstado.Text = "$(@($filas).Count) entradas de inicio, $h huérfanas."
    if ($h) { Show-Banner "Hay $h entrada(s) de inicio huérfanas (en rojo): su programa ya no existe. Pulsa «Limpiar huérfanas» para quitarlas." 'aviso' }
}
function Update-Inicio {
    $Global:InicioCargado = $true
    $ui.TxtInicioEstado.Text = '⏳ Leyendo programas de inicio…'
    Start-Tarea -Nombre 'leer programas de inicio' -Carril 'inicio' -AlParcial { param($lote) Set-FilasInicio $lote -Parcial } -MaxSegundos 120 -Codigo { Set-Estado 'Leyendo programas de inicio...' 40; Get-ProgramasInicio; Set-Estado 'Programas de inicio leídos.' 100 } -AlTerminar {
        param($res)
        $filas = @($res | Where-Object { $_ -is [FilaOpt] })
        if (-not $filas -and $Global:UltimosErrores) {
            Show-Banner 'No se pudieron leer los programas de inicio. Revisa el registro y vuelve a pulsar Actualizar.' 'error'
        }
        Set-FilasInicio $filas
    }
}
function Get-FilasInicioMarcadas {
    $sel = @($ui.GridInicio.ItemsSource | Where-Object Seleccionado)
    if (-not $sel -and $ui.GridInicio.SelectedItem) { $sel = @($ui.GridInicio.SelectedItem) }
    return $sel
}
$ui.BtnInicioRefrescar.Add_Click({ Update-Inicio })
$ui.BtnInicioDesactivar.Add_Click({
    $s = Get-FilasInicioMarcadas; if (-not $s) { Show-Banner 'Marca o selecciona alguna entrada.' 'info'; return }
    foreach ($f in $s) { try { Set-ProgramaInicio $f $false } catch { Write-Log "$($f.Nombre): $($_.Exception.Message)" 'ERROR' } }
    Show-Banner "$($s.Count) entrada(s) desactivadas." 'ok'; Update-Inicio
})
$ui.BtnInicioActivar.Add_Click({
    $s = Get-FilasInicioMarcadas; if (-not $s) { Show-Banner 'Marca o selecciona alguna entrada.' 'info'; return }
    foreach ($f in $s) { try { Set-ProgramaInicio $f $true } catch { Write-Log "$($f.Nombre): $($_.Exception.Message)" 'ERROR' } }
    Show-Banner "$($s.Count) entrada(s) activadas." 'ok'; Update-Inicio
})
$ui.BtnInicioHuerfanas.Add_Click({
    $Global:Huerfanas = @($ui.GridInicio.ItemsSource | Where-Object { $_.Confianza -eq 'Huérfana' })
    if (-not $Global:Huerfanas) { Show-Banner 'No hay entradas huérfanas. ¡Todo limpio!' 'ok'; return }
    Request-Confirmacion -Titulo "¿Limpiar $($Global:Huerfanas.Count) entrada(s) huérfanas?" -Texto ((($Global:Huerfanas | ForEach-Object { " • [$($_.Tipo)] $($_.Nombre)" }) -join "`n") + "`n`nSe guarda copia (.reg / .xml) en Documentos\Optimization\CopiasInicio.") -Boton '🧹 Limpiar' -Si {
        $dir = New-DirCopiaInicio; $ok = 0
        foreach ($f in $Global:Huerfanas) { try { Remove-EntradaInicio $f $dir; $ok++ } catch { Write-Log "No se pudo eliminar $($f.Nombre): $($_.Exception.Message)" 'ERROR' } }
        Show-Banner "$ok entrada(s) huérfanas eliminadas (copia en $dir)." 'ok'; Update-Inicio
    }
})
$ui.BtnInicioDesinstalar.Add_Click({
    $fila = $ui.GridInicio.SelectedItem
    if (-not $fila) { $fila = @($ui.GridInicio.ItemsSource | Where-Object Seleccionado) | Select-Object -First 1 }
    if (-not $fila) { Show-Banner 'Selecciona una entrada de la lista.' 'info'; return }
    $Global:FilaInicioRaiz = $fila
    Update-Apps {
        $fila = $Global:FilaInicioRaiz
        $Global:AppRaiz = Find-AppDeEntrada $fila $Global:TodasApps
        if ($Global:AppRaiz) {
            Request-Confirmacion -Titulo "Desinstalar de raíz: $($Global:AppRaiz.Nombre)" -Texto "Entrada de inicio: $($fila.Nombre)`nPrograma: $($Global:AppRaiz.Nombre) ($($Global:AppRaiz.Detalle))`n`n1. Se elimina la entrada de inicio (con copia).`n2. Punto de restauración y desinstalador oficial.`n3. Escaneo y eliminación de rastros." -Boton '🗑 Desinstalar de raíz' -Si {
                try { Remove-EntradaInicio $Global:FilaInicioRaiz (New-DirCopiaInicio) } catch { Write-Log "No se pudo eliminar la entrada: $($_.Exception.Message)" 'ERROR' }
                $Global:InicioCargado = $false
                Start-Desinstalacion $Global:AppRaiz
            }
        } else {
            Request-Confirmacion -Titulo "«$($fila.Nombre)» no está en la lista de programas instalados" -Texto 'Puede que ya se desinstalara y solo quede la entrada de inicio. Se eliminará la entrada (con copia) y se buscarán restos por nombre y carpeta.' -Boton '🧹 Quitar entrada y eliminar rastros' -Si {
                $f = $Global:FilaInicioRaiz
                try { Remove-EntradaInicio $f (New-DirCopiaInicio) } catch { Write-Log "No se pudo eliminar la entrada: $($_.Exception.Message)" 'ERROR' }
                $carpeta = if ($f.Detalle -and $f.Detalle -match '^[A-Za-z]:\\') { Split-Path $f.Detalle -Parent } else { $null }
                $falsa = New-Object FilaOpt; $falsa.Nombre = $f.Nombre
                $falsa.Datos = @{ Tipo = 'Win32'; DisplayName = $f.Nombre; Publisher = ''; InstallLocation = $(if ($carpeta -and (Test-Path $carpeta)) { $carpeta } else { $null }); UninstallString = ''; KeyPath = $null }
                $Global:InicioCargado = $false
                Start-BusquedaRestos $falsa
            }
        }
    }
})

# ===================== Acelerar: cuatro acciones independientes y confirmadas =====================
function Request-LimpiezaWindows {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    Request-Confirmacion -Titulo '¿Ejecutar Limpieza Windows?' -Texto "Guarda tu trabajo.`n`nSe borrarán temporales, descargas de Windows Update, caché de Delivery Optimization y el contenido de la Papelera. También se vacía DNS y se limpian componentes antiguos con DISM. No se puede deshacer el borrado.`n`nSe pausan y reanudan BITS, Windows Update, UsoSvc y DoSvc. Puede tardar varios minutos. No se reinicia Explorer, no se cierra ninguna app ni se reinicia el PC." -Boton 'Sí, limpiar' -Si {
        $ui.TxtBoostResultado.Text='Empezando… midiendo el espacio libre en C:.'
        Start-Tarea -Nombre 'limpieza de Windows' -Codigo {Invoke-LimpiezaWindows} -AlParcial {
            param($r)
            if($r.Tipo -eq 'LIMPIEZA_INICIO'){$ui.TxtBoostResultado.Text=('Antes: {0:N2} GB libres en C:. Limpiando…' -f $r.AntesGB)}
        } -AlTerminar {
            param($res)
            $r=$res | Where-Object {$_.Tipo -eq 'LIMPIEZA'} | Select-Object -Last 1
            if(-not $r){$ui.TxtBoostResultado.Text='No se pudo terminar la limpieza. Revisa el registro.';Show-Banner $ui.TxtBoostResultado.Text 'error';return}
            $texto=if($null -ne $r.DespuesGB){'Antes: {0:N2} GB · Después: {1:N2} GB libres en C:.' -f $r.AntesGB,$r.DespuesGB}else{'Antes: {0:N2} GB libres en C:. No se pudo medir el espacio final.' -f $r.AntesGB}
            if($r.Avisos.Count){$texto+=' Hay pasos pendientes; revisa el registro.'}
            if($r.RequiereReinicio){$texto+=' Windows recomienda reiniciar cuando te venga bien.'}
            $ui.TxtBoostResultado.Text=$texto;Show-Banner $texto $(if($r.Avisos.Count){'aviso'}else{'ok'})
        }
    }
}
$ui.BtnBoostLimpiar.Add_Click({Request-LimpiezaWindows})
function Request-ReiniciarExplorer {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    Request-Confirmacion -Titulo '¿Reiniciar Explorer?' -Texto 'Guarda tu trabajo y termina las copias de archivos. El escritorio, la barra y las carpetas abiertas pueden desaparecer un momento. No se limpian temporales, cachés ni la Papelera y no se reinicia el PC.' -Boton 'Sí, reiniciar Explorer' -Si {
        $ui.TxtBoostResultado.Text='Reiniciando Explorer…'
        Start-Tarea -Nombre 'reiniciar Explorer' -Codigo {Restart-Explorer;'EXPLORER_OK'} -AlTerminar {
            param($res)
            $ok='EXPLORER_OK' -in $res -and -not $Global:UltimosErrores
            $ui.TxtBoostResultado.Text=if($ok){'Explorer reiniciado.'}else{'No se pudo completar el reinicio de Explorer. Revisa el registro.'}
            Show-Banner $ui.TxtBoostResultado.Text $(if($ok){'ok'}else{'error'})
        }
    }
}
function Request-LimpiarTemporales {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    Request-Confirmacion -Titulo '¿Limpiar solo los temporales?' -Texto 'Se borra únicamente el contenido de %TEMP% y C:\Windows\Temp. El borrado no se puede deshacer. Los archivos en uso, enlaces y archivos de esta sesión se conservan. No se toca Windows Update, Delivery Optimization, la Papelera ni DNS y no se reinicia Explorer.' -Boton 'Sí, limpiar temporales' -Si {
        $ui.TxtBoostResultado.Text='Limpiando temporales…'
        Start-Tarea -Nombre 'limpiar temporales' -Codigo {Invoke-LimpiarTemporales} -AlTerminar {
            param($res)
            $r=$res | Where-Object {$_.Tipo -eq 'TEMPORALES'} | Select-Object -Last 1
            $ui.TxtBoostResultado.Text=if(-not $r){'No se pudieron limpiar los temporales. Revisa el registro.'}elseif($r.Avisos.Count){'Temporales: se han conservado elementos en uso o protegidos. Revisa el registro.'}else{'Temporales limpiados.'}
            Show-Banner $ui.TxtBoostResultado.Text $(if(-not $r){'error'}elseif($r.Avisos.Count){'aviso'}else{'ok'})
        }
    }
}
function Request-VaciarDns {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación actual.' 'aviso';return}
    Request-Confirmacion -Titulo '¿Vaciar la caché DNS?' -Texto 'Solo se vacía la caché local de nombres DNS. No se cambian los servidores DNS ni se borran otros archivos.' -Boton 'Sí, vaciar DNS' -Si {
        $ui.TxtBoostResultado.Text='Vaciando la caché DNS…'
        Start-Tarea -Nombre 'vaciar caché DNS' -Codigo {Invoke-VaciarDns} -AlTerminar {
            param($res)
            $ok='DNS_OK' -in $res -and -not $Global:UltimosErrores
            $ui.TxtBoostResultado.Text=if($ok){'Caché DNS vaciada.'}else{'No se pudo vaciar la caché DNS. Revisa el registro.'}
            Show-Banner $ui.TxtBoostResultado.Text $(if($ok){'ok'}else{'error'})
        }
    }
}
$ui.BtnBoostExplorer.Add_Click({Request-ReiniciarExplorer})
$ui.BtnBoostTemporales.Add_Click({Request-LimpiarTemporales})
$ui.BtnBoostDns.Add_Click({Request-VaciarDns})


# ===================== Copias: información real, resultado verificado =====================
$ui.TxtRutaCopias.Text="Carpeta de esta sesión:`n$Global:DirectorioCopias"
function Update-Puntos {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación para actualizar la lista.' 'aviso';return}
    $ui.TxtPuntosEstado.Text='Leyendo puntos guardados por Windows…'
    Start-Tarea -Nombre 'listar puntos de restauración' -Carril 'copias' -MaxSegundos 120 -Codigo {
        try {
            foreach($p in @(Get-PuntosRestauracion)){
                $f=if($p.CreationTime -is [datetime]){$p.CreationTime.ToLocalTime().ToString('dd/MM/yyyy HH:mm')}else{[Management.ManagementDateTimeConverter]::ToDateTime([string]$p.CreationTime).ToString('dd/MM/yyyy HH:mm')}
                [pscustomobject]@{Numero=$p.SequenceNumber;Fecha=$f;Descripcion=$p.Description}
            }
        } catch {Write-Log "No se pueden leer los puntos: $($_.Exception.Message)" 'ERROR';throw}
    } -AlTerminar {
        param($res)
        $ui.GridPuntos.ItemsSource=[object[]]@($res | Where-Object {$_.PSObject.Properties['Numero']})
        $ui.TxtPuntosEstado.Text=if($Global:UltimosErrores){'No se pudo leer la lista de Windows. Comprueba Protección del sistema en Windows y vuelve a actualizar.'}elseif(-not $ui.GridPuntos.ItemsSource.Count){'Windows no muestra puntos de restauración. Crea uno o revisa Protección del sistema.'}else{"$($ui.GridPuntos.ItemsSource.Count) punto(s) guardados por Windows."}
    }
}
$ui.BtnActualizarPuntos.Add_Click({Update-Puntos})
function Request-EliminarPuntos {
    if($Global:Tareas['principal'] -or $Global:Tareas['copias']){Show-Banner 'Espera a que termine la operación o la lectura de puntos.' 'aviso';return}
    $seleccion=$ui.GridPuntos.SelectedItem
    if(-not $seleccion){Show-Banner 'Selecciona un punto de la lista.' 'info';return}
    # Copia por valor: nunca depende de la selección posterior a la confirmación.
    $Global:PuntoEliminarConfirmado=$seleccion.Numero
    $detalle=" • Nº $($seleccion.Numero) · $($seleccion.Fecha) · $($seleccion.Descripcion)"
    $si={
        if($Global:Tareas['principal'] -or $Global:Tareas['copias']){Show-Banner 'La lista está ocupada. Vuelve a seleccionar y confirmar.' 'aviso';return}
        $ui.TxtCopiasResultado.Text='Eliminando únicamente el punto confirmado…'
        Start-Tarea -Nombre 'eliminar punto seleccionado' -Parametros @{Numeros=@($Global:PuntoEliminarConfirmado)} -Codigo {
            param($Numeros) Remove-PuntosRestauracion -Numeros $Numeros -Confirmado
        } -AlTerminar {
            param($res)
            $r=$res | Where-Object {$_.Tipo -eq 'PUNTOS_ELIMINADOS'} | Select-Object -Last 1
            if(-not $r){$ui.TxtCopiasResultado.Text='El borrado no terminó correctamente. Comprueba la lista de Windows.';Show-Banner $ui.TxtCopiasResultado.Text 'error'}
            else {
                $p=@($r.Resultados)[0]
                $ui.TxtCopiasResultado.Text="Punto nº $($p.Numero): $($p.Mensaje)"
                Show-Banner $ui.TxtCopiasResultado.Text $(if($p.Eliminado -and $p.Verificado){'ok'}else{'aviso'})
            }
            Update-Puntos
        }
    }
    Request-Confirmacion -Titulo '¿Eliminar el punto de restauración seleccionado?' -Texto ("ATENCIÓN: esta operación es IRREVERSIBLE. No podrás restaurar Windows al punto que elimines. No hay Papelera ni copia para recuperarlo.`n`nSe eliminará SOLO este punto:`n$detalle`n`nLos demás puntos no se solicitan para borrado. Si no estás seguro, pulsa Cancelar.") -Boton 'Eliminar definitivamente' -Si $si
}
$ui.BtnEliminarPuntos.Add_Click({Request-EliminarPuntos})
function Request-UsarRestauracion {
    if($Global:Tareas['principal'] -or $Global:Tareas['copias']){Show-Banner 'Espera a que termine la operación o la lectura de puntos.' 'aviso';return}
    $p=$ui.GridPuntos.SelectedItem
    if(-not $p){Show-Banner 'Selecciona un punto de la lista para restaurar.' 'info';return}
    $Global:PuntoRestaurarConfirmado=$p.Numero
    $detalle="Nº $($p.Numero) · $($p.Fecha)`n$($p.Descripcion)"
    Request-Confirmacion -Titulo '¿Seguro que quieres restaurar este punto?' -Texto ("$detalle`n`nSe restaurarán archivos y configuración del sistema al estado de ese punto; puede afectar a programas y controladores instalados después. No sustituye una copia de tus documentos.`n`nGuarda tu trabajo. Windows necesita reiniciarse para completar la restauración. Esta app solicitará el punto confirmado, pero NO reiniciará automáticamente: tendrás que reiniciar manualmente tras la aceptación de Windows.") -Boton 'Sí, usar este punto' -Si {
        if($Global:Tareas['principal'] -or $Global:Tareas['copias']){Show-Banner 'La lista está ocupada. Vuelve a seleccionar y confirmar.' 'aviso';return}
        $ui.TxtCopiasResultado.Text='Solicitando la restauración del punto confirmado a Windows…'
        Start-Tarea -Nombre 'usar restauración seleccionada' -Parametros @{Numero=$Global:PuntoRestaurarConfirmado} -Codigo {
            param($Numero) Start-RestauracionSeleccionada -Numero $Numero -Confirmado
        } -AlTerminar {
            param($res)
            $r=$res | Where-Object {$_.Tipo -eq 'RESTAURACION_SOLICITADA'} | Select-Object -Last 1
            if(-not $r -or $Global:UltimosErrores){
                $fallo=$res | Where-Object {$_.Tipo -eq 'RESTAURACION_ERROR'} | Select-Object -Last 1
                $ui.TxtCopiasResultado.Text=if($fallo){$fallo.Mensaje}else{'No se pudo iniciar o confirmar la restauración. Windows no devolvió una aceptación válida. No se ha reintentado ni se ha elegido otro punto; comprueba Restaurar sistema en Windows.'}
                Show-Banner $ui.TxtCopiasResultado.Text 'error';return
            }
            $ui.TxtCopiasResultado.Text="Windows aceptó restaurar el punto nº $($r.Numero). Aún NO está completado: guarda tu trabajo y reinicia Windows manualmente para completar la restauración."
            Show-Banner $ui.TxtCopiasResultado.Text 'aviso'
        }
    }
}
$ui.BtnUsarRestauracion.Add_Click({Request-UsarRestauracion})

$ui.BtnCrearPunto.Add_Click({
    Request-Confirmacion -Titulo '¿Preparar Protección del sistema y crear un punto?' -Texto 'Se activará la protección en la unidad de Windows. Si los servicios o una directiva local la bloquean, se intentarán reparar y se guardará una copia de la directiva. No se borran puntos existentes. En un PC de empresa la política puede volver a bloquearla.' -Boton 'Crear punto' -Si {
        $ui.TxtCopiasResultado.Text='Creando punto… espera a que Windows termine.'
        Start-Tarea -Nombre 'crear punto de restauración' -Codigo {
            $ok=New-PuntoRestauracion 'OptimiZation · Versión 2 · punto manual'
            if($ok){'PUNTO_OK'}else{'PUNTO_ERROR|'+$Global:UltimoErrorRestauracion}
        } -AlTerminar {
            param($res);$r="$($res | Select-Object -Last 1)"
            if($r -eq 'PUNTO_OK'){$ui.TxtCopiasResultado.Text='✓ Punto creado y comprobado en Windows.';Show-Banner $ui.TxtCopiasResultado.Text 'ok'}
            else{$ui.TxtCopiasResultado.Text=if($r.StartsWith('PUNTO_ERROR|')){$r.Substring(12)}else{'La creación no terminó correctamente. Revisa el registro.'};Show-Banner $ui.TxtCopiasResultado.Text 'error'}
            Update-Puntos
        }
    }
})
$ui.BtnExportarCopias.Add_Click({Request-ExportarCopias $false})

# ===================== Arranque =====================
$Global:Ventana.Add_ContentRendered({
    Write-Log "OptimiZation Versión 2 iniciado en $Global:Version (compilación $build)."
    Update-Disposicion
    Start-Deteccion
    Update-Host
})
# ===================== Cierre: solo archivos propios, con opción de conservar copias =====================
function Save-CopiasEn($carpeta) {
    $base=[IO.Path]::GetFullPath($carpeta).TrimEnd('\')
    $propia=[IO.Path]::GetFullPath($Global:DirectorioCopias).TrimEnd('\')
    $runtime=[IO.Path]::GetFullPath($Global:Raiz).TrimEnd('\')
    if($base -eq $propia -or $base.StartsWith($propia+'\',[StringComparison]::OrdinalIgnoreCase) -or $base -eq $runtime -or $base.StartsWith($runtime+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Elige una carpeta fuera de la sesión temporal.'}
    $destino=Join-Path $carpeta ('OptimiZation_copias_'+(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+(Get-Random -Maximum 99999))
    New-Item -ItemType Directory -Path $destino -ErrorAction Stop | Out-Null
    Copy-Item -LiteralPath $Global:DirectorioCopias -Destination $destino -Recurse -Force -ErrorAction Stop
    Write-Log "Copias exportadas a $destino" 'OK'
    return $destino
}
function Request-ExportarCopias([bool]$Cerrar = $false) {
    if($Global:Tareas['principal']){Show-Banner 'Espera a que termine la operación antes de guardar las copias.' 'aviso';return}
    $dlg=New-Object System.Windows.Forms.FolderBrowserDialog;$dlg.Description='Guardar copias fuera de las carpetas temporales de OptimiZation'
    if($dlg.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
        try{$d=Save-CopiasEn $dlg.SelectedPath;Show-Banner "Copias guardadas en $d" 'ok';if($Cerrar){Set-Content -LiteralPath $Global:ArchivoCierre -Value 'limpiar' -Encoding ASCII -ErrorAction Stop;$Global:CerrarConfirmado=$true;$Global:Ventana.Close()}}
        catch{Show-Banner "No se guardaron todas las copias. No se cierra: $($_.Exception.Message)" 'error'}
    }
}
$Global:CerrarConfirmado=$false
function Confirm-Cierre {
    if($Global:Tareas['principal']){Show-Banner 'Hay una operación en curso. Deja que termine antes de cerrar para no cortar una reparación, copia o desinstalación.' 'aviso';return}
    Request-Confirmacion -Titulo '¿Cerrar y limpiar los archivos propios?' -Texto "Se borrarán los archivos temporales de la app y las copias y el registro de ESTA sesión en:`n$Global:DirectorioCopias`n`nLos cambios y puntos de restauración de Windows se conservan. Si quieres guardar las copias, elige «Guardar copias en…». Windows o el antivirus pueden conservar historial de ejecución: no se promete invisibilidad." -Boton 'Cerrar y limpiar archivos' -Si {Set-Content -LiteralPath $Global:ArchivoCierre -Value 'limpiar' -Encoding ASCII -ErrorAction Stop;$Global:CerrarConfirmado=$true;$Global:Ventana.Close()} -BotonB 'Guardar copias en…' -B {Request-ExportarCopias $true}
}
$Global:Ventana.Add_Closing({param($remitente,$e) if(-not $Global:CerrarConfirmado){$e.Cancel=$true;Confirm-Cierre;return};$Global:Reloj.Stop();$Global:RelojBanner.Stop();$Global:RelojBuscar.Stop();$Global:RelojDisposicion.Stop();foreach($k in @($Global:Tareas.Keys)){Stop-Carril $k 'Cierre de la ventana.'}})
Select-Pagina 'resumen'
[void]$Global:Ventana.ShowDialog()
