using System.Numerics;

using global::KernelEngine.Common;

using KernelEngine.Result.Native;

namespace KernelEngine.Common.Native;

public static partial class NativeMethods
{
    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = (4294967295U);
}
