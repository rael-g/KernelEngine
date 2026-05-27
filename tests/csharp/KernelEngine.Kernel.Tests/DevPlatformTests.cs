using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class DevPlatformTests
{
    [Fact]
    public void DevPlatform_CanBeCreatedAndDisposed()
    {
        var vtable = new ke_dev_platform();
        var devPlatform = new DevPlatform(&vtable);
        devPlatform.Dispose();
    }

    [Fact]
    public void DevPlatform_NullNative_NoOps()
    {
        var devPlatform = new DevPlatform(null);
        devPlatform.SetOsThreadName("Test");
        devPlatform.Dispose();
    }

    [Fact]
    public void DevPlatform_NullDestroyFn_DoesNotCrashOnDispose()
    {
        var vtable = new ke_dev_platform();
        vtable.destroy = null;
        var devPlatform = new DevPlatform(&vtable);
        devPlatform.Dispose();
    }

    [Fact]
    public void DevPlatform_NullSetThreadNameFn_NoOps()
    {
        var vtable = new ke_dev_platform();
        vtable.set_thread_name = null;
        var devPlatform = new DevPlatform(&vtable);
        devPlatform.SetOsThreadName("Test");
        devPlatform.Dispose();
    }

    [Fact]
    public void DevPlatform_AccessNative_ThrowsWhenDisposed()
    {
        var vtable = new ke_dev_platform();
        var devPlatform = new DevPlatform(&vtable);
        devPlatform.Dispose();
        Assert.Throws<ObjectDisposedException>(() => _ = devPlatform.Native);
    }

    [Fact]
    public void DevPlatform_SetOsThreadName_DoesNotCrash()
    {
        var vtable = new ke_dev_platform();
        vtable.set_thread_name = null; // No-op
        
        var devPlatform = new DevPlatform(&vtable);
        devPlatform.SetOsThreadName("TestThread");
        
        devPlatform.Dispose();
    }
}
