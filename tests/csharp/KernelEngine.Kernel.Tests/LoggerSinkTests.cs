using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class LoggerSinkTests
{
    [Fact]
    public void CustomSink_ReceivesLogEvents()
    {
        using var allocator = new MallocAllocator();
        using var logger = new Logger();
        var mockSink = Substitute.For<ILoggerSink>();
        
        logger.AddSink(mockSink, LogLevel.Info);
        
        logger.Info("TestTag", "Hello Info");
        logger.Trace("TestTag", "Hello Trace"); // Below minLevel

        mockSink.Received(1).Log(LogLevel.Info, "TestTag", "Hello Info");
        mockSink.DidNotReceive().Log(LogLevel.Trace, Arg.Any<string>(), Arg.Any<string>());
    }

    [Fact]
    public void Flush_CallsSinkFlush()
    {
        using var allocator = new MallocAllocator();
        using var logger = new Logger();
        var mockSink = Substitute.For<ILoggerSink>();
        
        logger.AddSink(mockSink);
        logger.Flush();

        mockSink.Received(1).Flush();
    }

    [Fact]
    public void AllLogLevelMethods_ForwardCorrectLevel()
    {
        using var allocator = new MallocAllocator();
        using var logger = new Logger();
        var mockSink = Substitute.For<ILoggerSink>();
        logger.AddSink(mockSink);

        logger.Trace("T", "m");
        logger.Debug("T", "m");
        logger.Info("T", "m");
        logger.Warning("T", "m");
        logger.Error("T", "m");
        logger.Critical("T", "m");

        mockSink.Received(1).Log(LogLevel.Trace, "T", "m");
        mockSink.Received(1).Log(LogLevel.Debug, "T", "m");
        mockSink.Received(1).Log(LogLevel.Info, "T", "m");
        mockSink.Received(1).Log(LogLevel.Warning, "T", "m");
        mockSink.Received(1).Log(LogLevel.Error, "T", "m");
        mockSink.Received(1).Log(LogLevel.Critical, "T", "m");
    }
}
