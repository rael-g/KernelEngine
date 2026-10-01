using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace KernelEngine.Common;

/// <summary>
/// Installs process-wide handlers that turn opaque native crashes (abort(),
/// SEH access violation, debug assertions, etc.) into a clear diagnostic
/// line on stderr plus a minidump file, instead of silent process death.
/// </summary>
public static class CrashHandler
{
    private static bool _registered;
    private static readonly object _lock = new();

    /// <summary>Registers the handlers if not already registered. Idempotent.</summary>
    public static void Register()
    {
        lock (_lock)
        {
            if (_registered) return;
            _registered = true;
        }

        if (OperatingSystem.IsWindows())
        {
            try { SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX); }
            catch {  }

            try { _set_abort_behavior_release(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT); } catch { }
            try { _set_abort_behavior_debug  (0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT); } catch { }

            try
            {
                _CrtSetReportMode(_CRT_WARN,   _CRTDBG_MODE_FILE);
                _CrtSetReportMode(_CRT_ERROR,  _CRTDBG_MODE_FILE);
                _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
            }
            catch {  }

            unsafe
            {
                delegate* unmanaged[Stdcall]<IntPtr, int> fp = &SehFilter;
                SetUnhandledExceptionFilter((IntPtr)fp);

                delegate* unmanaged[Cdecl]<int, void> sfp = &OnSigAbrt;
                try { signal_release(SIGABRT, (IntPtr)sfp); } catch { }
                try { signal_debug  (SIGABRT, (IntPtr)sfp); } catch { }
            }
        }

