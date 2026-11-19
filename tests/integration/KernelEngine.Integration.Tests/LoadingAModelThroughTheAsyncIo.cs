using KernelEngine.Asset;
using KernelEngine.Asset.Assimp;
using KernelEngine.Async.Enki;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Std;

using Xunit;

namespace KernelEngine.Integration.Tests;

public class LoadingAModelThroughTheStdIo
{
    [Fact]
    public void AGltfAndTheBufferItNamesAreReadIntoMeshesAndMaterials()
    {
        using var config = new KernelEngine.Configuration.DefaultConfiguration();
        using var asyncs = new EnkiAsync(config.Section("async"));
        using var files = new StdFileSystem(".");
        using var io = new StdIo(files, config.Section("io"));
        using var loader = new AssimpAssetLoader(io);

        using var model = loader.LoadModel(Path.Combine(AppContext.BaseDirectory, "assets", "Box.gltf"));

        Assert.NotEmpty(model.Data.Meshes.ToArray());
        Assert.NotEmpty(model.Data.Materials.ToArray());
    }
}
