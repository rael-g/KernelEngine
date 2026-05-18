using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class KernelExceptionTests
{
    [Fact]
    public void ThrowIfFailed_DoesNothing_WhenOk()
    {
        KernelException.ThrowIfFailed(KernelResult.Ok);
        // Should not throw
    }

    [Fact]
    public void ThrowIfFailed_Throws_WhenNotOk()
    {
        var ex = Assert.Throws<KernelException>(() => 
            KernelException.ThrowIfFailed(KernelResult.InvalidArgument));
        Assert.Equal(KernelResult.InvalidArgument, ex.Result);
    }

    [Fact]
    public void Constructor_SetsMessageWithContext()
    {
        var ex = new KernelException(KernelResult.OutOfMemory, "TestContext");
        Assert.Contains("KE_ERROR_OUT_OF_MEMORY", ex.Message);
        Assert.Contains("TestContext", ex.Message);
    }

    [Fact]
    public void Constructor_SetsMessageWithoutContext()
    {
        var ex = new KernelException(KernelResult.NotFound);
        Assert.Contains("NotFound", ex.Message);
    }

    [Fact]
    public void Constructor_HandlesUnknownError()
    {
        var ex = new KernelException((KernelResult)9999);
        Assert.Contains("9999", ex.Message);
    }
}
