using System.Runtime.InteropServices;

namespace KernelEngine.Interop;

/// <summary>
/// The reference count of one native object, as a <see cref="SafeHandle"/>: the wrapper that
/// created the object holds the first reference and disposes it, every wrapper created over it as a
/// dependency adds one with <see cref="SafeHandle.DangerousAddRef"/> and drops it with
/// <see cref="SafeHandle.DangerousRelease"/>, and the teardown runs once, when the last is dropped.
/// </summary>
public sealed class NativeOwner : SafeHandle
{
    private readonly Action _teardown;

    /// <summary>Holds the first reference to an object that <paramref name="teardown"/> destroys.</summary>
    public NativeOwner(Action teardown) : base(new IntPtr(1), ownsHandle: true) => _teardown = teardown;

    /// <inheritdoc/>
    public override bool IsInvalid => false;

    /// <inheritdoc/>
    protected override bool ReleaseHandle()
    {
        _teardown();
        return true;
    }
}
