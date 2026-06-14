using KernelEngine.Kernel;

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
    /// to <paramref name="tree"/>. Must be called from the render worker (i.e.
    /// inside a <c>SceneModule</c> setup callback) because GPU uploads are
    /// pinned to ke.render.
    /// </summary>
    public static IReadOnlyList<MeshRenderer> AddModel(this Tree tree, IModel model, string rootName = "Model")
    {
        var renderer = tree.Renderer;

        var textures = new TextureHandle[model.Textures.Count];
        for (int i = 0; i < model.Textures.Count; i++)
        {
            var tex = model.Textures[i];
            textures[i] = renderer.CreateTexture(tex.Width, tex.Height, tex.Pixels.ToArray()).Value;
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
                normalMapHandle: normal).Value;
        }

        var nodes = new List<MeshRenderer>(model.Meshes.Count);
        for (int i = 0; i < model.Meshes.Count; i++)
        {
            var src      = model.Meshes[i];
            var mesh     = renderer.CreateMesh(src.Vertices.ToArray(), src.Indices.ToArray()).Value;
            var material = src.MaterialIndex >= 0 ? materials[src.MaterialIndex] : default;
            var name     = string.IsNullOrEmpty(src.Name) ? $"{rootName}.Mesh_{i}" : $"{rootName}.{src.Name}";
            nodes.Add(tree.AddNode(new MeshRenderer { MeshHandle = mesh, MaterialHandle = material }, name));
        }
        return nodes;
    }
}
