using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Read-only view of a PBR material loaded as part of an <see cref="IModel"/>.
/// Texture indices refer into <see cref="IModel.Textures"/>; <c>-1</c> means no texture.
/// </summary>
public interface IModelMaterial
{
    /// <summary>Material name.</summary>
    string Name { get; }

    /// <summary>PBR base color (linear RGBA).</summary>
    Vector4 BaseColor { get; }

    /// <summary>PBR metallic factor (0..1).</summary>
    float Metallic { get; }

    /// <summary>PBR roughness factor (0..1).</summary>
    float Roughness { get; }

    /// <summary>Index into <see cref="IModel.Textures"/> for the albedo map; <c>-1</c> = none.</summary>
    int AlbedoTextureIndex { get; }

    /// <summary>Index into <see cref="IModel.Textures"/> for the normal map; <c>-1</c> = none.</summary>
    int NormalMapTextureIndex { get; }
}
