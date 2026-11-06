param([string]$ReferenceDir='/workspace/OptimizadorWindows/tools/net48/build/.NETFramework/v4.8',[string]$OutDir='/workspace/OptimizadorWindows/dist')
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$Root=Split-Path $PSScriptRoot -Parent
$Build=Join-Path $PSScriptRoot 'build';New-Item -ItemType Directory -Path $Build -Force | Out-Null
$files=@('Main.ps1','Engine.ps1','Actions.ps1','Launch.ps1','WindowIdentity.ps1','MainWindow.xaml','tweaks.json','logo.ico','logo.png','LICENSE')
Add-Type -AssemblyName System.IO.Compression
$payload=Join-Path $Build 'payload.zip';$hashFile=Join-Path $Build 'sha256.txt'
$fs=[IO.File]::Open($payload,[IO.FileMode]::Create)
$zip=[IO.Compression.ZipArchive]::new($fs,[IO.Compression.ZipArchiveMode]::Create)
$hashes=@()
try{foreach($f in $files){
    $path=Join-Path $Root $f
    $hashes+=((Get-FileHash $path -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+$f)
    $e=$zip.CreateEntry($f,[IO.Compression.CompressionLevel]::Optimal);$e.LastWriteTime=[DateTimeOffset]::new(2026,11,6,0,0,0,[TimeSpan]::Zero)
    $s=$e.Open();try{$bytes=[IO.File]::ReadAllBytes($path);$s.Write($bytes,0,$bytes.Length)}finally{$s.Dispose()}
}}finally{$zip.Dispose();$fs.Dispose()}
[IO.File]::WriteAllLines($hashFile,$hashes,[Text.UTF8Encoding]::new($false))
$tree=[Microsoft.CodeAnalysis.CSharp.CSharpSyntaxTree]::ParseText([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Launcher.cs')))
$refs=[Collections.Generic.List[Microsoft.CodeAnalysis.MetadataReference]]::new()
foreach($name in @('mscorlib.dll','System.dll','System.Core.dll','System.IO.Compression.dll')){$refs.Add([Microsoft.CodeAnalysis.MetadataReference]::CreateFromFile((Join-Path $ReferenceDir $name)))}
$opts=[Microsoft.CodeAnalysis.CSharp.CSharpCompilationOptions]::new([Microsoft.CodeAnalysis.OutputKind]::WindowsApplication).WithOptimizationLevel([Microsoft.CodeAnalysis.OptimizationLevel]::Release).WithPlatform([Microsoft.CodeAnalysis.Platform]::AnyCpu).WithDeterministic($true)
$comp=[Microsoft.CodeAnalysis.CSharp.CSharpCompilation]::Create('OptimiZation_v2',[Microsoft.CodeAnalysis.SyntaxTree[]]@($tree),$refs,$opts)
$resources=[Collections.Generic.List[Microsoft.CodeAnalysis.ResourceDescription]]::new()
$resources.Add([Microsoft.CodeAnalysis.ResourceDescription]::new('payload.zip',[Func[IO.Stream]]{[IO.File]::OpenRead($payload)},$true))
$resources.Add([Microsoft.CodeAnalysis.ResourceDescription]::new('sha256.txt',[Func[IO.Stream]]{[IO.File]::OpenRead($hashFile)},$true))
$manifest=[IO.File]::OpenRead((Join-Path $PSScriptRoot 'app.manifest'));$icon=[IO.File]::OpenRead((Join-Path $Root 'logo.ico'))
$win32=$comp.CreateDefaultWin32Resources($true,$false,$manifest,$icon)
$exe=Join-Path $OutDir 'OptimiZation_v2.exe';$stream=[IO.File]::Open($exe,[IO.FileMode]::Create)
try{
    $result=$comp.Emit($stream,$null,$null,$win32,$resources,$null,[Threading.CancellationToken]::None)
    $result.Diagnostics | ForEach-Object {Write-Output $_.ToString()}
    if(-not $result.Success){throw 'Compilación fallida.'}
}finally{$stream.Dispose();$win32.Dispose();$icon.Dispose();$manifest.Dispose()}
Write-Output "PE generado: $exe"
Get-FileHash $exe -Algorithm SHA256
