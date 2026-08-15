
using Xunit;

namespace EngineTests;

public class LoggerTests
{
    [Fact]
    public void Logger_CanBeCreatedAndDestroyed()
    {        var logger = new Logger();
    }

    [Fact]
    public void Logger_CanLogWithSink()
    {        var logger = new Logger();
        var sink = new RecordingSink();
        logger.AddSink(sink);

        logger.Info("Testing C# logger interop", "TEST");

        Assert.Contains(sink.Entries, e => e.Tag == "Testing C# logger interop" && e.Message == "TEST");
    }

    private sealed class RecordingSink : ILoggerSink
    {
        public LogLevel MinLevel => LogLevel.Trace;
        public List<(LogLevel Level, string Tag, string Message)> Entries { get; } = [];
        public void Log(LogLevel level, string tag, string message) => Entries.Add((level, tag, message));
    }
}
