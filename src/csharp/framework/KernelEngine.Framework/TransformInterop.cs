using System.Runtime.CompilerServices;
using KernelEngine.Common.Native;
using KernelEngine.Common;

namespace KernelEngine.Framework;

/// <summary>
/// Reinterprets between the two spellings of <c>ke_transform</c>: the one kabic emits for
/// game code, in managed math types, and the one ClangSharp emits for the P/Invoke surface.
/// Both are generated from the same declaration, so a field added there reaches both or
/// neither; this makes the crossing explicit at the callsites that have to make it.
/// </summary>
public static class TransformInterop
{
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Transform FromNative(ke_transform t) => Unsafe.As<ke_transform, Transform>(ref t);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static ke_transform ToNative(Transform t) => Unsafe.As<Transform, ke_transform>(ref t);
}
