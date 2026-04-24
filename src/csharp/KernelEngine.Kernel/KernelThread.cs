using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Threading.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for a native kernel thread (<c>ke_thread</c>).
/// The thread starts immediately on construction and must be joined before disposal.
/// </summary>
public sealed unsafe class KernelThread : IDisposable
{
    private ke_thread*  _native;
    private Allocator   _alloc;

    private KernelThread(ke_thread* native, Allocator alloc)
    {
        _native = native;
        _alloc  = alloc;
    }

    /// <summary>
    /// Creates and immediately starts a kernel thread named <paramref name="name"/>.
    /// The thread runs <paramref name="action"/> and terminates when it returns.
    /// </summary>
    public static KernelThread Create(Allocator alloc, string name, Action action)
    {
        var actionHandle = GCHandle.Alloc(action);

        var nameBytes = Marshal.StringToHGlobalAnsi(name);
        try
        {
            var desc = new ke_thread_desc
            {
                name          = (sbyte*)nameBytes,
                func          = &ThreadEntryPoint,
                user_data     = (void*)GCHandle.ToIntPtr(actionHandle),
                affinity_mask = 0,
            };

            ke_thread* native;
            KernelException.ThrowIfFailed(
                NativeMethods.thread_std_create(alloc.Native, &desc, &native));

            return new KernelThread(native, alloc);
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

    /// <summary>Sets the name of the calling thread (e.g. the main thread).</summary>
    public static void SetCurrentName(string name)
    {
        var nameBytes = Marshal.StringToHGlobalAnsi(name);
        try   { NativeMethods.thread_set_current_name((sbyte*)nameBytes); }
        finally { Marshal.FreeHGlobal(nameBytes); }
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
