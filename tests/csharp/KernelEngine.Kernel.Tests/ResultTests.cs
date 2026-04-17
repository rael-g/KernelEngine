using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ResultTests
{
    [Fact]
    public void SuccessResult_IsOk()
    {
        var result = new Result(ke_result.KE_OK);
        Assert.True(result.IsOk);
        Assert.False(result.IsError);
    }

    [Fact]
    public void FailureResult_IsError()
    {
        var result = new Result(ke_result.KE_ERROR_INVALID_ARGUMENT);
        Assert.False(result.IsOk);
        Assert.True(result.IsError);
        Assert.Equal(ke_result.KE_ERROR_INVALID_ARGUMENT, result.Code);
    }

    [Fact]
    public void SuccessResultWithValue_HasValue()
    {
        var result = new Result<int>(ke_result.KE_OK, 42);
        Assert.True(result.IsOk);
        Assert.Equal(42, result.Value);
    }

    [Fact]
    public void FailureResult_ThrowsOnValueAccess()
    {
        var result = new Result<int>(ke_result.KE_ERROR_OUT_OF_MEMORY);
        Assert.Throws<KernelException>(() => result.Value);
    }

    [Fact]
    public void ResultT_ImplicitConversionToResult_Works()
    {
        Result<int> rt = ke_result.KE_ERROR_IO;
        Result r = rt;
        Assert.Equal(ke_result.KE_ERROR_IO, r.Code);
    }

    [Fact]
    public void ResultT_ToString_Works()
    {
        Result<int> ok = new(ke_result.KE_OK, 42);
        Result<int> err = ke_result.KE_ERROR_NOT_FOUND;
        
        Assert.Contains("Ok(42)", ok.ToString());
        Assert.Contains("Error(KE_ERROR_NOT_FOUND)", err.ToString());
    }

    [Fact]
    public void Result_ToString_Works()
    {
        Result r = ke_result.KE_OK;
        Assert.Equal("KE_OK", r.ToString());
    }

    [Fact]
    public void Result_ThrowIfFailed_Works()
    {
        Result ok = ke_result.KE_OK;
        ok.ThrowIfFailed(); // Should not throw

        Result err = ke_result.KE_ERROR;
        Assert.Throws<KernelException>(() => err.ThrowIfFailed());
    }
}
