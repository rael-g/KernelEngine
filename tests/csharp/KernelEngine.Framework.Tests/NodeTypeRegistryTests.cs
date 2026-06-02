using System.Runtime.InteropServices;
using Xunit;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Tests;

public class NodeTypeRegistryTests
{
    [Fact]
    public void Constructor_Works()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        Assert.NotNull(registry);
    }

    [Fact]
    public void Register_Works()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        bool created = false;
        registry.Register("TestType", (e, n) => created = true, (e, k, v) => { });
        
        registry.TryCreate("TestType", 1, "test");
        Assert.True(created);
    }

    [Fact]
    public void TryCreate_ReturnsFalse_WhenNotFound()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        Assert.False(registry.TryCreate("Unknown", 1, "test"));
    }

    [Fact]
    public void TryCreate_CallsFallback()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        bool fallbackCalled = false;
        registry.SetFallback((t, e, n) => { fallbackCalled = true; return true; }, (t, e, k, v) => false);
        
        Assert.True(registry.TryCreate("Unknown", 1, "test"));
        Assert.True(fallbackCalled);
    }

    [Fact]
    public void TrySetProperty_Works()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        object? receivedValue = null;
        registry.Register("TestType", (e, n) => { }, (e, k, v) => receivedValue = v);
        
        registry.TrySetProperty("TestType", 1, "key", "value");
        Assert.Equal("value", receivedValue);
    }

    [Fact]
    public void TrySetProperty_CallsFallback()
    {
        using var allocator = new MallocAllocator();
        using var registry = new NodeTypeRegistry(allocator);
        bool fallbackCalled = false;
        registry.SetFallback((t, e, n) => false, (t, e, k, v) => { fallbackCalled = true; return true; });
        
        Assert.True(registry.TrySetProperty("Unknown", 1, "key", "value"));
        Assert.True(fallbackCalled);
    }

    [Fact]
    public unsafe void VariantToObject_ConvertsAllTypes()
    {
        var method = typeof(NodeTypeRegistry).GetMethod("VariantToObject", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        
        // Null
        var v = new ke_variant { type = ke_variant_type.KE_VARIANT_NULL };
        Assert.Null(method!.Invoke(null, new object[] { v }));
        
        // Bool
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_BOOL, b = true };
        Assert.Equal(true, method!.Invoke(null, new object[] { v }));
        
        // Int
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_INT, i = 42 };
        Assert.Equal(42L, method!.Invoke(null, new object[] { v }));
        
        // Float
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_FLOAT, f = 3.14 };
        Assert.Equal(3.14, (double)method!.Invoke(null, new object[] { v })!, 5);
        
        // String
        var s = Marshal.StringToCoTaskMemUTF8("hello");
        try {
            v = new ke_variant { type = ke_variant_type.KE_VARIANT_STRING, s = (sbyte*)s };
            Assert.Equal("hello", method!.Invoke(null, new object[] { v }));
        } finally { Marshal.FreeCoTaskMem(s); }

        // Vec2
        var v2 = new ke_vec2 { x = 1, y = 2 };
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_VEC2, v2 = v2 };
        var resV2 = (ke_vec2)method!.Invoke(null, new object[] { v })!;
        Assert.Equal(1f, resV2.x);
        Assert.Equal(2f, resV2.y);

        // Vec3
        var v3 = new ke_vec3 { x = 1, y = 2, z = 3 };
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_VEC3, v3 = v3 };
        var resV3 = (ke_vec3)method!.Invoke(null, new object[] { v })!;
        Assert.Equal(3f, resV3.z);

        // Vec4
        var v4 = new ke_vec4 { x = 1, y = 2, z = 3, w = 4 };
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_VEC4, v4 = v4 };
        var resV4 = (ke_vec4)method!.Invoke(null, new object[] { v })!;
        Assert.Equal(4f, resV4.w);

        // Quat
        var q = new ke_quat { x = 0, y = 0, z = 0, w = 1 };
        v = new ke_variant { type = ke_variant_type.KE_VARIANT_QUAT, q = q };
        var resQ = (ke_quat)method!.Invoke(null, new object[] { v })!;
        Assert.Equal(1f, resQ.w);

        // Unknown
        v = new ke_variant { type = (ke_variant_type)999 };
        Assert.Null(method!.Invoke(null, new object[] { v }));
    }
}
