using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class KernelExceptionTests
{
    [Fact]
    public void ThrowIfFailed_DoesNothing_WhenOk()
    {
        KernelException.ThrowIfFailed(ke_result.KE_OK);
        // Should not throw
    }

    [Fact]
    public void ThrowIfFailed_Throws_WhenNotOk()
    {
        var ex = Assert.Throws<KernelException>(() => 
            KernelException.ThrowIfFailed(ke_result.KE_ERROR_INVALID_ARGUMENT));
        Assert.Equal(ke_result.KE_ERROR_INVALID_ARGUMENT, ex.Result);
    }

    [Fact]
    public void Constructor_SetsMessageWithContext()
    {
        var ex = new KernelException(ke_result.KE_ERROR_OUT_OF_MEMORY, "TestContext");
        Assert.Contains("KE_ERROR_OUT_OF_MEMORY", ex.Message);
        Assert.Contains("TestContext", ex.Message);
    }

    [Fact]
    public void Constructor_SetsMessageWithoutContext()
    {
        var ex = new KernelException(ke_result.KE_ERROR_NOT_FOUND);
        Assert.Contains("KE_ERROR_NOT_FOUND", ex.Message);
    }

    [Fact]
    public void Constructor_HandlesUnknownError()
    {
        var ex = new KernelException((ke_result)9999);
        Assert.Contains("UNKNOWN_ERROR(9999)", ex.Message);
    }
}
