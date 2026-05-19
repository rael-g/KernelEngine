using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for a native kernel thread (<c>ke_thread</c>).
/// The thread starts immediately on construction and must be joined before disposal.
/// </summary>
public sealed unsafe class KernelThread : IKernelThread
{
    private ke_thread*  _native;
    private Allocator   _alloc;

    /// <inheritdoc/>
    public string Name { get; }

    private KernelThread(ke_thread* native, Allocator alloc, string name)
    {
        _native = native;
        _alloc  = alloc;
        Name    = name;
    }

    /// <summary>
    /// Creates and immediately starts a kernel thread named <paramref name="name"/>.
    /// The thread runs <paramref name="action"/> and terminates when it returns.
    /// </summary>
    /// <param name="alloc">Allocator used for the native handle.</param>
    /// <param name="name">Thread name. Stored in TLS and (if <paramref name="devPlatform"/> is provided)
    /// also forwarded to the OS for debugger/profiler visibility.</param>
    /// <param name="action">Thread body.</param>
    /// <param name="devPlatform">Optional. When provided, the thread name becomes visible to debuggers/profilers.</param>
    public static KernelThread Create(Allocator alloc, string name, Action action, DevPlatform? devPlatform = null)
    {
        var actionHandle = GCHandle.Alloc(action);

        var nameBytes = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_thread_params
            {
                name         = (sbyte*)nameBytes,
                func         = &ThreadEntryPoint,
                user_data    = (void*)GCHandle.ToIntPtr(actionHandle),
                dev_platform = devPlatform != null ? devPlatform.Native : null,
            };

            ke_thread* native;
            KernelException.ThrowIfFailed(NativeMethods.thread_std_create(alloc.Native, &desc, &native).ToManaged());

            return new KernelThread(native, alloc, name);
        }
        finally
        {
            Marshal.FreeHGlobal(nameBytes);
        }
    }

    /// <summary>Blocks the calling thread until this thread finishes.</summary>
    public void Join()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->join(_native);
    }

    /// <summary>
    /// Blocks until the thread finishes or the timeout expires.
    /// </summary>
    /// <param name="timeoutMs">Timeout in milliseconds.</param>
    /// <returns>true if the thread finished, false if it timed out.</returns>
    public bool Join(int timeoutMs)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->join_timeout(_native, (uint)timeoutMs) != 0;
    }

    /// <summary>Sets the name of the calling thread (e.g. the main thread).</summary>
    public static void SetCurrentName(string name)
    {
        var nameBytes = Marshal.StringToHGlobalAnsi(name);
        try   { NativeMethods.thread_set_current_name((sbyte*)nameBytes); }
        finally { Marshal.FreeHGlobal(nameBytes); }
    }

    /// <summary>Returns the name of the calling thread.</summary>
    public static string GetCurrentName()
    {
        var ptr = NativeMethods.thread_get_current_name();
        return Marshal.PtrToStringAnsi((IntPtr)ptr) ?? "unknown";
    }

    /// <summary>
    /// Asserts that the calling thread matches the expected name.
    /// Throws an <see cref="InvalidOperationException"/> if the affinity contract is violated.
    /// </summary>
    public static void AssertCurrent(string expectedName)
    {
#if DEBUG
        var current = GetCurrentName();
        if (current != expectedName)
        {
            throw new InvalidOperationException(
                $"Thread affinity violation: Expected '{expectedName}', but current thread is '{current}'.");
        }
        // Also call native assertion to be safe and cover native callers.
        var nameBytes = Marshal.StringToHGlobalAnsi(expectedName);
        try { NativeMethods.thread_assert_current((sbyte*)nameBytes); }
        finally { Marshal.FreeHGlobal(nameBytes); }
#endif
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native, _alloc.Native);
            _native = null;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void ThreadEntryPoint(void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        try
        {
            var action = (Action)handle.Target!;
            action();
        }
        finally
        {
            handle.Free();
        }
    }
}
