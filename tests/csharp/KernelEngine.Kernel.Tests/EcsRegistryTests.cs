using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
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
        var cid = reg.RegisterComponent<int>("int");
        Assert.NotEqual(uint.MaxValue, cid);
    }

    [Fact]
    public void GetComponent_ReturnsEmptySpan_WhenMissing()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var cid = reg.RegisterComponent<int>("int");

        var span = reg.GetComponent<int>(entity, cid);
        Assert.True(span.IsEmpty);
    }

    [Fact]
    public void AddComponentRaw_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var cid = reg.RegisterComponent<int>("int");

        unsafe {
            int* ptr = reg.AddComponentRaw<int>(entity, cid);
            Assert.True(ptr != null);
            *ptr = 42;
        }
        
        Assert.Equal(42, reg.GetComponent<int>(entity, cid)[0]);
    }

    [Fact]
    public void GetComponentRaw_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var cid = reg.RegisterComponent<int>("int");
        reg.AddComponent<int>(entity, cid)[0] = 123;

        unsafe {
            int* ptr = reg.GetComponentRaw<int>(entity, cid);
            Assert.True(ptr != null);
            Assert.Equal(123, *ptr);
        }
    }

    [Fact]
    public void RemoveComponent_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var cid = reg.RegisterComponent<int>("int");
        reg.AddComponent<int>(entity, cid);

        Assert.True(reg.HasComponent(entity, cid));
        reg.RemoveComponent(entity, cid);
        Assert.False(reg.HasComponent(entity, cid));
    }

    [Fact]
    public void HasComponent_ReturnsTrue_WhenPresent()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = world.Registry;
        var entity = reg.CreateEntity();
        var cid = reg.RegisterComponent<int>("int");
        reg.AddComponent<int>(entity, cid);

        Assert.True(reg.HasComponent(entity, cid));
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
