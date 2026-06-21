
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class ResourceQueueTests
{
    public interface IAllResourceFactory : IResourceFactory, IAsyncResourceFactory { }

    [Fact]
    public async Task CreateMeshAsync_ReturnsValidResource()
    {
        var factory = Substitute.For<IAllResourceFactory>();
        var meshCache = Substitute.For<IResourceCacheBackend>();
        var matCache = Substitute.For<IResourceCacheBackend>();
        var texCache = Substitute.For<IResourceCacheBackend>();
        
        var manager = new ResourceManager(factory, meshCache, matCache, texCache);
        
        var vertices = new Vertex[3];
        var indices = new ushort[3];

        factory.CreateMeshAsync(vertices, indices)
            .Returns(Task.FromResult(new MeshHandle(42)));

        var mesh = await manager.CreateMeshAsync(vertices, indices);
        
        Assert.Equal(42u, mesh.Handle.Value);
    }

    [Fact]
    public async Task CreateTextureAsync_ReturnsValidResource()
    {
        var factory = Substitute.For<IAllResourceFactory>();
        var meshCache = Substitute.For<IResourceCacheBackend>();
        var matCache = Substitute.For<IResourceCacheBackend>();
        var texCache = Substitute.For<IResourceCacheBackend>();
        
        var manager = new ResourceManager(factory, meshCache, matCache, texCache);
        
        var pixels = new byte[16];
        factory.CreateTextureAsync(2, 2, pixels)
            .Returns(Task.FromResult(new TextureHandle(10)));

        var tex = await manager.CreateTextureAsync(2, 2, pixels);
        
        Assert.Equal(10u, tex.Handle.Value);
    }

    [Fact]
    public void CreateComposite_FiresReleasesOnDestroy()
    {
        var factory = Substitute.For<IAllResourceFactory>();
        var meshCache = Substitute.For<IResourceCacheBackend>();
        var matCache = Substitute.For<IResourceCacheBackend>();
        var texCache = Substitute.For<IResourceCacheBackend>();
        
        var manager = new ResourceManager(factory, meshCache, matCache, texCache);
        
        Action? destroyHook = null;
        texCache.RegisterComposite(Arg.Do<Action>(a => destroyHook = a)).Returns(999u);
        
        var mesh = new Mesh(meshCache, new MeshHandle(1));
        var mat = new Material(matCache, new MaterialHandle(2));
        var modelMesh = new ModelMesh("test", mesh, mat);
        
        var model = manager.CreateComposite(new[] { modelMesh }, new[] { mat }, new Texture[0]);
        
        Assert.Equal(999u, model.RawHandle);
        Assert.NotNull(destroyHook);
        
        destroyHook!();
        
        // meshCache.Release should be called for modelMesh.Mesh
        meshCache.Received(1).Release(1);
        // matCache.Release should be called for modelMesh.Material AND the materials list entry
        matCache.Received(2).Release(2);
    }
}
