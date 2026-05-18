namespace KernelEngine.Kernel;

/// <summary>Managed logger interface. Implementations dispatch to one or more <see cref="ILoggerSink"/>s.</summary>
public interface ILogger
{
    void AddSink(ILoggerSink sink, LogLevel minLevel = LogLevel.Trace);
    void Log(LogLevel level, string tag, string message);
    void Trace(string tag, string message);
    void Debug(string tag, string message);
    void Info(string tag, string message);
    void Warning(string tag, string message);
    void Error(string tag, string message);
    void Critical(string tag, string message);
    void Flush();
}

/// <summary>Receives structured log events dispatched by an <see cref="ILogger"/>.</summary>
public interface ILoggerSink
{
    /// <summary>Minimum level this sink processes. Events below this level are filtered out by the logger.</summary>
    LogLevel MinLevel { get; }

    void Log(LogLevel level, string tag, string message);
}
