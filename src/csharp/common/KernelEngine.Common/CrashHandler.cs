using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace KernelEngine.Kernel;

/// <summary>
/// Installs process-wide handlers that turn opaque native crashes (abort(),
/// SEH access violation, bgfx debug assertions, etc.) into a clear diagnostic
/// line on stderr plus a minidump file, instead of silent process death.
/// </summary>
/// <remarks>
/// Register once at process startup before any native code that might assert
/// or crash. Subsequent Register calls are no-ops (idempotent).
/// <para>
/// On Windows the handler chain is:
/// <list type="number">
///   <item><c>_set_abort_behavior</c> — routes <c>abort()</c> through Windows Error Reporting,
///         which propagates as an SEH exception instead of dying silently.</item>
///   <item><c>SetUnhandledExceptionFilter</c> — catches the SEH (or any other native fault)
///         before the OS kills the process, prints a useful diagnostic to stderr.</item>
///   <item><c>AppDomain.UnhandledException</c> — catches any managed exception that bubbled
///         past every try/catch, prints the full stack trace.</item>
/// </list>
/// </para>
/// </remarks>
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

        // Route abort() through Windows Error Reporting so it surfaces as an
        // SEH exception (caught below) instead of silently terminating.
        if (OperatingSystem.IsWindows())
        {
            // (1) Kill every Windows-level error dialog. SEM_NOGPFAULTERRORBOX
            // covers GPF + Watson; SEM_FAILCRITICALERRORS covers missing-DLL
            // popups; SEM_NOOPENFILEERRORBOX covers file open dialogs. Combined,
            // no native crash can ever block on a modal dialog again.
            try { SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX); }
            catch { /* non-fatal */ }

            // (2) Silence the CRT's own "abnormal program termination" message
            // AND its WER call. Done on BOTH release (ucrtbase) and debug
            // (ucrtbased) CRTs — each has independent state, and native plugins
            // compiled in Debug link to ucrtbased while C# itself uses ucrtbase.
            try { _set_abort_behavior_release(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT); } catch { }
            try { _set_abort_behavior_debug  (0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT); } catch { }

            // (3) Debug builds load ucrtbased.dll, whose default behavior on
            // abort()/assert is the modal "Debug Error! Program: ... abort()
            // has been called [Abort][Retry][Ignore]" dialog. Redirecting every
            // report category to FILE (stderr) bypasses the dialog entirely so
            // our signal handler can run instead. ucrtbased only exists in
            // debug, hence the try/catch.
            try
            {
                _CrtSetReportMode(_CRT_WARN,   _CRTDBG_MODE_FILE);
                _CrtSetReportMode(_CRT_ERROR,  _CRTDBG_MODE_FILE);
                _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
            }
            catch { /* release build — ucrtbased not loaded, fine */ }

            unsafe
            {
                delegate* unmanaged[Stdcall]<IntPtr, int> fp = &SehFilter;
                SetUnhandledExceptionFilter((IntPtr)fp);

                // Defense in depth: hook SIGABRT directly on BOTH CRTs. Each
                // CRT has its own signal table — abort() in ucrtbased only
                // dispatches handlers registered through ucrtbased's signal(),
                // and vice versa. The CRT runs the handler before any default
                // abort behavior, so even if everything else fails we still
                // print the [FATAL] line.
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
        catch { /* never let the handler itself crash */ }
    }

    // ── SEH catch (Windows) ─────────────────────────────────────────────────

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

    // ucrtbase.dll is the Universal CRT used by every MSVC-compiled binary in
    // this engine (bgfx, flecs, our plugins). Registering against the legacy
    // msvcrt.dll would set handlers on a CRT instance nobody links against, so
    // abort()/raise() from native code would still terminate silently.
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
        catch { /* never let the handler itself crash */ }
        Environment.Exit(134); // 128 + SIGABRT, conventional shell exit code
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

        // 0xE0434352 ('MCR\E0') is the CLR's own managed-exception SEH code —
        // let it through so the CLR can unwind it.
        if (code == unchecked((int)0xE0434352)) return 0;

        // Friendly names for the codes the user is most likely to hit.
        string name = code switch
        {
            unchecked((int)0x80000003) => "STATUS_BREAKPOINT (bgfx debug assert / int3)",
            unchecked((int)0xC0000005) => "STATUS_ACCESS_VIOLATION (null/dangling pointer)",
            unchecked((int)0xC00000FD) => "STATUS_STACK_OVERFLOW",
            unchecked((int)0x40010005) => "DBG_CONTROL_C",
            unchecked((int)0x40010008) => "DBG_TERMINATE_THREAD",
            // abort() routed through _CALL_REPORTFAULT raises this:
            unchecked((int)0xC0000409) => "STATUS_STACK_BUFFER_OVERRUN / __fastfail (abort/__debugbreak)",
            _ => $"0x{code:X8}"
        };

        string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss");
        string dumpPath  = Path.GetFullPath($"crash_{timestamp}.dmp");

        try
        {
            using var fs = new FileStream(dumpPath, FileMode.Create, FileAccess.Write, FileShare.None);

            // MiniDumpNormal + WithHandleData + WithUnloadedModules + WithThreadInfo
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
