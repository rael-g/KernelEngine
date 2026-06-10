using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class KernelAbstractionsTests
{
    [Fact]
    public void InputContext_Current_ThrowsWhenNotSet()
    {
        InputContext.Set(null);
        Assert.Throws<InvalidOperationException>(() => InputContext.Current);
    }

    [Fact]
    public void InputContext_Set_Works()
    {
        var mock = Substitute.For<IInputReader>();
        InputContext.Set(mock);
        Assert.Same(mock, InputContext.Current);
        InputContext.Set(null);
    }

    [Fact]
    public void KernelException_ThrowIfFailed_DoesNotThrowOnOk()
    {
        KernelException.ThrowIfFailed(KernelResult.Ok);
    }

    [Fact]
    public void KernelException_ThrowIfFailed_ThrowsOnError()
    {
        Assert.Throws<KernelException>(() => KernelException.ThrowIfFailed(KernelResult.Error, "context"));
    }

    [Fact]
    public void KernelException_Constructor_SetsMessage()
    {
        var ex = new KernelException(KernelResult.Io, "test");
        Assert.Equal(KernelResult.Io, ex.Result);
        Assert.Contains("Io", ex.Message);
        Assert.Contains("test", ex.Message);
    }
}
