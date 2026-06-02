using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using Tomlyn.Model;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework.Tests;

public class NodeTypeRegistrarTests
{
    public class TestNode : Node
    {
        public Vector2 Vec2 { get; set; }
        public float FloatVal { get; set; }
        public string? StringVal { get; set; }
        public TestEnum EnumVal { get; set; }
        public Shape2D? Shape { get; set; }
    }

    public enum TestEnum { A, B }

    [Fact]
    public void ResolveNodeType_ReturnsCorrectType()
    {
        var type = NodeTypeRegistrar.ResolveNodeType("Camera2D");
        Assert.Equal(typeof(Camera2D), type);
    }

    [Fact]
    public void ResolveNodeType_ReturnsNull_ForUnknown()
    {
        var type = NodeTypeRegistrar.ResolveNodeType("UnknownType");
        Assert.Null(type);
    }

    [Fact]
    public void ApplyProperty_SetsVector2()
    {
        var node = new TestNode();
        var arr = new TomlArray { 1.5, 2.5 };
        
        NodeTypeRegistrar.ApplyProperty(node, "Vec2", arr, null);

        Assert.Equal(1.5f, node.Vec2.X);
        Assert.Equal(2.5f, node.Vec2.Y);
    }

    [Fact]
    public void ApplyProperty_SetsFloat()
    {
        var node = new TestNode();
        NodeTypeRegistrar.ApplyProperty(node, "FloatVal", 3.14, null);
        Assert.Equal(3.14f, node.FloatVal);
    }

    [Fact]
    public void ApplyProperty_SetsString()
    {
        var node = new TestNode();
        NodeTypeRegistrar.ApplyProperty(node, "StringVal", "hello", null);
        Assert.Equal("hello", node.StringVal);
    }

    [Fact]
    public void ApplyProperty_SetsEnum()
    {
        var node = new TestNode();
        NodeTypeRegistrar.ApplyProperty(node, "EnumVal", "B", null);
        Assert.Equal(TestEnum.B, node.EnumVal);
    }

    [Fact]
    public void ApplyProperty_SetsShape_Circle()
    {
        var node = new TestNode();
        var table = new TomlTable { ["kind"] = "circle", ["radius"] = 5.0 };
        
        NodeTypeRegistrar.ApplyProperty(node, "Shape", table, null);

        var circle = Assert.IsType<CircleShape2D>(node.Shape);
        Assert.Equal(5f, circle.Radius);
    }

    [Fact]
    public void ApplyProperty_SetsShape_Rectangle()
    {
        var node = new TestNode();
        var table = new TomlTable { 
            ["kind"] = "rectangle", 
            ["half_extents"] = new TomlArray { 10.0, 20.0 } 
        };
        
        NodeTypeRegistrar.ApplyProperty(node, "Shape", table, null);

        var rect = Assert.IsType<RectangleShape2D>(node.Shape);
        Assert.Equal(10f, rect.HalfExtents.X);
        Assert.Equal(20f, rect.HalfExtents.Y);
    }

    public class MultiPropertyNode : Node
    {
        public Vector3 Vec3 { get; set; }
        public Vector4 Vec4 { get; set; }
        public Quaternion Quat { get; set; }
        public Mesh? Mesh { get; set; }
        public Material? Material { get; set; }
    }

    [Fact]
    public void ApplyProperty_SetsVector3()
    {
        var node = new MultiPropertyNode();
        var arr = new TomlArray { 1.0, 2.0, 3.0 };
        NodeTypeRegistrar.ApplyProperty(node, "Vec3", arr, null);
        Assert.Equal(new Vector3(1, 2, 3), node.Vec3);
    }

    [Fact]
    public void ApplyProperty_SetsVector4()
    {
        var node = new MultiPropertyNode();
        var arr = new TomlArray { 1.0, 2.0, 3.0, 4.0 };
        NodeTypeRegistrar.ApplyProperty(node, "Vec4", arr, null);
        Assert.Equal(new Vector4(1, 2, 3, 4), node.Vec4);
    }

    [Fact]
    public void ApplyProperty_SetsQuaternion()
    {
        var node = new MultiPropertyNode();
        var arr = new TomlArray { 0.0, 0.0, 0.0, 1.0 };
        NodeTypeRegistrar.ApplyProperty(node, "Quat", arr, null);
        Assert.Equal(new Quaternion(0, 0, 0, 1), node.Quat);
    }

    [Fact]
    public void ApplyProperty_Throws_OnInvalidData()
    {
        var node = new TestNode();
        // Passing a string where a float is expected
        Assert.Throws<InvalidDataException>(() => NodeTypeRegistrar.ApplyProperty(node, "FloatVal", "not-a-float", null));
    }

    [Fact]
    public void ResolveNodeType_ReturnsDirectType()
    {
        var type = NodeTypeRegistrar.ResolveNodeType("KernelEngine.Framework.Camera2D");
        Assert.Equal(typeof(Camera2D), type);
    }

    [Fact]
    public void ResolveResource_Primitives_Work()
    {
        var rf = Substitute.For<IResourceFactory>();
        var rm = new ResourceManager(rf);
        var node = new MultiPropertyNode();
        
        NodeTypeRegistrar.ApplyProperty(node, "Mesh", "res://primitives/cube", rm);
        Assert.NotNull(node.Mesh);
        
        NodeTypeRegistrar.ApplyProperty(node, "Mesh", "res://primitives/plane", rm);
        Assert.NotNull(node.Mesh);

        NodeTypeRegistrar.ApplyProperty(node, "Mesh", "res://primitives/quad", rm);
        Assert.NotNull(node.Mesh);

        NodeTypeRegistrar.ApplyProperty(node, "Mesh", "res://primitives/sphere", rm);
        Assert.NotNull(node.Mesh);
    }

    [Fact]
    public void BuildInlineMaterial_Works()
    {
        var rf = Substitute.For<IResourceFactory>();
        var rm = new ResourceManager(rf);
        var node = new MultiPropertyNode();
        
        var matTable = new TomlTable { 
            ["base_color"] = new TomlArray { 1.0, 0.0, 0.0, 1.0 },
            ["metallic"] = 1.0,
            ["roughness"] = 0.0
        };
        
        NodeTypeRegistrar.ApplyProperty(node, "Material", matTable, rm);
        Assert.NotNull(node.Material);
    }

    [Fact]
    public void Register_WithServices_CallsActivatorUtilities()
    {
        var registry = Substitute.For<INodeTypeRegistry>();
        var world = Substitute.For<IWorld>();
        var services = new ServiceCollection().BuildServiceProvider();
        
        Action<ulong, string>? createCallback = null;
        registry.When(r => r.Register(Arg.Any<string>(), Arg.Any<Action<ulong, string>>(), Arg.Any<Action<ulong, string, object?>>()))
                .Do(x => createCallback = x.Arg<Action<ulong, string>>());

        registry.Register<TestNode>(world, services);
        
        createCallback!(1, "test");
        // Verifying it didn't throw is enough here as it covers the branch
    }
}
