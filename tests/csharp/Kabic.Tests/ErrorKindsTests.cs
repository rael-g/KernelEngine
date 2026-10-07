using Kabic.Pipeline;

namespace Kabic.Tests;

public sealed class ErrorKindsTests
{
    static Convention With(Action<ConventionBuilder> declare)
    {
        var builder = new ConventionBuilder()
            .Symbols("my_", "_handle", "_create", "_component", "_params")
            .Booleans("my_bool")
            .Failure("my_error", "my_error_type", "my_error_is", "MY_ERROR_GENERAL",
                "", [], "NativeErrors", "MyGame", "");
        declare(builder);
        return builder.Build();
    }

    [Fact]
    public void WithoutAnyKindEveryFailureIsAPlainException()
    {
        var text = Generation.ErrorKinds(With(_ => { }));

        Assert.Contains("new Exception(message, cause)", text);
        Assert.DoesNotContain("case ", text);
    }

    [Fact]
    public void AKindNamesTheExceptionItBecomes()
    {
        var text = Generation.ErrorKinds(With(b => b.AddError("MY_ERROR_BUSY", "my.error.busy", "TimeoutException")));

        Assert.Contains("case \"my.error.busy\":", text);
        Assert.Contains("new TimeoutException(message, cause)", text);
    }

    [Fact]
    public void ACustomExceptionIsDeclaredBesideTheMapping()
    {
        var text = Generation.ErrorKinds(With(b =>
            b.AddError("MY_ERROR_INVALID", "my.error.invalid", "MyInvalidArgumentException", extends: "ArgumentException")));

        Assert.Contains("new MyInvalidArgumentException(message, cause)", text);
        Assert.Contains("public class MyInvalidArgumentException : ArgumentException", text);
        Assert.Contains("public MyInvalidArgumentException(string message, Exception? innerException)", text);
    }

    [Fact]
    public void TheGeneralKindMayBeDeclaredToo()
    {
        var text = Generation.ErrorKinds(With(b =>
            b.AddError("MY_ERROR_GENERAL", "my.error", "MyEngineException", "General", extends: "InvalidOperationException")));

        Assert.Contains("new MyEngineException(message, cause);", text);
        Assert.DoesNotContain("case \"my.error\"", text);
    }

    [Fact]
    public void TheZigNameDefaultsToTheLastSegmentOfTheNativeName()
    {
        var convention = With(b => b.AddError("MY_ERROR_OUT_OF_SPACE", "my.error.out_of_space", "IOException"));

        Assert.Equal("OutOfSpace", convention.NamedErrors.Single().Zig);
    }
}
