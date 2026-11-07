using KernelEngine.Logger;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Input;

public static class InputServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="Input"/> singleton. The library logs to the registered
    /// <see cref="Microsoft.Extensions.Logging.ILoggerFactory"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddInput(this IServiceCollection services)
    {
        services.AddSingleton(sp =>
        {
            if (sp.GetService<Microsoft.Extensions.Logging.ILoggerFactory>() is { } loggerFactory)
                unsafe
                {
                    Native.NativeMethods.input_default_set_log_callback(KernelEngine.Logger.NativeLogging.Callback, KernelEngine.Logger.NativeLogging.ContextOf(loggerFactory));
                }
            return new Input();
        });
        services.AddSingleton<IInput>(sp => sp.GetRequiredService<Input>());
        services.AddSingleton<INativeInput>(sp => sp.GetRequiredService<Input>());
        return services;
    }
}
