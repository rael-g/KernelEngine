using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class ResourceTests
{
    [Fact]
    public void Mesh_Dispose_ReleasesHandle()
    {
        var cache = Substitute.For<IResourceCacheBackend>();
        var mesh = new Mesh(cache, new MeshHandle(42));
        mesh.Dispose();
        cache.Received(1).Release(42);
    }

    [Fact]
    public void Texture_Dispose_ReleasesHandle()
    {
        var cache = Substitute.For<IResourceCacheBackend>();
        var tex = new Texture(cache, new TextureHandle(77));
        tex.Dispose();
        cache.Received(1).Release(77);
    }

    [Fact]
    public void Material_Dispose_ReleasesHandle()
    {
        var cache = Substitute.For<IResourceCacheBackend>();
        var mat = new Material(cache, new MaterialHandle(123));
        mat.Dispose();
        cache.Received(1).Release(123);
    }

    [Fact]
    public void Model_Dispose_ReleasesSyntheticHandle()
    {
        var cache = Substitute.For<IResourceCacheBackend>();
        var model = new Model(cache, 999u, new ModelMesh[0]);
        model.Dispose();
        cache.Received(1).Release(999);
    }
}
