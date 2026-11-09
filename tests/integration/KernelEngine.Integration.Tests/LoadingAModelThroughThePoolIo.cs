using KernelEngine.Asset;
using KernelEngine.Asset.Assimp;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Pool;
using KernelEngine.TaskPool.Enki;

using Microsoft.Extensions.DependencyInjection;

using Xunit;

namespace KernelEngine.Integration.Tests;

public class LoadingAModelThroughThePoolIo
{
    [Fact]
    public void AGltfAndTheBufferItNamesAreReadIntoMeshesAndMaterials()
    {
        using var services = new ServiceCollection()
            .AddEnkiTaskPool(workerCount: uint.MaxValue)
            .AddStdFileSystem(root: ".")
            .AddPoolIo()
            .AddAssimpAssetLoader()
            .BuildServiceProvider();
        var loader = services.GetRequiredService<AssimpAssetLoader>();

        using var model = loader.LoadModel(Path.Combine(AppContext.BaseDirectory, "assets", "Box.gltf"));

        Assert.NotEmpty(model.Data.Meshes.ToArray());
        Assert.NotEmpty(model.Data.Materials.ToArray());
    }
}
