using System.Numerics;
using KernelEngine.Common;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Backend contract for path resolution (<c>res://...</c>) into typed CPU-side asset data
/// (texture pixels, mesh CPU buffers, material specs). Sugar layer (<c>Assets</c>,
/// <c>NodeTypeRegistrar</c>) consumes this; the unsafe wrapper lives in
/// <c>KernelEngine.Framework.Legacy.Native</c>.
/// </summary>
public interface IAssetResolverBackend : IDisposable
{
    /// <summary>Decodes an image at <paramref name="path"/> into RGBA8 pixel data.</summary>
    TextureBuffer? ResolveTexture(string path);

    /// <summary>
    /// Bakes a built-in mesh primitive (<c>res://primitives/{quad|plane|cube|sphere}</c>) into
    /// CPU vertex/index buffers. Returns null for unknown shapes.
    /// </summary>
    MeshBuffer? ResolveMesh(string path);

    /// <summary>Parses a <c>.material</c> TOML file. Returns null on missing file.</summary>
    MaterialSpec? ResolveMaterial(string path);
}

/// <summary>Decoded RGBA8 pixel buffer plus its dimensions.</summary>
public sealed record TextureBuffer(uint Width, uint Height, byte[] Pixels);

/// <summary>CPU mesh data: vertex array + index array.</summary>
public sealed record MeshBuffer(KernelEngine.Common.Vertex[] Vertices, ushort[] Indices);

/// <summary>Material file spec: PBR parameters + path-string texture references.</summary>
public sealed record MaterialSpec(
    Vector4 BaseColor,
    float   Metallic,
    float   Roughness,
    string? AlbedoPath,
    string? NormalPath);
