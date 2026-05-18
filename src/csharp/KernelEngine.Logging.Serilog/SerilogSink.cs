using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Serilog.Events;
using ILogger = Serilog.ILogger;

namespace KernelEngine.Logging.Serilog;

/// <summary>
/// Routes native kernel log events to a Serilog <see cref="ILogger"/>.
/// </summary>
public sealed class SerilogSink : ILoggerSink
{
    private readonly ILogger _logger;

    /// <inheritdoc/>
    public LogLevel MinLevel { get; init; } = LogLevel.Trace;

    /// <param name="logger">
    /// The Serilog logger to write to. Defaults to <see cref="global::Serilog.Log.Logger"/>.
    /// </param>
    public SerilogSink(ILogger? logger = null)
    {
        _logger = logger ?? global::Serilog.Log.Logger;
    }

    /// <inheritdoc/>
    public void Log(LogLevel level, string tag, string message)
    {
        var serilogLevel = level switch
        {
            LogLevel.Trace    => LogEventLevel.Verbose,
            LogLevel.Debug    => LogEventLevel.Debug,
            LogLevel.Info     => LogEventLevel.Information,
            LogLevel.Warning  => LogEventLevel.Warning,
            LogLevel.Error    => LogEventLevel.Error,
            LogLevel.Critical => LogEventLevel.Fatal,
            _                                  => LogEventLevel.Information,
        };

        _logger.ForContext("Tag", tag).Write(serilogLevel, "[{Tag}] {Message}", tag, message);
    }

    public void Flush()
    {
        (global::Serilog.Log.Logger as IDisposable)?.Dispose();
    }
}
