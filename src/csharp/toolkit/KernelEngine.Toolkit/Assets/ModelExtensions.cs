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
    /// Uploads <paramref name="model"/>'s textures, materials, and meshes to
    /// the renderer, then adds one <see cref="MeshRenderer"/> node per sub-mesh
    /// to <paramref name="nodeWorld"/>. Must be called from the render worker (i.e.
    /// inside a <c>SceneModule</c> setup callback) because GPU uploads are
    /// pinned to ke.render.
    /// </summary>
    public static IReadOnlyList<MeshRenderer> AddModel(
        this NodeWorld nodeWorld,
        IModel model,
        IRenderer renderer,
        string rootName = "Model")
    {
        var textures = new TextureHandle[model.Textures.Count];
        for (int i = 0; i < model.Textures.Count; i++)
        {
            var tex = model.Textures[i];
            textures[i] = renderer.CreateTexture(tex.Width, tex.Height, tex.Pixels.ToArray());
        }

        var materials = new MaterialHandle[model.Materials.Count];
        for (int i = 0; i < model.Materials.Count; i++)
        {
            var m       = model.Materials[i];
            var albedo  = m.AlbedoTextureIndex    >= 0 ? textures[m.AlbedoTextureIndex]    : default;
            var normal  = m.NormalMapTextureIndex >= 0 ? textures[m.NormalMapTextureIndex] : default;
            materials[i] = renderer.CreateMaterial(
                m.BaseColor,
                textureHandle:   albedo,
                metallic:        m.Metallic,
                roughness:       m.Roughness,
                normalMapHandle: normal);
        }

        var nodes = new List<MeshRenderer>(model.Meshes.Count);
        for (int i = 0; i < model.Meshes.Count; i++)
        {
            var src      = model.Meshes[i];
            var mesh     = renderer.CreateMesh(src.Vertices.ToArray(), src.Indices.ToArray());
            var material = src.MaterialIndex >= 0 ? materials[src.MaterialIndex] : default;
            var name     = string.IsNullOrEmpty(src.Name) ? $"{rootName}.Mesh_{i}" : $"{rootName}.{src.Name}";
            nodes.Add(nodeWorld.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }

    /// <summary>
    /// Render-v2 overload: uploads via <see cref="IRenderResources"/> instead of
    /// the legacy <see cref="IRenderer"/>. Converts the engine's <c>Vertex</c>
    /// layout (12 floats, tangent.w handedness) to <c>MeshVertex</c> (11 floats).
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
            textures[i] = resources.UploadTexture(tex.Width, tex.Height, tex.Pixels);
        }

        var materials = new MaterialHandle[model.Materials.Count];
        for (int i = 0; i < model.Materials.Count; i++)
        {
            var m      = model.Materials[i];
            var albedo = m.AlbedoTextureIndex    >= 0 ? textures[m.AlbedoTextureIndex]    : default;
            var normal = m.NormalMapTextureIndex >= 0 ? (TextureHandle?)textures[m.NormalMapTextureIndex] : null;
            materials[i] = resources.CreateMaterial(m.BaseColor, m.Metallic, m.Roughness, albedo, normal);
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
            var mesh     = resources.UploadMesh(converted, src.Indices);
            var material = src.MaterialIndex >= 0 ? materials[src.MaterialIndex] : default;
            var name     = string.IsNullOrEmpty(src.Name) ? $"{rootName}.Mesh_{i}" : $"{rootName}.{src.Name}";
            nodes.Add(nodeWorld.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }
}
