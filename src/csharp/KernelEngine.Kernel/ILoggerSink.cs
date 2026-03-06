using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Receives structured log events dispatched by a <see cref="Logger"/>.
/// </summary>
public interface ILoggerSink
{
    /// <summary>
    /// Minimum level this sink wants to receive.
    /// The logger filters events below this level before calling <see cref="Log"/>.
    /// </summary>
    ke_log_level MinLevel => ke_log_level.KE_LOG_LEVEL_TRACE;

    void Log(ke_log_level level, string tag, string message);
}
