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
    static SceneLoaderTests()
    {
        // Bypass DI: wire the native backend factory so FrameworkBackends.Required
        // resolves when the tests instantiate Tree / SceneLoader directly.
        var factory = new NativeFrameworkBackendFactory();
        FrameworkBackends.Default ??= factory;
    }

    public SceneLoaderTests()
    {
        // Each test gets a fresh World whose entity counter restarts at 1, so a
        // stale wrapper from the previous test (same entity id, different
        // disposed world) would be returned by Node.FromEntity. Clear the
        // static registry every test so WrapEntity always creates a new
        // wrapper bound to *this* test's world.
        Node.ClearRegistryForTests();
    }

    [Fact]
    public void Load_SimpleNode_Works()
    {
        string toml = @"
[[entity]]
name = ""test""
[entity.script]
language = ""csharp""
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
[[entity]]
name = ""test""
[entity.script]
language = ""csharp""
type = ""Camera2D""
[entity.transform]
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
[[entity]]
name = ""parent""
[entity.script]
language = ""csharp""
type = ""Camera2D""

[[entity]]
name = ""child""
parent = ""parent""
[entity.script]
language = ""csharp""
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

            var parent = tree.FindNode("parent");
            var child = tree.FindNode("child");
            Assert.NotNull(parent);
            Assert.NotNull(child);
            Assert.Equal(parent.Entity, child.Parent?.Entity);
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_UnknownType_SkipsScript()
    {
        // Phase 5.6: the legacy [[node]] path threw on unknown types via the
        // node-type registry callback; the new [entity.script] path is silent
        // — unknown languages or types just don't get wrapped, and the entity
        // remains as a plain ECS row.
        string toml = @"
[[entity]]
name = ""test""
[entity.script]
language = ""csharp""
type = ""UnknownType""
";
        string path = Path.GetTempFileName();
        File.WriteAllText(path, toml);
        try
        {
            using var allocator = new MallocAllocator();
            using var world = new World(allocator);
            var tree = new Tree(world);
            SceneLoader.Load(tree, path); // does not throw

            // The entity is in the scene tree by name, but no C# wrapper attached.
            // FindNode walks Node.s_registry, so an unwrapped entity returns null.
            Assert.Null(tree.FindNode("test"));
        }
        finally { File.Delete(path); }
    }

    [Fact]
    public void Load_WithEulerRotation_Works()
    {
        string toml = @"
[[entity]]
name = ""rot""
[entity.script]
language = ""csharp""
type = ""Camera2D""
[entity.transform]
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
[[entity]]
name = ""quat""
[entity.script]
language = ""csharp""
type = ""Camera2D""
[entity.transform]
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
[[entity]]
name = ""inner_root""
[entity.script]
language = ""csharp""
type = ""Camera2D""
";
        string outerToml = @"
[[entity]]
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
}
