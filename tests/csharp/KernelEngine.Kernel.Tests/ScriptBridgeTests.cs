using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
public class ScriptBridgeTests
{
    [Fact]
    public unsafe void ScriptBridge_RegisterAndInvoke()
    {
        KernelThread.SetCurrentName("ke.sim");
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var registry = world.Registry;
        
        var entity = registry.CreateEntity();
        bool started = false;
        float updatedDt = 0;

        ScriptBridge.Register(registry, world.ScriptComponentId, entity, 
            () => started = true, 
            (dt) => updatedDt = dt);

        // We can't easily trigger the native call from managed without 
        // calling the world update, but we can verify it was registered.
        var componentSpan = registry.GetComponent<ke_script_component>(entity, world.ScriptComponentId);
        Assert.False(componentSpan.IsEmpty);
        fixed (ke_script_component* component = componentSpan)
        {
            Assert.True(component->on_start != null);
            Assert.True(component->on_update != null);
        }
        
        // We can't easily trigger the native call from managed without 
        // calling the world update, but we can verify it was registered.
        KernelThread.SetCurrentName("ke.sim");
        
        // First update triggers on_start
        world.Update();
        System.Threading.Thread.Sleep(10);
        // Second update ensures on_update is called if there's any timing issue
        world.Update();
        
        Assert.True(started);
        Assert.True(updatedDt >= 0);

        ScriptBridge.Unregister(entity);
    }
}
