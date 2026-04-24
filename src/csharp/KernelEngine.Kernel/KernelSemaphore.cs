using KernelEngine.Threading.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for a native counting semaphore (<c>ke_semaphore</c>).
/// </summary>
public sealed unsafe class KernelSemaphore : IDisposable
{
    private ke_semaphore* _native;
    private Allocator     _alloc;

    private KernelSemaphore(ke_semaphore* native, Allocator alloc)
    {
        _native = native;
        _alloc  = alloc;
    }

    /// <summary>Creates a counting semaphore with the given <paramref name="initial"/> count.</summary>
    public static KernelSemaphore Create(Allocator alloc, uint initial = 0)
    {
        ke_semaphore* native;
        KernelException.ThrowIfFailed(
            NativeMethods.semaphore_create(alloc.Native, initial, &native));
        return new KernelSemaphore(native, alloc);
    }

    /// <summary>Increments the count, unblocking one waiting thread.</summary>
    public void Signal()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        NativeMethods.semaphore_signal(_native);
    }

    /// <summary>Decrements the count, blocking if it is zero.</summary>
    public void Wait()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        NativeMethods.semaphore_wait(_native);
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            NativeMethods.semaphore_destroy(_native, _alloc.Native);
            _native = null;
        }
    }
}
