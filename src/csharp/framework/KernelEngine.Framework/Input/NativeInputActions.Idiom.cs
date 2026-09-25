using KernelEngine.Common;
using KernelEngine.Common.Native;

namespace KernelEngine.Framework;

/// <summary>
/// The one part of <see cref="NativeInputActions"/> that is not a direct image of the C
/// ABI: the constructor's factory call. Everything that mirrors the vtable 1:1 is
/// generated in <c>Generated/NativeInputActions.g.cs</c>.
/// </summary>
public unsafe partial class NativeInputActions
{
    /// <summary>Creates a native input-actions instance.</summary>
    public NativeInputActions() : this(Create())
    {
    }

    private static ke_input_actions_handle Create()
    {
        ke_error* err = null;
        var handle = KernelEngine.Framework.Native.NativeMethods.input_actions_create(&err);
        if (handle.@ref == null) throw KernelError.FromNative(err, "input_actions_create");
        return handle;
    }
}
