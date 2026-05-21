using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class EcsRegistryTests
{
    [Fact]
    public void CreateEntity_ReturnsValidId()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        Assert.NotEqual(0UL, entity);
    }

    [Fact]
    public void RegisterComponent_ReturnsValidId()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var id = reg.RegisterComponent<int>("TestComp");
        Assert.NotEqual(uint.MaxValue, id);
    }

    [Fact]
    public unsafe void AddComponent_ReturnsValidReference()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var id = reg.RegisterComponent<int>("TestComp");
        
        ref int val = ref *reg.AddComponentRaw<int>(entity, id);
        val = 42;
        
        Assert.Equal(42, val);
    }

    [Fact]
    public unsafe void GetComponent_ReturnsAddedValue()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var id = reg.RegisterComponent<int>("TestComp");
        *reg.AddComponentRaw<int>(entity, id) = 123;
        
        int* ptr = reg.GetComponentRaw<int>(entity, id);
        Assert.True(ptr != null);
    }

    [Fact]
    public unsafe void GetComponent_ReturnsCorrectValue()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var id = reg.RegisterComponent<int>("TestComp");
        *reg.AddComponentRaw<int>(entity, id) = 123;
        
        int* ptr = reg.GetComponentRaw<int>(entity, id);
        Assert.Equal(123, *ptr);
    }

    [Fact]
    public unsafe void GetComponent_ReturnsNull_WhenNotPresent()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var id = reg.RegisterComponent<int>("TestComp");
        
        int* ptr = reg.GetComponentRaw<int>(entity, id);
        Assert.True(ptr == null);
    }

    [Fact]
    public unsafe void RemoveComponent_MakesItNull()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var id = reg.RegisterComponent<int>("TestComp");
        *reg.AddComponentRaw<int>(entity, id) = 1;
        
        reg.RemoveComponent(entity, id);
        
        Assert.True(reg.GetComponentRaw<int>(entity, id) == null);
    }

    [Fact]
    public unsafe void Query_ReturnsCorrectCount()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var id = reg.RegisterComponent<int>("TestComp");
        
        var e1 = reg.CreateEntity();
        var e2 = reg.CreateEntity();
        *reg.AddComponentRaw<int>(e1, id) = 10;
        *reg.AddComponentRaw<int>(e2, id) = 20;
        
        var query = reg.Query<int>(id);
        Assert.Equal(2, query.Length);
    }

    [Fact]
    public unsafe void Query_ReturnsCorrectData()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var id = reg.RegisterComponent<int>("TestComp");
        var e = reg.CreateEntity();
        *reg.AddComponentRaw<int>(e, id) = 99;
        
        var query = reg.Query<int>(id);
        Assert.Equal(99, query.Data[0]);
    }
}
