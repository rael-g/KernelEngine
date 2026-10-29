using KernelEngine.Common;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native input actions map. This part declares the constructor that calls
/// the native factory; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class NativeInputActions
{
    /// <summary>Creates a native input-actions instance that loads its file through <paramref name="io"/>.</summary>
    /// <exception cref="InvalidOperationException">The native factory fails.</exception>
    /// <param name="io">The io the file is read through, borrowed; must outlive the instance.</param>
    public NativeInputActions(KernelEngine.Io.INativeIo io) : this(Create(io))
    {
    }

    private static ke_input_actions_handle Create(KernelEngine.Io.INativeIo io)
    {
        ArgumentNullException.ThrowIfNull(io);
        ke_input_actions_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.input_actions_create(io.Native, &handle), "ke_input_actions_create");
        return handle;
    }
}
