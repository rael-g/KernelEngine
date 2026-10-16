using KernelEngine.Configuration;

using Microsoft.Extensions.DependencyInjection;

using NSubstitute;

using Xunit;

namespace EngineTests;

public class ServiceCollectionExtensionsTests
{
    [Fact]
    public void AddLogger_RegistersLogger()
    {
        var services = new ServiceCollection();
        services.AddLogger();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Logger>());
        Assert.NotNull(provider.GetService<ILogger>());
    }

    [Fact]
    public void AddConsoleSink_RegistersSinkWithDefaultLevel()
    {
        var services = new ServiceCollection();
        services.AddConsoleSink();
        var provider = services.BuildServiceProvider();

        var sink = provider.GetService<ILoggerSink>();
        Assert.NotNull(sink);
        Assert.Equal(LogLevel.Trace, sink.MinLevel);
    }

    [Fact]
    public void AddConsoleSink_WithMinLevel_RegistersSinkWithSpecifiedLevel()
    {
        var services = new ServiceCollection();
        services.AddConsoleSink(LogLevel.Error);
        var provider = services.BuildServiceProvider();

        var sink = provider.GetRequiredService<ILoggerSink>();
        Assert.Equal(LogLevel.Error, sink.MinLevel);
    }

    [Fact]
    public void AddLogger_AttachesEachSinkAtItsOwnMinimumLevel()
    {
        var sink = Substitute.For<ILoggerSink>();
        sink.MinLevel.Returns(LogLevel.Error);
        var services = new ServiceCollection();
        services.AddSingleton(sink);
        services.AddLogger();
        using var provider = services.BuildServiceProvider();

        var logger = provider.GetRequiredService<ILogger>();
        logger.Info("T", "below");
        logger.Error("T", "at");

        sink.Received(1).Log(LogLevel.Error, "T", "at");
        sink.DidNotReceive().Log(LogLevel.Info, Arg.Any<string>(), Arg.Any<string>());
    }

    [Fact]
    public void AddInput_RegistersInput()
    {
        var services = new ServiceCollection();
        services.AddLogger();
        services.AddInput();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Input>());
        Assert.NotNull(provider.GetService<IInput>());
    }
}
