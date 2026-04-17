using KernelEngine.Kernel.Native;
using KernelEngine.Logging.Serilog;
using Moq;
using Serilog;
using Serilog.Events;
using Xunit;

namespace KernelEngine.Logging.Serilog.Tests;

public class SerilogSinkTests
{
    [Fact]
    public void Log_Information_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_INFO, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Information, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Error_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_ERROR, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Error, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Critical_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_CRITICAL, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Fatal, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Debug_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_DEBUG, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Debug, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Warning_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_WARNING, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Warning, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Trace_LevelMapping()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log(ke_log_level.KE_LOG_LEVEL_TRACE, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Verbose, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Log_Unknown_LevelMapping_DefaultsToInformation()
    {
        var mockLogger = new Mock<ILogger>();
        mockLogger.Setup(x => x.ForContext(It.IsAny<string>(), It.IsAny<object>(), It.IsAny<bool>())).Returns(mockLogger.Object);
        var sink = new SerilogSink(mockLogger.Object);
        
        sink.Log((ke_log_level)999, "TEST", "Message");
        
        mockLogger.Verify(x => x.Write(LogEventLevel.Information, It.IsAny<string>(), "TEST", "Message"), Times.Once);
    }

    [Fact]
    public void Constructor_NullLogger_UsesGlobalSerilog()
    {
        var sink = new SerilogSink(null);
        Assert.NotNull(sink);
    }
}
