using KernelEngine.Asset;
using KernelEngine.Asset.Assimp;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Pool;
using KernelEngine.TaskPool.Enki;

using Xunit;

namespace KernelEngine.Integration.Tests;

public class LoadingAModelThroughThePoolIo
{
    [Fact]
    public void AGltfAndTheBufferItNamesAreReadIntoMeshesAndMaterials()
    {
        using var pool = new EnkiTaskPool(null, uint.MaxValue);
        using var files = new StdFileSystem(null, ".");
        using var io = new PoolIo(null, pool, files);
        using var loader = new AssimpAssetLoader(null, io);

        using var model = loader.LoadModel(Path.Combine(AppContext.BaseDirectory, "assets", "Box.gltf"));

        Assert.NotEmpty(model.Data.Meshes.ToArray());
        Assert.NotEmpty(model.Data.Materials.ToArray());
    }
}
