using Xunit;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using System.Numerics;
using NSubstitute;
using System.Linq;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class SceneLoaderTests
{
    [Fact]
    public void Load_SimpleNode_Works()
    {
        string toml = @"
[[node]]
name = ""test""
type = ""Camera2D""
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path);
            
            Assert.NotNull(tree.FindNode("test"));
            Assert.IsType<Camera2D>(tree.FindNode("test"));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_WithTransform_Works()
    {
        string toml = @"
[[node]]
name = ""test""
type = ""Camera2D""
[node.transform]
position = [1.0, 2.0, 3.0]
scale = [2.0, 2.0, 2.0]
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path);
            
            var node = tree.FindNode("test");
            Assert.NotNull(node);
            Assert.Equal(new Vector3(1, 2, 3), node.LocalTransform.Position);
            Assert.Equal(new Vector3(2, 2, 2), node.LocalTransform.Scale);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_WithHierarchy_Works()
    {
        string toml = @"
[[node]]
name = ""parent""
type = ""Camera2D""

[[node]]
name = ""child""
type = ""Camera2D""
parent = ""parent""
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path);
            
            var parent = tree.FindNode("parent");
            var child = tree.FindNode("child");
            Assert.NotNull(parent);
            Assert.NotNull(child);
            Assert.Equal(parent.Entity, child.Parent?.Entity);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_Throws_WhenTypeNotFound()
    {
        string toml = @"
[[node]]
name = ""test""
type = ""UnknownType""
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            Assert.Throws<InvalidDataException>(() => SceneLoader.Load(tree, path));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public async Task LoadAsync_ResolvesResources_Works()
    {
        string toml = @"
[[node]]
name = ""mesh""
type = ""MeshRenderer""
[node.properties]
Mesh = ""res://primitives/cube""
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            var rf = Substitute.For<IResourceFactory>();
            using var cache = new NativeResourceCache(allocator);
            var rm = new ResourceManager(rf, cache, cache, cache);

            await SceneLoader.LoadAsync(tree, path, rm);
            
            var node = tree.FindNode("mesh") as MeshRenderer;
            Assert.NotNull(node);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_WithEulerRotation_Works()
    {
        string toml = @"
[[node]]
name = ""rot""
type = ""Camera2D""
[node.transform]
rotation_euler = [90.0, 0.0, 0.0]
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path);
            
            var node = tree.FindNode("rot");
            // 90 deg on X
            var expected = Quaternion.CreateFromYawPitchRoll(0, 90f * MathF.PI / 180f, 0);
            Assert.Equal(expected.X, node.LocalTransform.Rotation.X, 5);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_WithQuaternionRotation_Works()
    {
        string toml = @"
[[node]]
name = ""quat""
type = ""Camera2D""
[node.transform]
rotation = [0.0, 0.0, 0.0, 1.0]
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path);
            
            var node = tree.FindNode("quat");
            Assert.Equal(Quaternion.Identity, node.LocalTransform.Rotation);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_NestedScene_Works()
    {
        string innerToml = @"
[[node]]
name = ""inner_root""
type = ""Camera2D""
";
        string outerToml = @"
[[node]]
name = ""nested""
scene = ""res://inner.scene.toml""
";
        string innerPath = Path.Combine(AppContext.BaseDirectory, "inner.scene.toml");
        string outerPath = Path.GetTempFileName();
        File.WriteAllText(innerPath, innerToml);
        File.WriteAllText(outerPath, outerToml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, outerPath);
            
            var nested = tree.FindNode("nested");
            Assert.NotNull(nested);
            Assert.IsType<Camera2D>(nested);
        }
        finally { 
            File.Delete(innerPath);
            File.Delete(outerPath);
        }
    }

    [Fact]
    public async Task LoadAsync_WithInlineMaterial_Works()
    {
        string toml = @"
[[node]]
name = ""mat_node""
type = ""MeshRenderer""
[node.properties.Material]
base_color = [1.0, 0.0, 0.0, 1.0]
metallic = 0.8
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            var rf = Substitute.For<IResourceFactory>();
            using var cache = new NativeResourceCache(allocator);
            var rm = new ResourceManager(rf, cache, cache, cache);

            await SceneLoader.LoadAsync(tree, path, rm);
            
            var node = tree.FindNode("mat_node") as MeshRenderer;
            Assert.NotNull(node);
        }
        finally { File.Delete(path); }
    }
}
