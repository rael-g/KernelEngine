using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;
using ILogger = Serilog.ILogger;

namespace KernelEngine.Logging.Serilog;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a <see cref="SerilogSink"/> that routes kernel log events to Serilog.
    /// </summary>
    /// <param name="logger">
    /// Optional specific Serilog logger. Defaults to <see cref="global::Serilog.Log.Logger"/>.
    /// </param>
    public static IServiceCollection AddSerilogSink(
        this IServiceCollection services,
        ILogger? logger = null,
        LogLevel minLevel = LogLevel.Trace) =>
        services.AddSingleton<ILoggerSink>(_ => new SerilogSink(logger) { MinLevel = minLevel });
}
