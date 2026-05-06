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
    public ke_log_level MinLevel { get; init; } = ke_log_level.KE_LOG_LEVEL_TRACE;

    /// <param name="logger">
    /// The Serilog logger to write to. Defaults to <see cref="global::Serilog.Log.Logger"/>.
    /// </param>
    public SerilogSink(ILogger? logger = null)
    {
        _logger = logger ?? global::Serilog.Log.Logger;
    }

    /// <inheritdoc/>
    public void Log(ke_log_level level, string tag, string message)
    {
        var serilogLevel = level switch
        {
            ke_log_level.KE_LOG_LEVEL_TRACE    => LogEventLevel.Verbose,
            ke_log_level.KE_LOG_LEVEL_DEBUG    => LogEventLevel.Debug,
            ke_log_level.KE_LOG_LEVEL_INFO     => LogEventLevel.Information,
            ke_log_level.KE_LOG_LEVEL_WARNING  => LogEventLevel.Warning,
            ke_log_level.KE_LOG_LEVEL_ERROR    => LogEventLevel.Error,
            ke_log_level.KE_LOG_LEVEL_CRITICAL => LogEventLevel.Fatal,
            _                                  => LogEventLevel.Information,
        };

        _logger.ForContext("Tag", tag).Write(serilogLevel, "[{Tag}] {Message}", tag, message);
    }

    public void Flush()
    {
        (global::Serilog.Log.Logger as IDisposable)?.Dispose();
    }
}
