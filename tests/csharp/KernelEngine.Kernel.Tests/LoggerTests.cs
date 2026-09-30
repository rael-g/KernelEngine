
using System;
using Xunit;

namespace EngineTests;

public class LoggerTests
{
    [Fact]
    public void Logger_RefusesToBeUsedOnceDisposed()
    {
        var logger = new Logger();
        logger.Dispose();
        Assert.Throws<ObjectDisposedException>(() => logger.Info("Tag", "after dispose"));
    }

    [Fact]
    public void Logger_DisposeIsIdempotent()
    {
        var logger = new Logger();
        logger.Dispose();
        logger.Dispose();
    }

    [Fact]
    public void Logger_CanLogWithSink()
    {
        using var logger = new Logger();
        var sink = new RecordingSink();
        logger.AddSink(sink);

        logger.Info("TestTag", "Testing C# logger interop");

        Assert.Contains(sink.Entries, e => e.Tag == "TestTag" && e.Message == "Testing C# logger interop");
    }

    private sealed class RecordingSink : ILoggerSink
    {
        public LogLevel MinLevel => LogLevel.Trace;
        public List<(LogLevel Level, string Tag, string Message)> Entries { get; } = [];
        public void Log(LogLevel level, string tag, string message) => Entries.Add((level, tag, message));
    }
}
