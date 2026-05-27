using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;
using Xunit;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
public unsafe class WorldDetailsTests
{
    private static int _nativeUpdateCalled = 0;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockSystemUpdate(void* handle, ke_world* world, float dt, ke_frame_packet* packet)
    {
        _nativeUpdateCalled++;
    }

    [Fact]
    public void AddSystem_Native_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);

        var parameters = new ke_system_params
        {
            name = (sbyte*)Marshal.StringToHGlobalAnsi("NativeTest"),
            update = &MockSystemUpdate,
            handle = null
        };

        try
        {
            world.AddSystem(parameters);
            
            // Trigger update to see if native system is called
            KernelThread.SetCurrentName("ke.sim");
            world.Update();
            
            Assert.True(_nativeUpdateCalled > 0);
        }
        finally
        {
            Marshal.FreeHGlobal((IntPtr)parameters.name);
        }
    }

    [Fact]
    public void ScriptRegistration_Works()
    {
        KernelThread.SetCurrentName("ke.sim");
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        bool started = false;
        world.RegisterScript(1, () => started = true, dt => { });
        
        // World.Update calls ScriptSystem which should call our bridge
        // Needs 2 updates: one to detect and call on_start, one to ensure it's processed.
        world.Update();
        world.Update();
        
        Assert.True(started);
        world.UnregisterScript(1);
    }
}
