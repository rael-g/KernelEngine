using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Core.Logging;
using Serilog;

namespace KernelEngine.Logging.Serilog;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddSerilog(this IServiceCollection services, LoggerConfiguration configuration)
    {
        var logger = configuration.CreateLogger();
        services.AddSingleton<ILogger>(logger);
        services.AddSingleton<ILoggerSink, SerilogSink>();
        
        return services;
    }
}
