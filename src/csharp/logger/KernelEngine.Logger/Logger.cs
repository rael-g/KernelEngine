namespace KernelEngine.Logger;

/// <summary>
/// The logger: hands each event to every registered sink whose <see cref="ILoggerSink.MinLevel"/>
/// it reaches. Callable from any thread, since native libraries log from whichever thread runs them.
/// </summary>
public sealed class Logger : ILogger
{
    private readonly List<ILoggerSink> _sinks = [];
    private readonly Lock _lock = new();

    /// <inheritdoc/>
    public void AddSink(ILoggerSink sink)
    {
        lock (_lock) _sinks.Add(sink);
    }

    /// <inheritdoc/>
    public void Log(LogLevel level, string tag, string message)
    {
        lock (_lock)
        {
            foreach (var sink in _sinks)
                if (level >= sink.MinLevel) sink.Log(level, tag, message);
        }
    }

    /// <inheritdoc/>
    public void Trace(string tag, string message) => Log(LogLevel.Trace, tag, message);

    /// <inheritdoc/>
    public void Debug(string tag, string message) => Log(LogLevel.Debug, tag, message);

    /// <inheritdoc/>
    public void Info(string tag, string message) => Log(LogLevel.Info, tag, message);

    /// <inheritdoc/>
    public void Warning(string tag, string message) => Log(LogLevel.Warning, tag, message);

    /// <inheritdoc/>
    public void Error(string tag, string message) => Log(LogLevel.Error, tag, message);

    /// <inheritdoc/>
    public void Critical(string tag, string message) => Log(LogLevel.Critical, tag, message);

    /// <inheritdoc/>
    public void Flush()
    {
        lock (_lock)
        {
            foreach (var sink in _sinks) sink.Flush();
        }
    }
}
