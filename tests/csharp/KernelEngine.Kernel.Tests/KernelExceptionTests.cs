using KernelEngine.Kernel;
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
        Assert.Throws<KernelException>(() => 
            KernelException.ThrowIfFailed(KernelResult.InvalidArgument));
    }

    [Fact]
    public void ThrowIfFailed_SetsCorrectResult_WhenNotOk()
    {
        var ex = Assert.Throws<KernelException>(() => 
            KernelException.ThrowIfFailed(KernelResult.InvalidArgument));
        Assert.Equal(KernelResult.InvalidArgument, ex.Result);
    }

    [Fact]
    public void Constructor_SetsMessageWithResultName()
    {
        var ex = new KernelException(KernelResult.OutOfMemory, "TestContext");
        Assert.Contains("OutOfMemory", ex.Message);
    }

    [Fact]
    public void Constructor_SetsMessageWithContextName()
    {
        var ex = new KernelException(KernelResult.OutOfMemory, "TestContext");
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
