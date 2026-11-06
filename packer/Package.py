"""Package OptimiZation 6.5.3 after Build.ps1 and all local static/mock suites."""
from pathlib import Path
import argparse,datetime,hashlib,json,shutil,zipfile
from zoneinfo import ZoneInfo
R=Path(__file__).resolve().parents[1];VERSION='6.5.3';PUBLIC_VERSION='2' # internal maintenance id; user-facing version is locked
a=argparse.ArgumentParser();a.add_argument('--out-dir',type=Path,default=R.parent/'dist');args=a.parse_args()
D=args.out_dir.resolve();D.mkdir(parents=True,exist_ok=True);S=D/('Fuentes_v'+VERSION)
EXE=D/'OptimiZation_v2.exe'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
assert EXE.is_file(),'Run packer/Build.ps1 first'
assert json.loads((R/'tweaks.json').read_text('utf-8-sig'))['version']==PUBLIC_VERSION
summary=json.loads((R/'tests/resultados-resumen-v6.5.3.json').read_text())
for name,count in summary['suites'].items():
 p=R/'tests'/('resultados-'+name+'-v6.5.3.txt')
 assert sum(l.startswith('OK:') for l in p.read_text().splitlines())==count and count>0,(name,count)
assert summary['total_checks']>=950 and len(summary['suites'])>=12
assert sum(l.startswith('Sintaxis OK:') for l in (R/'tests/resultados-sintaxis-v6.5.3.txt').read_text().splitlines())==summary['scripts_parsed']
assert sha(EXE) in (R/'tests/resultados-reproducibilidad-v6.5.3.txt').read_text()
files=['Main.ps1','Engine.ps1','Actions.ps1','Launch.ps1','WindowIdentity.ps1','MainWindow.xaml','tweaks.json','logo.ico','logo.png','Iniciar.bat','LEEME.md','LICENSE','EMPAQUETADO.md','PRUEBAS_WINDOWS.md','CHANGELOG_v6.5.3.md','INFORME_v6.5.3.md','extras/LimpiezaWindows11.bat']
files+=['packer/'+n for n in ('Build.ps1','Launcher.cs','app.manifest','Package.py','RecolorLogo.py')]
files += ['tests/'+n for n in ('UI652.ps1','CompileUI652.ps1','Visual652.py','Metrics652.ps1','UI651.ps1','Visual651.py','Runspace651.ps1','base-v6.5.sha256.json','Parse.ps1','Unit.ps1','UI61.ps1','UI611.ps1','CompileUI611.ps1','UI612.ps1','UI65.ps1','Metrics65.ps1','Runspace65.ps1','Compile65.ps1','Visual612.py','Visual65.py','VerifyPackage.py','Visual61.py','Visual611.py','catalogo-v6-original.sha256.json','logo-v6.5.json','resultados-resumen-v6.5.3.json')]
files += ['tests/baseline652/tweaks.json','tests/baseline652/Actions.ps1']
files += ['tests/'+n for n in ('UI653.ps1','Visual653.py','Cards653.ps1','Chrome653.py','CompileUI653.ps1','Runspace653.ps1','Run653.py','Metrics653.ps1','Progress653.ps1','Cleanup653.ps1','manual-dialog-preserved.json')]
files += [p.relative_to(R).as_posix() for p in (R/'tests/baseline653').glob('*') if p.is_file()]
files += [p.relative_to(R).as_posix() for p in (R/'tests').glob('resultados-*-v6.5.3.txt')]
files=sorted(set(files))
for f in files:
 p=S/f;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(R/f,p)
