using Xunit;
using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
public unsafe class ScriptBridgeTests
{
    [Fact]
    public void Register_SetsNativeFunctionPointers()
    {
        ScriptBridge.ClearForTesting();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = (EcsRegistry)world.Registry;
        var entity = reg.CreateEntity();
        var cid = world.ScriptComponentId;

        ScriptBridge.Register(reg, cid, entity, onAwake: () => { });

        var slot = reg.GetComponent<ke_script_component>(entity, cid);
        Assert.True(slot[0].on_awake != null);
        Assert.True(slot[0].on_start == null);
    }

    [Fact]
    public void NativeCallbacks_InvokeDelegates()
    {
        ScriptBridge.ClearForTesting();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = (EcsRegistry)world.Registry;
        var entity = reg.CreateEntity();
        var cid = world.ScriptComponentId;

        bool awake = false, start = false, update = false, late = false, destroy = false, input = false;
        
        ScriptBridge.Register(reg, cid, entity,
            onAwake: () => awake = true,
            onStart: () => start = true,
            onUpdate: (dt) => update = true,
            onLateUpdate: (dt) => late = true,
            onDestroy: () => destroy = true,
            onInput: (s) => input = true);

        var slot = reg.GetComponent<ke_script_component>(entity, cid);

        // Awake
        ((delegate* unmanaged[Cdecl]<ulong, ke_result>)slot[0].on_awake)(entity);
        Assert.True(awake);

        // Start
        ((delegate* unmanaged[Cdecl]<ulong, ke_result>)slot[0].on_start)(entity);
        Assert.True(start);

        // Update
        ((delegate* unmanaged[Cdecl]<ulong, float, ke_result>)slot[0].on_update)(entity, 0.1f);
        Assert.True(update);

        // LateUpdate
        ((delegate* unmanaged[Cdecl]<ulong, float, ke_result>)slot[0].on_late_update)(entity, 0.1f);
        Assert.True(late);

        // Input
        ke_input_snapshot s = default;
        ((delegate* unmanaged[Cdecl]<ulong, ke_input_snapshot*, ke_result>)slot[0].on_input)(entity, &s);
        Assert.True(input);

        // Destroy
        ((delegate* unmanaged[Cdecl]<ulong, ke_result>)slot[0].on_destroy)(entity);
        Assert.True(destroy);
    }

    [Fact]
    public void Unregister_RemovesCallbacks()
    {
        ScriptBridge.ClearForTesting();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var reg = (EcsRegistry)world.Registry;
        var entity = reg.CreateEntity();
        
        bool called = false;
        ScriptBridge.Register(reg, world.ScriptComponentId, entity, onAwake: () => called = true);
        
        var slot = reg.GetComponent<ke_script_component>(entity, world.ScriptComponentId);
        var func = (delegate* unmanaged[Cdecl]<ulong, ke_result>)slot[0].on_awake;

        ScriptBridge.Unregister(entity);
        
        func(entity); // Should not call the delegate anymore
        Assert.False(called);
    }
}
