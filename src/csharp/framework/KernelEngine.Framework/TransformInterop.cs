using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Internal helpers that reinterpret-cast between the managed <see cref="Transform"/> struct
/// (defined in KernelEngine.Kernel.Abstractions, pure managed) and the native <c>ke_transform</c>
/// struct (defined in the auto-generated bindings). Layout is identical by construction; this
/// class just makes the reinterpretation explicit at any callsite that has to cross the boundary.
/// </summary>
public static class TransformInterop
{
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static Transform FromNative(ke_transform t) => Unsafe.As<ke_transform, Transform>(ref t);

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static ke_transform ToNative(Transform t) => Unsafe.As<Transform, ke_transform>(ref t);
}
