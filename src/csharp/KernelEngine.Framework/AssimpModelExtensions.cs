using KernelEngine.Asset.Assimp;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

public static class AssimpModelExtensions
{
    /// <summary>
    /// Uploads model data to the GPU and adds it to the scene.
    /// </summary>
    public static async Task<Node> AddToSceneAsync(this ModelData model, World world, IResourceFactory resources, string name = "Model")
    {
        var root = world.Scene.AddNode(name);

        // 1. Create GPU textures
        var gpuTextures = new TextureHandle[model.Textures.Length];
        for (int i = 0; i < model.Textures.Length; i++)
        {
            var tex = model.Textures[i];
            gpuTextures[i] = await resources.CreateTextureAsync(tex.Width, tex.Height, tex.Pixels.ToArray());
        }

        // 2. Create GPU materials
        var gpuMaterials = new MaterialHandle[model.Materials.Length];
        for (int i = 0; i < model.Materials.Length; i++)
        {
            var mat = model.Materials[i];
            var albedo = mat.AlbedoTextureIndex >= 0 ? gpuTextures[mat.AlbedoTextureIndex] : default;
            var normal = mat.NormalMapTextureIndex >= 0 ? gpuTextures[mat.NormalMapTextureIndex] : default;
            
            gpuMaterials[i] = await resources.CreateMaterialAsync(
                mat.BaseColor, 
                textureHandle: albedo,
                metallic: mat.Metallic,
                roughness: mat.Roughness,
                normalMapHandle: normal);
        }

        // 3. Create GPU meshes and add nodes
        for (int i = 0; i < model.Meshes.Length; i++)
        {
            var meshData = model.Meshes[i];
            var gpuMesh = await resources.CreateMeshAsync(meshData.Vertices.ToArray(), meshData.Indices.ToArray());
            
            var material = meshData.MaterialIndex >= 0 ? gpuMaterials[meshData.MaterialIndex] : default;

            var meshNode = world.Scene.AddNode(
                new MeshNode { MeshHandle = gpuMesh, MaterialHandle = material },
                meshData.Name,
                parent: root);
        }

        return root;
    }
}
