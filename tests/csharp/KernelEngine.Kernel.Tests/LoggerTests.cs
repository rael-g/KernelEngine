using Microsoft.Extensions.Logging;

using Xunit;

namespace EngineTests;

public class LoggerTests
{
    [Fact]
    public unsafe void A_line_a_native_library_logs_reaches_the_logger_factory_under_its_scope_at_its_level()
    {
        var provider = new RecordingProvider();
        using var factory = LoggerFactory.Create(logging => logging.AddProvider(provider).SetMinimumLevel(Microsoft.Extensions.Logging.LogLevel.Trace));

        var scope = "render_forward\0"u8.ToArray();
        var message = "pipeline compiled\0"u8.ToArray();
        fixed (byte* s = scope, m = message)
            NativeLogging.Callback(NativeLogging.ContextOf(factory), KernelEngine.Logger.LogLevel.Warning, (sbyte*)s, (sbyte*)m);

        Assert.Contains(provider.Entries, e => e.Level == Microsoft.Extensions.Logging.LogLevel.Warning && e.Category == "render_forward" && e.Message == "pipeline compiled");
    }

    [Fact]
    public void The_same_factory_always_yields_the_same_native_context()
    {
        using var factory = LoggerFactory.Create(_ => { });
        unsafe
        {
            Assert.True(NativeLogging.ContextOf(factory) == NativeLogging.ContextOf(factory));
        }
    }

    private sealed class RecordingProvider : ILoggerProvider
    {
        public List<(string Category, Microsoft.Extensions.Logging.LogLevel Level, string Message)> Entries { get; } = [];

        public Microsoft.Extensions.Logging.ILogger CreateLogger(string categoryName) => new Recorder(this, categoryName);

        public void Dispose() { }

        private sealed class Recorder(RecordingProvider owner, string category) : Microsoft.Extensions.Logging.ILogger
        {
            public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;
            public bool IsEnabled(Microsoft.Extensions.Logging.LogLevel logLevel) => true;
            public void Log<TState>(Microsoft.Extensions.Logging.LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter) =>
                owner.Entries.Add((category, logLevel, formatter(state, exception)));
        }
    }
}
