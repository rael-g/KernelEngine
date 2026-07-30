using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Logger;

/// <summary>
/// The parts of <see cref="Logger"/> that express the native surface in C# terms
/// rather than mirroring it: string marshaling for <see cref="Log"/>, the
/// severity-named convenience overloads, and the adapter from the game-facing
/// <see cref="ILoggerSink"/> to the generated, native-shaped
/// <see cref="ILoggerSinkNative"/>. Everything that is a direct image of the C
/// ABI is generated in <c>Generated/Logger.g.cs</c>.
/// </summary>
public sealed unsafe partial class Logger : ILogger
{
    /// <summary>Dispatches a log event to all registered sinks.</summary>
    public void Log(LogLevel level, string tag, string message)
    {
        var tagBytes = System.Text.Encoding.ASCII.GetBytes(tag + '\0');
        var msgBytes = System.Text.Encoding.ASCII.GetBytes(message + '\0');
        fixed (byte* tagPtr = tagBytes, msgPtr = msgBytes)
        {
            var evt = new ke_log_event
            {
                level = (int)level,
                tag = (sbyte*)tagPtr,
                message = (sbyte*)msgPtr,
            };
            Log(&evt);
        }
    }

    public void Trace(string tag, string message)    => Log(LogLevel.Trace, tag, message);
    public void Debug(string tag, string message)    => Log(LogLevel.Debug, tag, message);
    public void Info(string tag, string message)     => Log(LogLevel.Info, tag, message);
    public void Warning(string tag, string message)  => Log(LogLevel.Warning, tag, message);
    public void Error(string tag, string message)    => Log(LogLevel.Error, tag, message);
    public void Critical(string tag, string message) => Log(LogLevel.Critical, tag, message);

    /// <summary>Registers a managed sink to receive all subsequent log events.</summary>
    /// <param name="sink">The sink implementation.</param>
    /// <param name="minLevel">Minimum level forwarded to this sink. Defaults to <see cref="LogLevel.Trace"/>.</param>
    public void AddSink(ILoggerSink sink, LogLevel minLevel = LogLevel.Trace) =>
        AddSink(new NativeSinkAdapter(sink), (int)minLevel);

    /// <summary>Adapts a game-facing <see cref="ILoggerSink"/> to the generated, native-event-shaped interface.</summary>
    private sealed class NativeSinkAdapter(ILoggerSink sink) : ILoggerSinkNative
    {
        public void Log(in ke_log_event @event)
        {
            var tag = Marshal.PtrToStringAnsi((nint)@event.tag) ?? string.Empty;
            var message = Marshal.PtrToStringAnsi((nint)@event.message) ?? string.Empty;
            sink.Log((LogLevel)@event.level, tag, message);
        }

        public void Flush() => sink.Flush();
    }
}
