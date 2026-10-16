using System.Numerics;

using KernelEngine.Asset;
using KernelEngine.Render;

namespace KernelEngine.Framework;

/// <summary>
/// Uploads a <see cref="ModelData"/> to the GPU and attaches it to a scene as a flat collection of
/// <see cref="MeshRenderer"/> nodes, one per sub-mesh, named <c>{rootName}.{meshName}</c>.
/// </summary>
public static class ModelExtensions
{
    /// <summary>
    /// Uploads the textures, materials and meshes of <paramref name="model"/> through
    /// <paramref name="resources"/>, converting each vertex to <see cref="MeshVertex"/>, then adds
    /// one <see cref="MeshRenderer"/> node per sub-mesh to <paramref name="scriptHost"/> and
    /// returns them. It must run on the thread that owns GPU resource creation.
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
            var m = sourceMaterials[i];
            var albedo = m.AlbedoTextureIndex >= 0 ? textures[m.AlbedoTextureIndex] : default;
            var normal = m.NormalMapTextureIndex >= 0 ? (TextureHandle?)textures[m.NormalMapTextureIndex] : null;
            var baseColor = new Vector4(m.BaseColorR, m.BaseColorG, m.BaseColorB, m.BaseColorA);
            materials[i] = resources.CreateMaterial($"{rootName}#mat{i}", baseColor, m.Metallic, m.Roughness, albedo, normal);
        }

        var sourceMeshes = model.Meshes;
        var nodes = new List<MeshRenderer>(sourceMeshes.Length);
        for (int i = 0; i < sourceMeshes.Length; i++)
        {
            var src = sourceMeshes[i];
            var raw = src.Vertices;
            var converted = new MeshVertex[raw.Length];
            for (int j = 0; j < raw.Length; j++)
            {
                var v = raw[j];
                converted[j] = new MeshVertex(
                    new Vector3(v.X, v.Y, v.Z),
                    new Vector3(v.Nx, v.Ny, v.Nz),
                    new Vector2(v.U, v.V),
                    new Vector3(v.Tx, v.Ty, v.Tz));
            }
            var mesh = resources.UploadMesh($"{rootName}#mesh{i}", converted, src.Indices);
            var material = src.MaterialIndex >= 0 ? materials[src.MaterialIndex] : default;
            var name = string.IsNullOrEmpty(src.Name) ? $"{rootName}.Mesh_{i}" : $"{rootName}.{src.Name}";
            nodes.Add(scriptHost.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }
}
