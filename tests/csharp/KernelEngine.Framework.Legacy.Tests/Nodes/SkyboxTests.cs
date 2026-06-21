
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class SkyboxTests
{
    [Fact]
    public void Skybox_DefaultCubemapHandle_IsNone()
    {
        var skybox = new Skybox();
        Assert.Equal(TextureHandle.None, skybox.CubemapHandle);
    }

    [Fact]
    public void Skybox_Start_AddsSkyboxComponent_WhenCubemapIsValid()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        var skybox = new Skybox { CubemapHandle = new TextureHandle(5u) };
        tree.AddNode(skybox);
        
        skybox.TickAwakeAndStart();
        
        var cid = world.GetOrRegisterComponentId<SkyboxComponent>("Skybox");
        Assert.True(world.Registry.HasComponent(skybox.Entity, cid));
    }

    [Fact]
    public void Skybox_Start_SetsCorrectCubemapHandle_WhenCubemapIsValid()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        var skybox = new Skybox { CubemapHandle = new TextureHandle(5u) };
        tree.AddNode(skybox);
        
        skybox.TickAwakeAndStart();
        
        var cid = world.GetOrRegisterComponentId<SkyboxComponent>("Skybox");
        var comp = world.Registry.GetComponent<SkyboxComponent>(skybox.Entity, cid);
        Assert.Equal(5u, comp[0].CubemapHandle.Value);
    }

    [Fact]
    public void Skybox_Start_DoesNotAddSkyboxComponent_WhenCubemapIsNone()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        var skybox = new Skybox { CubemapHandle = TextureHandle.None };
        tree.AddNode(skybox);
        
        skybox.TickAwakeAndStart();
        
        var cid = world.GetOrRegisterComponentId<SkyboxComponent>("Skybox");
        Assert.False(world.Registry.HasComponent(skybox.Entity, cid));
    }
}
