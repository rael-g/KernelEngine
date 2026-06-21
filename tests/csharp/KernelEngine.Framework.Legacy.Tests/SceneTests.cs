using KernelEngine.Framework.Legacy;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class SceneTests
{
    [Fact]
    public void Scene_Instantiate_CreatesNodes()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var scene = new Scene((t, root) => {
            t.AddNode("Child1", root);
            t.AddNode("Child2", root);
        }) { Name = "MyScene" };

        var instanceRoot = scene.Instantiate(tree);
        
        Assert.Equal("MyScene", instanceRoot.Name);
        Assert.NotNull(instanceRoot.FirstChild);
        Assert.Equal("Child2", instanceRoot.FirstChild.Name); // Prepend behavior
        Assert.NotNull(instanceRoot.FirstChild.NextSibling);
        Assert.Equal("Child1", instanceRoot.FirstChild.NextSibling.Name);
    }

    [Fact]
    public void Scene_Empty_InstantiatesRootOnly()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var scene = new Scene();

        var instanceRoot = scene.Instantiate(tree);
        
        Assert.Equal("Scene", instanceRoot.Name);
        Assert.Null(instanceRoot.FirstChild);
    }
}
