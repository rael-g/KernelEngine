using KernelEngine.Asset;
using KernelEngine.Asset.Assimp;
using KernelEngine.Async.Enki;
using KernelEngine.FileSystem.Std;
using KernelEngine.Io.Async;

using Xunit;

namespace KernelEngine.Integration.Tests;

public class LoadingAModelThroughTheAsyncIo
{
    [Fact]
    public void AGltfAndTheBufferItNamesAreReadIntoMeshesAndMaterials()
    {
        using var asyncs = new EnkiAsync(null, new Async.AsyncConfig { WorkerCount = 1, SubmitCapacity = 16 });
        using var files = new StdFileSystem(null, new FileSystem.FileSystemConfig { Root = "." });
        using var io = new AsyncIo(null, asyncs, files);
        using var loader = new AssimpAssetLoader(null, io);

        using var model = loader.LoadModel(Path.Combine(AppContext.BaseDirectory, "assets", "Box.gltf"));

        Assert.NotEmpty(model.Data.Meshes.ToArray());
        Assert.NotEmpty(model.Data.Materials.ToArray());
    }
}
