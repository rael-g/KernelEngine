using KernelEngine.Common;

namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native input actions map. This part declares the constructor that calls
/// the native factory; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class NativeInputActions
{
    /// <summary>Creates a native input-actions instance.</summary>
    /// <exception cref="InvalidOperationException">The native factory fails.</exception>
    public NativeInputActions() : this(Create())
    {
    }

    private static ke_input_actions_handle Create()
    {
        ke_input_actions_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.input_actions_create(&handle), "ke_input_actions_create");
        return handle;
    }
}
