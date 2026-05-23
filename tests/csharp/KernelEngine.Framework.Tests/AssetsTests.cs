using KernelEngine.Framework;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

/// <summary>
/// Phase 2: <see cref="Assets"/> caches loaded models by path, dedups concurrent loads, and
/// evicts the cache entry when the last reference is released. Tests use an empty
/// <see cref="IModel"/> so the cache+lifetime mechanics are exercised without the upload pipeline.
/// </summary>
public class AssetsTests
{
    private static (Assets assets, IAssetLoader loader, IResourceFactory factory) NewAssets()
    {
        var factory = Substitute.For<IResourceFactory>();
        var loader = Substitute.For<IAssetLoader>();

        var model = Substitute.For<IModel>();
        model.Meshes.Returns(Array.Empty<IModelMesh>());
        model.Materials.Returns(Array.Empty<IModelMaterial>());
        model.Textures.Returns(Array.Empty<IModelTexture>());
        loader.LoadModelAsync(Arg.Any<string>()).Returns(Task.FromResult(model));

        return (new Assets(loader, new ResourceManager(factory)), loader, factory);
    }

    [Fact]
    public async Task LoadModelAsync_FirstCall_InvokesLoaderOnce_AndReturnsRefCount1()
    {
        var (assets, loader, _) = NewAssets();
        var m = await assets.LoadModelAsync("foo.gltf");
        Assert.NotNull(m);
        Assert.Equal(1, m.ReferenceCount);
        await loader.Received(1).LoadModelAsync("foo.gltf");
    }

    [Fact]
    public async Task LoadModelAsync_SamePath_ReturnsSameInstance_AndIncrementsRefCount()
    {
        var (assets, loader, _) = NewAssets();
        var a = await assets.LoadModelAsync("foo.gltf");
        var b = await assets.LoadModelAsync("foo.gltf");
        Assert.Same(a, b);
        Assert.Equal(2, a.ReferenceCount);
        await loader.Received(1).LoadModelAsync("foo.gltf"); // cache hit second time
    }

    [Fact]
    public async Task Release_ToZero_EvictsFromCache_SoNextLoadFetchesAgain()
    {
        var (assets, loader, _) = NewAssets();
        var a = await assets.LoadModelAsync("foo.gltf");
        a.Release();                          // refCount → 0, evict
        var b = await assets.LoadModelAsync("foo.gltf");
        Assert.NotSame(a, b);                 // a was evicted/destroyed; b is freshly loaded
        await loader.Received(2).LoadModelAsync("foo.gltf");
    }

    [Fact]
    public async Task DifferentPaths_AreIndependentEntries()
    {
        var (assets, _, _) = NewAssets();
        var a = await assets.LoadModelAsync("a.gltf");
        var b = await assets.LoadModelAsync("b.gltf");
        Assert.NotSame(a, b);
        Assert.Equal(1, a.ReferenceCount);
        Assert.Equal(1, b.ReferenceCount);
    }
}
