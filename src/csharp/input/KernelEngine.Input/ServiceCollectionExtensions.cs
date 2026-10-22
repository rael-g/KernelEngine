using KernelEngine.Logger;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Input;

public static class InputServiceCollectionExtensions
{
    /// <summary>
    /// Registers an <see cref="Input"/> singleton. The library logs to the registered
    /// <see cref="ILogger"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddInput(this IServiceCollection services)
    {
        services.AddSingleton(sp =>
        {
            if (sp.GetService<ILogger>() is { } logger)
                unsafe
                {
                    Native.NativeMethods.input_default_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));
                }
            return new Input();
        });
        services.AddSingleton<IInput>(sp => sp.GetRequiredService<Input>());
        services.AddSingleton<INativeInput>(sp => sp.GetRequiredService<Input>());
        return services;
    }
}
