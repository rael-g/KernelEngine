using Xunit;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using KernelEngine.Configuration;
using NSubstitute;

namespace EngineTests;

public class ServiceCollectionExtensionsTests
{
    [Fact]
    public void AddKernel_RegistersEssentialServices()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<IKernelFactory>());
    }

    [Fact]
    public void AddLogger_RegistersLogger()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        services.AddLogger();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Logger>());
        Assert.NotNull(provider.GetService<ILogger>());
    }

    [Fact]
    public void AddConsoleSink_RegistersSinkWithDefaultLevel()
    {
        var services = new ServiceCollection();
        // ConsoleSink needs IProjectConfig for AddProjectConfigSection
        var config = Substitute.For<IProjectConfig>();
        services.AddSingleton(config);
        
        services.AddConsoleSink();
        var provider = services.BuildServiceProvider();

        var sink = provider.GetService<ILoggerSink>();
        Assert.NotNull(sink);
        Assert.IsType<ConsoleSink>(sink);
        Assert.Equal(LogLevel.Trace, ((ConsoleSink)sink).MinLevel);
    }

    [Fact]
    public void AddConsoleSink_WithMinLevel_RegistersSinkWithSpecifiedLevel()
    {
        var services = new ServiceCollection();
        var config = Substitute.For<IProjectConfig>();
        services.AddSingleton(config);

        services.AddConsoleSink(LogLevel.Error);
        var provider = services.BuildServiceProvider();

        var sink = (ConsoleSink)provider.GetRequiredService<ILoggerSink>();
        Assert.Equal(LogLevel.Error, sink.MinLevel);
    }

    [Fact]
    public void AddInput_RegistersInput()
    {
        var services = new ServiceCollection();
        services.AddKernel();
        services.AddLogger();
        services.AddInput();
        var provider = services.BuildServiceProvider();

        Assert.NotNull(provider.GetService<Input>());
        Assert.NotNull(provider.GetService<IInput>());
    }
}
