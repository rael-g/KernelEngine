using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Kernel;

public static class InputServiceCollectionExtensions
{
    /// <summary>Registers an <see cref="Input"/> singleton.</summary>
    public static IServiceCollection AddInput(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Input(sp.GetService<INativeLogger>()));
        services.AddSingleton<IInput>(sp => sp.GetRequiredService<Input>());
        services.AddSingleton<INativeInput>(sp => sp.GetRequiredService<Input>());
        return services;
    }
}
