using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Tests;

/// <summary>
/// Phase 1 of the resource pipeline: ref-counted managed wrappers + the manager that creates them.
/// Tests use a fake <see cref="IResourceFactory"/> so the <c>CreateXAsync</c> extensions hit the
/// non-RCF fallback (synchronous <see cref="Task.FromResult"/>), exercising manager + ref-count
/// logic without the cross-thread queue.
/// </summary>
[Collection("KernelRegistry")]
public class ResourceManagerTests
{
    private static (ResourceManager manager, IResourceFactory factory) NewManager()
    {
        var factory = Substitute.For<IResourceFactory>();
        factory.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>()).Returns(new MeshHandle(42));
        factory.CreateTexture(Arg.Any<uint>(), Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(7));
        factory.CreateMaterial(Arg.Any<Vector4>(), Arg.Any<TextureHandle>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<TextureHandle>())
               .Returns(new MaterialHandle(13));
        return (new ResourceManager(factory), factory);
    }

    [Fact]
    public async Task CreateMaterialAsync_ReturnsRefCountedMaterial_WithHandleFromFactory()
    {
        var (manager, _) = NewManager();
        var mat = await manager.CreateMaterialAsync(new Vector4(1f, 0f, 0f, 1f));
        Assert.NotNull(mat);
        Assert.Equal(1, mat.ReferenceCount);
    }

    [Fact]
    public async Task Release_AtZero_DestroysOnceViaFactory()
    {
        var (manager, factory) = NewManager();
        var mat = await manager.CreateMaterialAsync(new Vector4(1f));
        var mesh = await manager.CreateMeshAsync(Array.Empty<Vertex>(), Array.Empty<ushort>());
        var tex = await manager.CreateTextureAsync(2, 2, new byte[16]);

        mat.Release();
        mesh.Release();
        tex.Release();

        factory.Received(1).DestroyMaterial(Arg.Any<MaterialHandle>());
        factory.Received(1).DestroyMesh(Arg.Any<MeshHandle>());
        factory.Received(1).DestroyTexture(Arg.Any<TextureHandle>());
    }

    [Fact]
    public async Task Retain_DelaysDestroyUntilAllReferencesReleased()
    {
        var (manager, factory) = NewManager();
        var mat = await manager.CreateMaterialAsync(new Vector4(1f));

        mat.Retain();                          // ref = 2
        Assert.Equal(2, mat.ReferenceCount);
        mat.Release();                         // ref = 1, no destroy yet
        factory.DidNotReceive().DestroyMaterial(Arg.Any<MaterialHandle>());
        mat.Release();                         // ref = 0, destroy
        factory.Received(1).DestroyMaterial(Arg.Any<MaterialHandle>());
    }

    [Fact]
    public async Task Dispose_IsEquivalentToRelease()
    {
        var (manager, factory) = NewManager();
        var tex = await manager.CreateTextureAsync(1, 1, new byte[4]);
        tex.Dispose();
        factory.Received(1).DestroyTexture(Arg.Any<TextureHandle>());
    }

    [Fact]
    public async Task Release_PastZero_Throws()
    {
        var (manager, _) = NewManager();
        var mesh = await manager.CreateMeshAsync(Array.Empty<Vertex>(), Array.Empty<ushort>());
        mesh.Release();
        Assert.Throws<InvalidOperationException>(() => mesh.Release());
    }

    [Fact]
    public async Task CreateCubemapAsync_ReturnsRefCountedTexture()
    {
        var (manager, factory) = NewManager();
        factory.CreateCubemap(Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(99));

        var tex = await manager.CreateCubemapAsync(2, new byte[16 * 6]);
        Assert.NotNull(tex);
        Assert.Equal(99u, tex.Handle.Value);
    }

    [Fact]
    public async Task DirectExtensionCalls_WorkWithPlainFactory()
    {
        var factory = Substitute.For<IResourceFactory>();
        factory.CreateMesh(Arg.Any<Vertex[]>(), Arg.Any<ushort[]>()).Returns(new MeshHandle(1));
        factory.CreateTexture(Arg.Any<uint>(), Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(2));
        factory.CreateCubemap(Arg.Any<uint>(), Arg.Any<byte[]>()).Returns(new TextureHandle(3));
        factory.CreateMaterial(Arg.Any<Vector4>(), Arg.Any<TextureHandle>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<TextureHandle>())
               .Returns(new MaterialHandle(4));

        Assert.Equal(1u, (await factory.CreateMeshAsync(Array.Empty<Vertex>(), Array.Empty<ushort>())).Value);
        Assert.Equal(2u, (await factory.CreateTextureAsync(1, 1, Array.Empty<byte>())).Value);
        Assert.Equal(3u, (await factory.CreateCubemapAsync(1, Array.Empty<byte>())).Value);
        Assert.Equal(4u, (await factory.CreateMaterialAsync(Vector4.One)).Value);
    }
}