source_sums=''.join(sha(S/f)+'  '+f+'\n' for f in files)
(S/'SHA256SUMS_Fuentes.txt').write_text(source_sums);files.append('SHA256SUMS_Fuentes.txt')
Z=D/'OptimiZation_v2_Fuentes.zip'
with zipfile.ZipFile(Z,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
 for f in sorted(files):
  entry=zipfile.ZipInfo('Fuentes/'+f,date_time=(2026,11,6,1,0,0));entry.compress_type=zipfile.ZIP_DEFLATED;entry.external_attr=0o100644<<16
  z.writestr(entry,(S/f).read_bytes())
with zipfile.ZipFile(Z) as z:
 assert z.testzip() is None
 assert len(z.namelist())==len(files)
 for f in files:assert z.read('Fuentes/'+f)==(S/f).read_bytes()
 for line in source_sums.splitlines():
  h,f=line.split('  ',1);assert hashlib.sha256(z.read('Fuentes/'+f)).hexdigest()==h
 assert not any(any(n in f for n in ('/tmp/','/packer/build/','__pycache__')) for f in z.namelist())
 bat=z.read('Fuentes/Iniciar.bat');assert bat.count(b'\r\n')==len(bat.splitlines())
 assert 'Fuentes/extras/LimpiezaWindows11.bat' in z.namelist()
 assert 'by YuzVax' in z.read('Fuentes/MainWindow.xaml').decode('utf-8-sig')
 assert 'TxtHardwareChrome' not in z.read('Fuentes/Main.ps1').decode('utf-8-sig')
release=[EXE.name,Z.name]
for n in ('CHANGELOG_v6.5.3.md','INFORME_v6.5.3.md'):
 shutil.copyfile(R/n,D/n);release.append(n)
for n in ('LEEME','EMPAQUETADO','PRUEBAS_WINDOWS'):
 dest=n+'_v6.5.3.md';shutil.copyfile(R/(n+'.md'),D/dest);release.append(dest)
now=datetime.datetime.now(ZoneInfo('Europe/Madrid')).strftime('%d/%m/%Y %H:%M')
text=f"""VERIFICACIÓN OptimiZation · Versión 2 · by YuzVax / PE 2.0.0.0 (mantenimiento interno 6.5.3)
Fecha: {now} Europe/Madrid

OK: parser de {summary['scripts_parsed']} scripts PowerShell
OK: {summary['total_checks']} comprobaciones estáticas/lógicas en {len(summary['suites'])} suites
OK: 129 ajustes intactos, motor activo conservado, métricas 1 s, progreso verificado 90/100 y limpieza de código muerto
OK: tres modos separados, categorías por tipo, solo Activas/Desactivadas y planes Manual sin tipo oculto
OK: nombres compactos en columnas, información solo al pulsar ⓘ, búsqueda en cabecera superior derecha
OK: Z/autor, métricas CPU/RAM/GPU, perfiles confirmación→aplicación, Copias y registro preservados con mocks
OK: PE AnyCPU, ProductName/FileDescription OptimiZation, versión 2.0.0.0, UAC e iconos naranjas
OK: dos compilaciones del EXE con SHA-256 idéntico
OK: ZIP Fuentes interno, {len(files)} archivos, CRC y hashes de todas las fuentes
OK: Iniciar.bat CRLF, logos y extras/LimpiezaWindows11.bat incluidos
NO: Windows/WPF/EXE/servicios/DISM/API SRRemoveRestorePoint/SystemRestore.Restore no ejecutados
NO: lecturas hardware reales, render/DPI y diálogos en Windows pendientes; EXE sin firma

"""
for n in (EXE.name,Z.name):text+=f'{n}: {(D/n).stat().st_size} bytes · SHA256 {sha(D/n)}\n'
V='VERIFICACION_v6.5.3.txt';(D/V).write_text(text);release.append(V)
sums=''.join(sha(D/f)+'  '+f+'\n' for f in release)
(D/'SHA256SUMS_v6.5.3.txt').write_text(sums)
for line in sums.splitlines():
 h,f=line.split('  ',1);assert sha(D/f)==h
print(text)
print('SHA256SUMS_v6.5.3.txt verificado:',len(release),'archivos internos (usuario: SOLO EXE)')
