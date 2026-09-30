using System.Numerics;
using KernelEngine.Render;
using KernelEngine.Asset;

namespace KernelEngine.Framework;

/// <summary>
/// Helpers that upload a <see cref="ModelData"/> (read from an <see cref="IModel"/> an
/// <see cref="IAssetLoader"/> answered with) to the GPU and attach it to the scene as a
/// flat collection of <see cref="MeshRenderer"/> nodes. Each sub-mesh becomes its own node
/// named <c>{rootName}.{meshName}</c>.
/// </summary>
public static class ModelExtensions
{
    /// <summary>
    /// Uploads <paramref name="model"/>'s textures, materials, and meshes via
    /// <see cref="IRenderResources"/>, then adds one <see cref="MeshRenderer"/> node per
    /// sub-mesh to <paramref name="scriptHost"/>. Converts the engine's <c>Vertex</c>
    /// layout (12 floats, tangent.w handedness) to <c>MeshVertex</c> (11 floats).
    /// Must be called from the render worker, because GPU uploads are pinned to ke.render.
    /// </summary>
    public static IReadOnlyList<MeshRenderer> AddModel(
        this ScriptHost scriptHost,
        ModelData model,
        IRenderResources resources,
        string rootName = "Model")
    {
        var sourceTextures = model.Textures;
        var textures = new TextureHandle[sourceTextures.Length];
        for (int i = 0; i < sourceTextures.Length; i++)
        {
            var tex = sourceTextures[i];
            var texKey = string.IsNullOrEmpty(tex.Path) ? $"{rootName}#tex{i}" : tex.Path;
            textures[i] = resources.UploadTexture(texKey, tex.Width, tex.Height, tex.Pixels);
        }

        var sourceMaterials = model.Materials;
        var materials = new MaterialHandle[sourceMaterials.Length];
        for (int i = 0; i < sourceMaterials.Length; i++)
        {
            var m         = sourceMaterials[i];
            var albedo    = m.AlbedoTextureIndex    >= 0 ? textures[m.AlbedoTextureIndex]    : default;
            var normal    = m.NormalMapTextureIndex >= 0 ? (TextureHandle?)textures[m.NormalMapTextureIndex] : null;
            var baseColor = new Vector4(m.BaseColorR, m.BaseColorG, m.BaseColorB, m.BaseColorA);
            materials[i] = resources.CreateMaterial($"{rootName}#mat{i}", baseColor, m.Metallic, m.Roughness, albedo, normal);
        }

        var sourceMeshes = model.Meshes;
        var nodes = new List<MeshRenderer>(sourceMeshes.Length);
        for (int i = 0; i < sourceMeshes.Length; i++)
        {
            var src  = sourceMeshes[i];
            var raw  = src.Vertices;
            var converted = new MeshVertex[raw.Length];
            for (int j = 0; j < raw.Length; j++)
            {
                var v = raw[j];
                converted[j] = new MeshVertex(
                    new Vector3(v.X,  v.Y,  v.Z),
                    new Vector3(v.Nx, v.Ny, v.Nz),
                    new Vector2(v.U,  v.V),
                    new Vector3(v.Tx, v.Ty, v.Tz));
            }
            var mesh     = resources.UploadMesh($"{rootName}#mesh{i}", converted, src.Indices);
            var material = src.MaterialIndex >= 0 ? materials[src.MaterialIndex] : default;
            var name     = string.IsNullOrEmpty(src.Name) ? $"{rootName}.Mesh_{i}" : $"{rootName}.{src.Name}";
            nodes.Add(scriptHost.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }
}
