using KernelEngine;
using KernelEngine.Result.Native;

using Xunit;

namespace EngineTests;

public class NativeResultsTests
{
    [Fact]
    public void A_call_that_returned_ok_throws_nothing()
    {
        NativeResults.ThrowIfFailed(ke_result.KE_OK, "probe_call");
    }

    [Fact]
    public void A_general_code_becomes_the_exception_the_convention_names_for_it()
    {
        var thrown = Assert.Throws<KeyNotFoundException>(() => NativeResults.ThrowIfFailed(ke_result.KE_RESULT_NOT_FOUND, "probe_call"));
        Assert.Contains("probe_call", thrown.Message);
        Assert.Contains("KE_RESULT_NOT_FOUND", thrown.Message);
    }

    [Fact]
    public void A_code_the_convention_does_not_name_becomes_the_general_exception()
    {
        var unknown = (ke_result)((10u << 16) | 99u);
        var thrown = Assert.Throws<InvalidOperationException>(() => NativeResults.ThrowIfFailed(unknown, "probe_call"));
        Assert.Contains("0x000a0063", thrown.Message);
    }
}
