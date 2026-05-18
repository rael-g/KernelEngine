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
    public void SuccessResultWithValue_HasValue()
    {
        var result = new Result<int>(KernelResult.Ok, 42);
        Assert.True(result.IsOk);
        Assert.Equal(42, result.Value);
    }

    [Fact]
    public void FailureResult_ThrowsOnValueAccess()
    {
        var result = new Result<int>(KernelResult.OutOfMemory);
        Assert.Throws<KernelException>(() => result.Value);
    }

    [Fact]
    public void ResultT_ImplicitConversionToResult_Works()
    {
        Result<int> rt = KernelResult.Io;
        Result r = rt;
        Assert.Equal(KernelResult.Io, r.Code);
    }

    [Fact]
    public void ResultT_ToString_Works()
    {
        Result<int> ok = new(KernelResult.Ok, 42);
        Result<int> err = KernelResult.NotFound;
        
        Assert.Contains("Ok(42)", ok.ToString());
        Assert.Contains("Error(KE_ERROR_NOT_FOUND)", err.ToString());
    }

    [Fact]
    public void Result_ToString_Works()
    {
        Result r = KernelResult.Ok;
        Assert.Equal("KE_OK", r.ToString());
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
