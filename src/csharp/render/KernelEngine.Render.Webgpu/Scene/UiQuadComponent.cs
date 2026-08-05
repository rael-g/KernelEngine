using System.Runtime.InteropServices;

namespace KernelEngine.Framework;

/// <summary>
/// A single screen-space UI quad, ECS-visible under the component name
/// "ui_quad". Producers (<see cref="Label"/>'s text shaping, arbitrary game
/// scripts) attach it to an entity via <see cref="KernelEngine.Runtime.SystemContext.Attach{T}"/>;
/// the "render.ui" native pass reads it through a declared query, resolved and
/// extracted by the runtime the same way every other render-phase pass
/// consumes sim-written data — no shared accumulator, no reset, no race.
/// </summary>
/// <remarks>
/// Field layout must match <c>UiQuadComponent</c> (<c>ui_module.zig</c>) byte
/// for byte — both sides register the component by the same name and share
/// its native storage directly.
/// </remarks>
[StructLayout(LayoutKind.Sequential)]
public struct UiQuadComponent
{
    /// <summary>Full generational texture handle bits; <c>uint.MaxValue</c> = built-in white.</summary>
    public uint TextureBits;
    public float DstX, DstY, DstW, DstH;
    public float U0, V0, U1, V1;
    /// <summary>Premultiplied alpha RGBA.</summary>
    public float R, G, B, A;

    /// <summary>A quad with zero size — "render.ui" skips it, so this hides a pooled slot.</summary>
    public static readonly UiQuadComponent Empty = default;
}
