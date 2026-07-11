using System.Numerics;
using KernelEngine.Render;
using KernelEngine.Asset;


namespace KernelEngine.Framework;

/// <summary>
/// Helpers that upload an <see cref="IModel"/> (returned by an
/// <see cref="IAssetLoader"/>) to the GPU and attach it to the scene as a
/// flat collection of <see cref="MeshRenderer"/> nodes. Each sub-mesh becomes
/// its own node named <c>{rootName}.{meshName}</c>.
/// </summary>
public static class ModelExtensions
{
    /// <summary>
    /// Uploads <paramref name="model"/>'s textures, materials, and meshes via
    /// <see cref="IRenderResources"/>, then adds one <see cref="MeshRenderer"/> node per
    /// sub-mesh to <paramref name="nodeWorld"/>. Converts the engine's <c>Vertex</c>
    /// layout (12 floats, tangent.w handedness) to <c>MeshVertex</c> (11 floats).
    /// Must be called from the render worker, because GPU uploads are pinned to ke.render.
    /// </summary>
    public static IReadOnlyList<MeshRenderer> AddModel(
        this NodeWorld nodeWorld,
        IModel model,
        IRenderResources resources,
        string rootName = "Model")
    {
        var textures = new TextureHandle[model.Textures.Count];
        for (int i = 0; i < model.Textures.Count; i++)
        {
            var tex = model.Textures[i];
            // A texture loaded from its own file dedups by that path (shared across
            // any model referencing the same file); an embedded texture has no path
            // identity of its own, so it keys per model instance instead.
            var texKey = string.IsNullOrEmpty(tex.Path) ? $"{rootName}#tex{i}" : tex.Path;
            textures[i] = resources.UploadTexture(texKey, tex.Width, tex.Height, tex.Pixels);
        }

        var materials = new MaterialHandle[model.Materials.Count];
        for (int i = 0; i < model.Materials.Count; i++)
        {
            var m      = model.Materials[i];
            var albedo = m.AlbedoTextureIndex    >= 0 ? textures[m.AlbedoTextureIndex]    : default;
            var normal = m.NormalMapTextureIndex >= 0 ? (TextureHandle?)textures[m.NormalMapTextureIndex] : null;
            materials[i] = resources.CreateMaterial($"{rootName}#mat{i}", m.BaseColor, m.Metallic, m.Roughness, albedo, normal);
        }

        var nodes = new List<MeshRenderer>(model.Meshes.Count);
        for (int i = 0; i < model.Meshes.Count; i++)
        {
            var src  = model.Meshes[i];
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
            nodes.Add(nodeWorld.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }
}
