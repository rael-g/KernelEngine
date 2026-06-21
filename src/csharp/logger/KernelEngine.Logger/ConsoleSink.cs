namespace KernelEngine.Logger;

/// <summary>
/// Writes log events to <see cref="Console.Error"/> using the same
/// <c>[LEVEL] tag: message</c> format as the native <c>ke_console_sink</c>.
/// Level filtering is handled by the logger before this sink is called.
/// </summary>
public sealed class ConsoleSink : ILoggerSink
{
    private static readonly string[] s_levels = ["TRACE", "DEBUG", "INFO", "WARN", "ERROR", "CRIT"];

    /// <inheritdoc/>
    public LogLevel MinLevel { get; init; } = LogLevel.Trace;

    /// <inheritdoc/>
    public void Log(LogLevel level, string tag, string message)
    {
        int idx = (int)level;
        string label = (idx >= 0 && idx < s_levels.Length) ? s_levels[idx] : "?";
        Console.Error.WriteLine($"[{label}] {tag}: {message}");
        Console.Error.Flush();
    }

    public void Flush() => Console.Error.Flush();
}
