# Identidad propia de ventana y barra de tareas. Código propio, MIT.
if (-not ('OWWindowIdentity' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OWWindowIdentity {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
    [DllImport("shell32.dll")] static extern int SHGetPropertyStoreForWindow(IntPtr hwnd, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern IntPtr LoadImage(IntPtr h, string file, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] static extern bool DestroyIcon(IntPtr icon);
    [StructLayout(LayoutKind.Sequential)] struct PropertyKey { public Guid fmtid; public uint pid; }
    [StructLayout(LayoutKind.Explicit, Size=24)] struct PropVariant { [FieldOffset(0)] public ushort vt; [FieldOffset(8)] public IntPtr ptr; }
    [ComImport,Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPropertyStore {
        [PreserveSig] int GetCount(out uint count);
        [PreserveSig] int GetAt(uint i, out PropertyKey key);
        [PreserveSig] int GetValue(ref PropertyKey key, out PropVariant value);
        [PreserveSig] int SetValue(ref PropertyKey key, ref PropVariant value);
        [PreserveSig] int Commit();
    }
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr hwnd, int attribute, ref int value, int size);
    public static void ApplyAppearance(IntPtr hwnd) {
        try {
            int dark=1;
            if(DwmSetWindowAttribute(hwnd,20,ref dark,4)<0) DwmSetWindowAttribute(hwnd,19,ref dark,4);
            int round=2; DwmSetWindowAttribute(hwnd,33,ref round,4); // Windows 11: DWMWCP_ROUND.
            int background=0x00140E0B; // COLORREF BGR: #0B0E14. Sin franja clara del DWM.
            DwmSetWindowAttribute(hwnd,34,ref background,4); // DWMWA_BORDER_COLOR.
            DwmSetWindowAttribute(hwnd,35,ref background,4); // DWMWA_CAPTION_COLOR.
        } catch(DllNotFoundException) {} catch(EntryPointNotFoundException) {}
        // Atributos no admitidos en Windows 10 fallan sin impedir abrir la app.
    }
    static IntPtr big, small;
    static void Set(IPropertyStore store, uint pid, string text) {
        var key=new PropertyKey {fmtid=new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),pid=pid};
        var value=new PropVariant {vt=31,ptr=Marshal.StringToCoTaskMemUni(text)};
        try {Marshal.ThrowExceptionForHR(store.SetValue(ref key, ref value));} finally {Marshal.FreeCoTaskMem(value.ptr);}
    }
    public static void Apply(IntPtr hwnd, string icon, string exe) {
        small=LoadImage(IntPtr.Zero,icon,1,16,16,16);big=LoadImage(IntPtr.Zero,icon,1,48,48,16);
        if(small!=IntPtr.Zero) SendMessage(hwnd,0x80,IntPtr.Zero,small);
        if(big!=IntPtr.Zero) SendMessage(hwnd,0x80,new IntPtr(1),big);
        IPropertyStore store; var iid=new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
        Marshal.ThrowExceptionForHR(SHGetPropertyStoreForWindow(hwnd,ref iid,out store));
        try {
            if(!String.IsNullOrEmpty(exe)) {Set(store,2,"\""+exe+"\"");Set(store,3,exe+",0");Set(store,4,"OptimiZation Versión 2");}
            Set(store,5,"YuzVax.Optimization.v2");
            Marshal.ThrowExceptionForHR(store.Commit());
        } finally {Marshal.ReleaseComObject(store);}
    }
    public static void Release() {if(small!=IntPtr.Zero) DestroyIcon(small);if(big!=IntPtr.Zero) DestroyIcon(big);small=big=IntPtr.Zero;}
}
'@
}
[void][OWWindowIdentity]::SetCurrentProcessExplicitAppUserModelID('YuzVax.Optimization.v2')
