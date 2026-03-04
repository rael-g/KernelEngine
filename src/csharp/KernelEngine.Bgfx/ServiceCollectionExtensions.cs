using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Core;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Bgfx;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddRenderBgfx(this IServiceCollection services, string shaderPath)
    {
        services.AddSingleton<IRenderer>(sp => 
        {
            var allocator = sp.GetRequiredService<IAllocator>();
            var window = sp.GetRequiredService<IWindow>();
            var logger = sp.GetService<NativeLogger>();
            var pipe = sp.GetService<NativeMessagePipe>();
            return new BgfxRenderSystem(allocator, window, shaderPath, logger, pipe);
        });
        
        return services;
    }
}
