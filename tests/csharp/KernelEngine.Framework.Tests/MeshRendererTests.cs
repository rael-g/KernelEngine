using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class MeshRendererTests
{
    [Fact]
    public void MeshRenderer_SyncsPropertiesToEcs()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);

        var renderer = new MeshRenderer {
            MeshHandle = new MeshHandle(10),
            MaterialHandle = new MaterialHandle(20),
        };

        var tree = new Tree(world);
        tree.AddNode(renderer, "Mesh");
        tree.TickAwakeAndStart();

        var cid = world.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");
        var compSpan = world.Registry.GetComponent<MeshComponent>(renderer.Entity, cid);
        Assert.False(compSpan.IsEmpty, $"MeshComponent {cid} not found for entity {renderer.Entity}");
        Assert.Equal(10u, compSpan[0].MeshHandle.Value);
        Assert.Equal(20u, compSpan[0].MaterialHandle.Value);
    }

    [Fact]
    public void MeshRenderer_UsesDefaultHandles_WhenNoneProvided()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);

        var renderer = new MeshRenderer();

        var tree = new Tree(world);
        tree.AddNode(renderer, "Mesh");
        tree.TickAwakeAndStart();

        var cid = world.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");
        var compSpan = world.Registry.GetComponent<MeshComponent>(renderer.Entity, cid);
        Assert.Equal(MeshRenderer.DefaultMeshHandle, compSpan[0].MeshHandle);
        Assert.Equal(MeshRenderer.DefaultMaterialHandle, compSpan[0].MaterialHandle);
    }
}
