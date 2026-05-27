using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ResultTests
{
    [Fact]
    public void SuccessResult_IsOk()
    {
        var result = new Result(KernelResult.Ok);
        Assert.True(result.IsOk);
        Assert.False(result.IsError);
    }

    [Fact]
    public void FailureResult_IsError()
    {
        var result = new Result(KernelResult.InvalidArgument);
        Assert.False(result.IsOk);
        Assert.True(result.IsError);
        Assert.Equal(KernelResult.InvalidArgument, result.Code);
    }

    [Fact]
    public void FailedResultT_AccessValue_Throws()
    {
        var result = new Result<int>(KernelResult.NotFound);
        Assert.Throws<KernelException>(() => result.Value);
    }

    [Fact]
    public void ResultT_ImplicitConversion_FromValue()
    {
        Result<int> result = 42;
        Assert.True(result.IsOk);
        Assert.Equal(42, result.Value);
    }

    [Fact]
    public void ResultT_ImplicitConversion_ToPlainResult()
    {
        var resultT = new Result<int>(KernelResult.Ok, 42);
        Result result = resultT;
        Assert.True(result.IsOk);
    }

    [Fact]
    public void Result_ToString_ReturnsCorrectFormat()
    {
        Assert.Equal("Ok", Result.Ok().ToString());
        Assert.Equal("Error(NotFound)", Result.Error(KernelResult.NotFound).ToString());
        
        var resultT = new Result<int>(KernelResult.Ok, 123);
        Assert.Equal("Ok(123)", resultT.ToString());
    }

    [Fact]
    public void ResultT_IsError_Works()
    {
        var result = new Result<int>(KernelResult.Error);
        Assert.True(result.IsError);
        Assert.False(result.IsOk);
    }

    [Fact]
    public void ResultT_ImplicitConversion_ToPlainResult_MaintainsCode()
    {
        var resultT = new Result<int>(KernelResult.InvalidArgument, 0);
        Result result = resultT;
        Assert.Equal(KernelResult.InvalidArgument, result.Code);
    }

    [Fact]
    public void Result_ThrowIfFailed_Works()
    {
        Result ok = KernelResult.Ok;
        ok.ThrowIfFailed(); // Should not throw

        Result err = KernelResult.Error;
        Assert.Throws<KernelException>(() => err.ThrowIfFailed());
    }
}