        AppDomain.CurrentDomain.UnhandledException += OnManagedUnhandled;
    }

    private static void OnManagedUnhandled(object sender, UnhandledExceptionEventArgs e)
    {
        try
        {
            var ex = e.ExceptionObject as Exception;
            Console.Error.WriteLine();
            Console.Error.WriteLine($"[FATAL] Unhandled managed exception ({(e.IsTerminating ? "terminating" : "non-terminating")}):");
            Console.Error.WriteLine(ex?.ToString() ?? e.ExceptionObject?.ToString() ?? "(unknown)");
            Console.Error.Flush();
        }
        catch {  }
    }

    private const uint _CALL_REPORTFAULT = 2;
    private const uint _WRITE_ABORT_MSG  = 1;
    private const int  SIGABRT           = 22;

    private const uint SEM_FAILCRITICALERRORS = 0x0001;
    private const uint SEM_NOGPFAULTERRORBOX  = 0x0002;
    private const uint SEM_NOOPENFILEERRORBOX = 0x8000;

    private const int _CRT_WARN          = 0;
    private const int _CRT_ERROR         = 1;
    private const int _CRT_ASSERT        = 2;
    private const int _CRTDBG_MODE_FILE  = 1;

    [DllImport("kernel32.dll")]
    private static extern uint SetErrorMode(uint uMode);

    [DllImport("ucrtbased.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int _CrtSetReportMode(int reportType, int reportMode);

    [DllImport("ucrtbase.dll", EntryPoint = "_set_abort_behavior", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint _set_abort_behavior_release(uint flags, uint mask);

    [DllImport("ucrtbased.dll", EntryPoint = "_set_abort_behavior", CallingConvention = CallingConvention.Cdecl)]
    private static extern uint _set_abort_behavior_debug(uint flags, uint mask);

    [DllImport("ucrtbase.dll", EntryPoint = "signal", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr signal_release(int signum, IntPtr handler);

    [DllImport("ucrtbased.dll", EntryPoint = "signal", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr signal_debug(int signum, IntPtr handler);

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void OnSigAbrt(int signum)
    {
        try
        {
            var t        = Thread.CurrentThread;
            string tname = string.IsNullOrEmpty(t.Name) ? $"tid={t.ManagedThreadId}" : $"\"{t.Name}\" (tid={t.ManagedThreadId})";
            string ts    = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff");

            Console.Error.WriteLine();
            Console.Error.WriteLine($"[FATAL] {ts} — process aborted (SIGABRT) on thread {tname}.");
            Console.Error.WriteLine("        A native plugin called abort(). The most recent stderr line(s) above usually");
            Console.Error.WriteLine("        carry the source file/line/message logged by the plugin before it aborted.");
            Console.Error.WriteLine("        If nothing precedes this banner, the plugin aborted without logging — that");
            Console.Error.WriteLine("        is a plugin bug (plugins must translate failures into ke_error + bool/null return).");
            Console.Error.WriteLine();
            Console.Error.WriteLine("Managed stack trace at the point of abort:");
            Console.Error.WriteLine(Environment.StackTrace);
            Console.Error.Flush();
        }
        catch {  }
        Environment.Exit(134);
    }

    [DllImport("kernel32.dll")]
    private static extern IntPtr SetUnhandledExceptionFilter(IntPtr lpTopLevelExceptionFilter);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentProcessId();

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("dbghelp.dll", SetLastError = true)]
    private static extern bool MiniDumpWriteDump(
        IntPtr hProcess, uint processId, IntPtr hFile, uint dumpType,
        IntPtr exceptionParam, IntPtr userStreamParam, IntPtr callbackParam);

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvStdcall) })]
    private static int SehFilter(IntPtr exceptionInfo)
    {
        int code = Marshal.ReadInt32(Marshal.ReadIntPtr(exceptionInfo));

        if (code == unchecked((int)0xE0434352)) return 0;

        string name = code switch
        {
            unchecked((int)0x80000003) => "STATUS_BREAKPOINT (debug assert / int3)",
            unchecked((int)0xC0000005) => "STATUS_ACCESS_VIOLATION (null/dangling pointer)",
            unchecked((int)0xC00000FD) => "STATUS_STACK_OVERFLOW",
            unchecked((int)0x40010005) => "DBG_CONTROL_C",
            unchecked((int)0x40010008) => "DBG_TERMINATE_THREAD",
            unchecked((int)0xC0000409) => "STATUS_STACK_BUFFER_OVERRUN / __fastfail (abort/__debugbreak)",
            _ => $"0x{code:X8}"
        };

        string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string dumpPath  = Path.GetFullPath($"crash_{timestamp}.dmp");

        try
        {
            using var fs = new FileStream(dumpPath, FileMode.Create, FileAccess.Write, FileShare.None);

            uint dumpType = 0x00000000 | 0x00000004 | 0x00000020 | 0x00001000;

            var exceptionPointers = Marshal.AllocHGlobal(Marshal.SizeOf<MINIDUMP_EXCEPTION_INFORMATION>());
            try
            {
                var mei = new MINIDUMP_EXCEPTION_INFORMATION
                {
                    ThreadId          = GetCurrentThreadId(),
                    ExceptionPointers = exceptionInfo,
                    ClientPointers    = false,
                };
                Marshal.StructureToPtr(mei, exceptionPointers, false);

                bool ok = MiniDumpWriteDump(
                    GetCurrentProcess(), GetCurrentProcessId(),
                    fs.SafeFileHandle.DangerousGetHandle(),
                    dumpType, exceptionPointers, IntPtr.Zero, IntPtr.Zero);

                Console.Error.WriteLine();
                Console.Error.WriteLine($"[FATAL] Native crash: {name}");
                Console.Error.WriteLine(ok
                    ? $"        Crash dump: {dumpPath}"
                    : $"        Failed to write crash dump (Win32 error {Marshal.GetLastWin32Error()})");
            }
            finally { Marshal.FreeHGlobal(exceptionPointers); }
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine();
            Console.Error.WriteLine($"[FATAL] Native crash: {name}");
            Console.Error.WriteLine($"        Dump generation failed: {ex.Message}");
        }

        Console.Error.Flush();
        Environment.Exit(1);
        return 0;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    private struct MINIDUMP_EXCEPTION_INFORMATION
    {
        public uint   ThreadId;
        public IntPtr ExceptionPointers;
        public bool   ClientPointers;
    }
}
