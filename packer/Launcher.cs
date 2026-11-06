// OptimiZation v2 — código propio, licencia de uso no comercial; ver LICENSE.
using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Runtime.InteropServices;
using System.Threading;
using System.Collections.Generic;
[assembly: AssemblyTitle("OptimiZation")]
[assembly: AssemblyDescription("OptimiZation Versión 2 — herramientas para Windows en castellano")]
[assembly: AssemblyProduct("OptimiZation")]
[assembly: AssemblyCompany("YuzVax")]
[assembly: AssemblyCopyright("Copyright © 2026 YuzVax · Uso no comercial")]
[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]
internal static class Launcher {
    [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int MessageBox(IntPtr h,string t,string c,uint type);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h,int cmd);
    [DllImport("shell32.dll",CharSet=CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    static readonly string Root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Optimization");
    static bool IsLink(string p) { return (File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0; }
    static void EnsureNormalDir(string p) {Directory.CreateDirectory(p);if(IsLink(p)) throw new IOException("La carpeta temporal es un enlace. No se usa por seguridad: "+p);}
    static string Hash(Stream s) {using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(s)).Replace("-","").ToLowerInvariant();}
    static Dictionary<string,string> Expected() {
        var d=new Dictionary<string,string>(StringComparer.Ordinal);
        using(var s=Assembly.GetExecutingAssembly().GetManifestResourceStream("sha256.txt"))
        using(var r=new StreamReader(s)) {string line;while((line=r.ReadLine())!=null) {int n=line.IndexOf("  ",StringComparison.Ordinal);if(n>0)d.Add(line.Substring(n+2),line.Substring(0,n));}}
        return d;
    }
    static void Extract(string dir) {
        var expected=Expected();int count=0;
        using(var stream=Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
        using(var zip=new ZipArchive(stream,ZipArchiveMode.Read)) {
            foreach(var e in zip.Entries) {
                if(e.FullName.IndexOfAny(new char[]{'/','\\',':'})>=0 || !expected.ContainsKey(e.FullName)) throw new IOException("Recurso no reconocido.");
                var path=Path.Combine(dir,e.FullName);
                using(var source=e.Open()) using(var target=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) source.CopyTo(target);
                using(var s=File.OpenRead(path)) if(Hash(s)!=expected[e.FullName]) throw new IOException("Recurso dañado: "+e.FullName);
                count++;
            }
        }
        if(count!=expected.Count) throw new IOException("El ejecutable no contiene todos los archivos necesarios.");
    }
    static void DeleteTree(string dir) {
        if(!Directory.Exists(dir))return;
        if(IsLink(dir))throw new IOException("No se limpia un enlace: "+dir);
        foreach(string f in Directory.GetFiles(dir)){if(IsLink(f))throw new IOException("Archivo enlazado; no se limpia.");File.SetAttributes(f,FileAttributes.Normal);File.Delete(f);}
        foreach(string child in Directory.GetDirectories(dir))DeleteTree(child);
        Directory.Delete(dir,false);
    }
    static bool Clean(string dir) {
        for(int i=0;i<12;i++){try{DeleteTree(dir);return true;}catch{Thread.Sleep(500);}}
        return !Directory.Exists(dir);
    }
    static void RemoveEmptyRoot(string root) {try{if(Directory.Exists(root)&&!IsLink(root)&&Directory.GetFileSystemEntries(root).Length==0)Directory.Delete(root);}catch{}}
    static void CleanOldSessions() {
        foreach(string dir in Directory.GetDirectories(Root,"sesion-*")) {
            try {
                if(IsLink(dir)||!File.Exists(Path.Combine(dir,".ow-session")))continue;
                int pid; if(!Int32.TryParse(File.ReadAllText(Path.Combine(dir,".ow-session")),out pid))continue;
                bool alive=false;try{using(var p=Process.GetProcessById(pid)){alive=!p.HasExited;}}catch(ArgumentException){}
                // Nunca se cierra una app/tarea ajena: solo restos de extracción cuyos procesos ya terminaron.
                if(!alive)Clean(dir);
            } catch{}
        }
    }
    [STAThread] static int Main() {
        string dir=null,backup=null,request=null;Mutex mutex=null;bool owned=false;
        try {
            if(Environment.OSVersion.Platform!=PlatformID.Win32NT) {Console.Error.WriteLine("Solo para Windows 10/11.");return 2;}
            SetCurrentProcessExplicitAppUserModelID("YuzVax.Optimization.v2");
            string sid=WindowsIdentity.GetCurrent().User.Value;
            mutex=new Mutex(false,"Local\\YuzVax.Optimization.v2."+sid);
            try{owned=mutex.WaitOne(0);}catch(AbandonedMutexException){owned=true;}
            if(!owned){
                foreach(var p in Process.GetProcesses())try{if(p.MainWindowTitle.StartsWith("OptimiZation",StringComparison.OrdinalIgnoreCase)){ShowWindow(p.MainWindowHandle,9);SetForegroundWindow(p.MainWindowHandle);p.Dispose();return 0;}}catch{}
                MessageBox(IntPtr.Zero,"OptimiZation ya está abierto. Termina o cierra esa sesión antes de iniciar otra. No se interrumpen reparaciones ni desinstaladores.","OptimiZation",0x40);return 0;
            }
            EnsureNormalDir(Root);CleanOldSessions();
            string id="sesion-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N").Substring(0,8);
            dir=Path.Combine(Root,id);EnsureNormalDir(dir);
            File.WriteAllText(Path.Combine(dir,".ow-session"),Process.GetCurrentProcess().Id.ToString());
            Extract(dir);request=Path.Combine(dir,"limpiar.confirmado");
            string documents=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments),"Optimization");
            EnsureNormalDir(documents);backup=Path.Combine(documents,id);EnsureNormalDir(backup);
            string windows=Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            string system=Environment.Is64BitOperatingSystem&&!Environment.Is64BitProcess?"Sysnative":"System32";
            string ps=Path.Combine(windows,system,"WindowsPowerShell\\v1.0\\powershell.exe");
            if(!File.Exists(ps))throw new FileNotFoundException("No se encuentra Windows PowerShell 5.1.",ps);
            var info=new ProcessStartInfo(ps,"-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \""+Path.Combine(dir,"Launch.ps1")+"\"");
            info.UseShellExecute=false;info.CreateNoWindow=true;info.WorkingDirectory=dir;
            info.EnvironmentVariables["OW_SESSION_ID"]=id;info.EnvironmentVariables["OW_BACKUP_DIR"]=backup;info.EnvironmentVariables["OW_CLOSE_REQUEST"]=request;
            info.EnvironmentVariables["OW_LAUNCHER_PATH"]=Assembly.GetExecutingAssembly().Location;
            int code;using(var child=Process.Start(info)){try{File.WriteAllText(Path.Combine(dir,".ow-session"),child.Id.ToString());}catch{}child.WaitForExit();code=child.ExitCode;}
            if(File.Exists(request)){
                if(!Clean(backup))MessageBox(IntPtr.Zero,"No se han podido limpiar todos los archivos propios de la sesión. Revisa: "+backup,"OptimiZation",0x30);
                RemoveEmptyRoot(documents);
            } else if(code!=0) MessageBox(IntPtr.Zero,"La app no terminó correctamente. Se han conservado sus copias y registro en: "+backup,"OptimiZation",0x30);
            return code;
        } catch(Exception ex) {MessageBox(IntPtr.Zero,"No se pudo iniciar OptimiZation Versión 2.\n"+ex.Message+"\nPrueba Fuentes\\Iniciar.bat si el problema persiste.","OptimiZation",0x10);return 1;}
        finally {
            if(dir!=null&&!Clean(dir))MessageBox(IntPtr.Zero,"Windows mantiene algún archivo temporal en uso. Puedes retirarlo tras cerrar la app: "+dir,"OptimiZation",0x30);
            RemoveEmptyRoot(Root);
            if(owned&&mutex!=null)mutex.ReleaseMutex();if(mutex!=null)mutex.Dispose();
        }
    }
}
