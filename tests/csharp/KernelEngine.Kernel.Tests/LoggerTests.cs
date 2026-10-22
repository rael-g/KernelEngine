
using System;

using Xunit;

namespace EngineTests;

public class LoggerTests
{
    [Fact]
    public void Logger_CanLogWithSink()
    {
        var logger = new Logger();
        var sink = new RecordingSink();
        logger.AddSink(sink);

        logger.Info("TestTag", "Testing C# logger interop");

        Assert.Contains(sink.Entries, e => e.Tag == "TestTag" && e.Message == "Testing C# logger interop");
    }

    [Fact]
    public unsafe void A_line_a_native_library_hands_its_log_callback_reaches_the_logger()
    {
        var logger = new Logger();
        var sink = new RecordingSink();
        logger.AddSink(sink);

        var scope = "render_forward\0"u8.ToArray();
        var message = "pipeline compiled\0"u8.ToArray();
        fixed (byte* s = scope, m = message)
            LogCallbackNative.Pointer(LogCallbackNative.Pin(logger.Log), KernelEngine.Logger.Native.ke_log_level.KE_LOG_LEVEL_WARNING, (sbyte*)s, (sbyte*)m);

        Assert.Contains(sink.Entries, e => e.Level == LogLevel.Warning && e.Tag == "render_forward" && e.Message == "pipeline compiled");
    }

    private sealed class RecordingSink : ILoggerSink
    {
        public LogLevel MinLevel => LogLevel.Trace;
        public List<(LogLevel Level, string Tag, string Message)> Entries { get; } = [];
        public void Log(LogLevel level, string tag, string message) => Entries.Add((level, tag, message));
    }
}
