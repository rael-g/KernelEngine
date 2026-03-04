using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Core;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Glfw;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddWindowGlfw(this IServiceCollection services, int width, int height, string title)
    {
        services.AddSingleton<IWindow>(sp => 
        {
            var allocator = sp.GetRequiredService<IAllocator>();
            var logger = sp.GetService<NativeLogger>();
            var pipe = sp.GetService<NativeMessagePipe>();
            return new GlfwWindowSystem(allocator, width, height, title, logger, pipe);
        });
        
        return services;
    }
}
