using System.Runtime.InteropServices;
using System.Text;

using KernelEngine.Asset;
using KernelEngine.Asset.Native;
using KernelEngine.Common;
using KernelEngine.Common.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Text;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed projection of <see cref="ke_material_spec"/>, returned by
/// <see cref="AssetResolver.ResolveMaterialSpec"/>. It holds no native memory.
/// </summary>
public sealed record ResolvedMaterial
{
    /// <summary>RGBA base color, components in [0, 1].</summary>
    public required float[] BaseColor { get; init; }

    /// <summary>Metallic factor, [0, 1].</summary>
    public required float Metallic { get; init; }

    /// <summary>Roughness factor, [0, 1].</summary>
    public required float Roughness { get; init; }

    /// <summary>Albedo texture path; empty when the material has none.</summary>
    public required string AlbedoPath { get; init; }

    /// <summary>Normal-map texture path; empty when the material has none.</summary>
    public required string NormalPath { get; init; }

    internal static unsafe ResolvedMaterial FromNative(KernelEngine.Render.MaterialSpec spec)
    {
        return new ResolvedMaterial
        {
            BaseColor = [spec.BaseColor[0], spec.BaseColor[1], spec.BaseColor[2], spec.BaseColor[3]],
            Metallic = spec.Metallic,
            Roughness = spec.Roughness,
            AlbedoPath = new string((sbyte*)&spec.AlbedoPathBytes),
            NormalPath = new string((sbyte*)&spec.NormalPathBytes),
        };
    }
}
