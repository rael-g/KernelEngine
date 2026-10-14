using System.Runtime.CompilerServices;
using KernelEngine.Common.Native;
using KernelEngine.Common;

namespace KernelEngine.Framework;

/// <summary>
/// Reinterprets between the two managed spellings of <c>ke_transform</c>: the one in managed
/// math types and the one of the P/Invoke surface. Both have the same layout.
/// </summary>
public static class TransformInterop
{
    /// <summary>Reinterprets the P/Invoke spelling as the managed one.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Transform FromNative(ke_transform t) => Unsafe.As<ke_transform, Transform>(ref t);

    /// <summary>Reinterprets the managed spelling as the P/Invoke one.</summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static ke_transform ToNative(Transform t) => Unsafe.As<Transform, ke_transform>(ref t);
}
