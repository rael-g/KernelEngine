using System.Numerics;
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

        return (new Assets(loader, imageLoader: null, new ResourceManager(factory)), loader, factory);
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

    private sealed class FakeModelTexture : IModelTexture
    {
        public string Path => "";
        public uint Width => 2;
        public uint Height => 2;
        public ReadOnlySpan<byte> Pixels => new byte[16];
    }

    private sealed class FakeModelMesh(string name, int materialIndex) : IModelMesh
    {
        public string Name => name;
        public int MaterialIndex => materialIndex;
        public ReadOnlySpan<Vertex> Vertices => new Vertex[3];
        public ReadOnlySpan<ushort> Indices => new ushort[3];
    }

    private sealed class FakeModelMaterial : IModelMaterial
    {
        public string Name => "";
        public Vector4 BaseColor => Vector4.One;
        public float Metallic => 0;
        public float Roughness => 0.5f;
        public int AlbedoTextureIndex => 0;
        public int NormalMapTextureIndex => -1;
    }

    private sealed class FakeModelData : IModel
    {
        public IReadOnlyList<IModelMesh> Meshes { get; set; } = new List<IModelMesh>();
        public IReadOnlyList<IModelMaterial> Materials { get; set; } = new List<IModelMaterial>();
        public IReadOnlyList<IModelTexture> Textures { get; set; } = new List<IModelTexture>();
        public void Dispose() { }
    }

    [Fact]
    public async Task LoadModelAsync_WithMultipleMeshesAndMaterials_UploadsAll()
    {
        var (assets, loader, factory) = NewAssets();
        var modelData = new FakeModelData
        {
            Textures = new List<IModelTexture> { new FakeModelTexture() },
            Materials = new List<IModelMaterial> { new FakeModelMaterial() },
            Meshes = new List<IModelMesh> { new FakeModelMesh("Mesh1", 0), new FakeModelMesh("Mesh2", -1) }
        };
        
        loader.LoadModelAsync("complex.gltf").Returns(Task.FromResult<IModel>(modelData));
        factory.CreateTexture(Arg.Any<uint>(), Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(1));
        factory.CreateMaterial(Arg.Any<Vector4>(), Arg.Any<TextureHandle>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<TextureHandle>())
               .Returns(new MaterialHandle(10), new MaterialHandle(20)); // One for mat0, one for fallback
        factory.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>()).Returns(new MeshHandle(100), new MeshHandle(200));

        var model = await assets.LoadModelAsync("complex.gltf");
        
        Assert.Equal(2, model.Meshes.Count);
        Assert.Equal(100u, model.Meshes[0].Mesh.Handle.Value);
        Assert.Equal(10u, model.Meshes[0].Material.Handle.Value);
        Assert.Equal(20u, model.Meshes[1].Material.Handle.Value); // Fallback
    }

    [Fact]
    public async Task Model_Release_ReleasesAllSubResources()
    {
        var factory = Substitute.For<IResourceFactory>();
        var manager = new ResourceManager(factory);
        
        factory.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>()).Returns(new MeshHandle(1));
        factory.CreateMaterial(Arg.Any<Vector4>(), Arg.Any<TextureHandle>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<TextureHandle>())
               .Returns(new MaterialHandle(1));
        factory.CreateTexture(Arg.Any<uint>(), Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(1));

        var mesh = await manager.CreateMeshAsync(Array.Empty<Vertex>(), Array.Empty<ushort>());
        var mat = await manager.CreateMaterialAsync(Vector4.One);
        var tex = await manager.CreateTextureAsync(1, 1, new byte[4]);

        // Retain material because it's used in two places (ModelMesh and _materials list)
        mat.Retain();

        var model = new Model(
            new List<ModelMesh> { new ModelMesh("M", mesh, mat) },
            new List<Material> { mat },
            new List<Texture> { tex }
        );

        // Model initially holds 1 ref to model itself.
        // Construction of Model DOES NOT automatically retain sub-resources, 
        // the constructor just takes ownership of the passed references? 
        // No, typically in KernelEngine, we pass already-retained instances to the constructor.
        // Model.DestroyNative calls Release() on everything.

        model.Release();

        // Each Mesh/Material/Texture should have been destroyed in the factory exactly once.
        factory.Received(1).DestroyMesh(Arg.Any<MeshHandle>());
        factory.Received(1).DestroyMaterial(Arg.Any<MaterialHandle>());
        factory.Received(1).DestroyTexture(Arg.Any<TextureHandle>());
    }

    private sealed class FakeImageData : IImageData
    {
        private readonly byte[] _pixels;
        public FakeImageData(string path, uint w, uint h) { Path = path; Width = w; Height = h; _pixels = new byte[w * h * 4]; }
        public string Path { get; }
        public uint Width { get; }
        public uint Height { get; }
        public ReadOnlySpan<byte> Pixels => _pixels;
        public void Dispose() { }
    }

    [Fact]
    public async Task LoadTextureAsync_CachesByPath_AndEvictsOnRelease()
    {
        var imageLoader = Substitute.For<IImageLoader>();
        imageLoader.LoadImageAsync(Arg.Any<string>())
            .Returns(call => Task.FromResult<IImageData>(new FakeImageData((string)call[0], 2, 2)));

        var factory = Substitute.For<IResourceFactory>();
        var assets = new Assets(modelLoader: null, imageLoader, new ResourceManager(factory));

        var t1 = await assets.LoadTextureAsync("a.png");
        var t2 = await assets.LoadTextureAsync("a.png");
        Assert.Same(t1, t2);
        Assert.Equal(2, t1.ReferenceCount);
        await imageLoader.Received(1).LoadImageAsync("a.png");

        t1.Release();
        t2.Release();
        var t3 = await assets.LoadTextureAsync("a.png");
        Assert.NotSame(t1, t3);
        await imageLoader.Received(2).LoadImageAsync("a.png");
    }

    [Fact]
    public async Task LoadModelAsync_ConcurrentRace_ReturnsSameInstance_AndReleasesExtra()
    {
        var (assets, loader, _) = NewAssets();
        
        // Loader will delay a bit to allow a race
        loader.LoadModelAsync(Arg.Any<string>()).Returns(async call => {
            await Task.Delay(100);
            var model = Substitute.For<IModel>();
            model.Meshes.Returns(Array.Empty<IModelMesh>());
            model.Materials.Returns(Array.Empty<IModelMaterial>());
            model.Textures.Returns(Array.Empty<IModelTexture>());
            return model;
        });

        var t1 = assets.LoadModelAsync("race.gltf");
        var t2 = assets.LoadModelAsync("race.gltf");

        var m1 = await t1;
        var m2 = await t2;

        Assert.Same(m1, m2);
        Assert.Equal(2, m1.ReferenceCount); // Initial 1 (from load) + 1 (from second caller retain)
        // Note: the second load should detect the win and release its own duplicate,
        // returning the winner with a fresh retain.
    }
}
