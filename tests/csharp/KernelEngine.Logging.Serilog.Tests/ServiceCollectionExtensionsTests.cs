using KernelEngine.Logging.Serilog;
using Microsoft.Extensions.DependencyInjection;
using Moq;
using Serilog;
using Xunit;

namespace KernelEngine.Logging.Serilog.Tests;

public class ServiceCollectionExtensionsTests
{
    [Fact]
    public void AddSerilogSink_RegistersService()
    {
        var services = new ServiceCollection();
        services.AddSerilogSink();
        
        var provider = services.BuildServiceProvider();
        var sink = provider.GetService<Kernel.ILoggerSink>();
        
        Assert.NotNull(sink);
    }

    [Fact]
    public void AddSerilogSink_RegistersCorrectType()
    {
        var services = new ServiceCollection();
        services.AddSerilogSink();
        
        var provider = services.BuildServiceProvider();
        var sink = provider.GetService<Kernel.ILoggerSink>();
        
        Assert.IsType<SerilogSink>(sink);
    }

    [Fact]
    public void AddSerilogSink_WithLogger_RegistersService()
    {
        var services = new ServiceCollection();
        var mockLogger = new Mock<ILogger>().Object;
        services.AddSerilogSink(mockLogger);
        
        var provider = services.BuildServiceProvider();
        var sink = provider.GetService<Kernel.ILoggerSink>();
        
        Assert.NotNull(sink);
    }
}
