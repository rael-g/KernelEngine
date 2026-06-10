using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ResultTests
{
    [Fact]
    public void SuccessResult_IsOk()
    {
        var result = new Result(KernelResult.Ok);
        Assert.True(result.IsOk);
    }

    [Fact]
    public void SuccessResult_IsNotError()
    {
        var result = new Result(KernelResult.Ok);
        Assert.False(result.IsError);
    }

    [Fact]
    public void FailureResult_IsNotOk()
    {
        var result = new Result(KernelResult.InvalidArgument);
        Assert.False(result.IsOk);
    }

    [Fact]
    public void FailureResult_IsError()
    {
        var result = new Result(KernelResult.InvalidArgument);
        Assert.True(result.IsError);
    }

    [Fact]
    public void FailureResult_RetainsCode()
    {
        var result = new Result(KernelResult.InvalidArgument);
        Assert.Equal(KernelResult.InvalidArgument, result.Code);
    }

    [Fact]
    public void FailedResultT_AccessValue_Throws()
    {
        var result = new Result<int>(KernelResult.NotFound);
        Assert.Throws<KernelException>(() => result.Value);
    }

    [Fact]
    public void ResultT_ImplicitConversion_FromValue_IsOk()
    {
        Result<int> result = 42;
        Assert.True(result.IsOk);
    }

    [Fact]
    public void ResultT_ImplicitConversion_FromValue_HoldsValue()
    {
        Result<int> result = 42;
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
    public void ResultOk_ToString_ReturnsOk()
    {
        Assert.Equal("Ok", Result.Ok().ToString());
    }

    [Fact]
    public void ResultError_ToString_ReturnsFormat()
    {
        Assert.Equal("Error(NotFound)", Result.Error(KernelResult.NotFound).ToString());
    }

    [Fact]
    public void ResultTOk_ToString_ReturnsFormat()
    {
        var resultT = new Result<int>(KernelResult.Ok, 123);
        Assert.Equal("Ok(123)", resultT.ToString());
    }

    [Fact]
    public void ResultT_IsError_IsTrue()
    {
        var result = new Result<int>(KernelResult.Error);
        Assert.True(result.IsError);
    }

    [Fact]
    public void ResultT_IsError_IsNotOk()
    {
        var result = new Result<int>(KernelResult.Error);
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
    public void ResultOk_ThrowIfFailed_DoesNotThrow()
    {
        Result ok = KernelResult.Ok;
        ok.ThrowIfFailed(); // Should not throw
    }

    [Fact]
    public void ResultError_ThrowIfFailed_Throws()
    {
        Result err = KernelResult.Error;
        Assert.Throws<KernelException>(() => err.ThrowIfFailed());
    }

    [Fact]
    public void Result_Equals_ReturnsTrue_ForSameCode()
    {
        var r1 = new Result(KernelResult.Ok);
        var r2 = new Result(KernelResult.Ok);
        Assert.True(r1.Equals(r2));
    }

    [Fact]
    public void Result_Equals_ReturnsFalse_ForDifferentCode()
    {
        var r1 = new Result(KernelResult.Ok);
        var r2 = new Result(KernelResult.InvalidArgument);
        Assert.False(r1.Equals(r2));
    }

    [Fact]
    public void Result_GetHashCode_IsSame_ForSameCode()
    {
        var r1 = new Result(KernelResult.Ok);
        var r2 = new Result(KernelResult.Ok);
        Assert.Equal(r1.GetHashCode(), r2.GetHashCode());
    }

    [Fact]
    public void Result_EqualityOperator_ReturnsTrue_ForSameCode()
    {
        var r1 = new Result(KernelResult.Ok);
        var r2 = new Result(KernelResult.Ok);
        Assert.True(r1 == r2);
    }

    [Fact]
    public void Result_InequalityOperator_ReturnsTrue_ForDifferentCode()
    {
        var r1 = new Result(KernelResult.Ok);
        var r2 = new Result(KernelResult.InvalidArgument);
        Assert.True(r1 != r2);
    }

    [Fact]
    public void ResultT_Equals_ReturnsTrue_ForSameCodeAndValue()
    {
        var r1 = new Result<int>(KernelResult.Ok, 42);
        var r2 = new Result<int>(KernelResult.Ok, 42);
        Assert.True(r1.Equals(r2));
    }

    [Fact]
    public void ResultT_Equals_ReturnsFalse_ForDifferentValue()
    {
        var r1 = new Result<int>(KernelResult.Ok, 42);
        var r2 = new Result<int>(KernelResult.Ok, 99);
        Assert.False(r1.Equals(r2));
    }

    [Fact]
    public void ResultT_GetHashCode_IsSame_ForSameCodeAndValue()
    {
        var r1 = new Result<int>(KernelResult.Ok, 42);
        var r2 = new Result<int>(KernelResult.Ok, 42);
        Assert.Equal(r1.GetHashCode(), r2.GetHashCode());
    }

    [Fact]
    public void ResultT_EqualityOperator_ReturnsTrue_ForSameCodeAndValue()
    {
        var r1 = new Result<int>(KernelResult.Ok, 42);
        var r2 = new Result<int>(KernelResult.Ok, 42);
        Assert.True(r1 == r2);
    }

    [Fact]
    public void ResultT_InequalityOperator_ReturnsTrue_ForDifferentValue()
    {
        var r1 = new Result<int>(KernelResult.Ok, 42);
        var r2 = new Result<int>(KernelResult.Ok, 99);
        Assert.True(r1 != r2);
    }
}
