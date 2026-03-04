using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Core;

public static class CoreServiceExtensions
{
    public static IServiceCollection AddKernelEngineCore(this IServiceCollection services)
    {
        services.AddSingleton<IAllocator>(sp => NativeAllocator.CreateMalloc());
        
        services.AddSingleton<NativeLogger>(sp => 
        {
            var alloc = sp.GetRequiredService<IAllocator>();
            return NativeLogger.Create(alloc);
        });

        services.AddSingleton<NativeMessagePipe>(sp => 
        {
            var alloc = sp.GetRequiredService<IAllocator>();
            var logger = sp.GetService<NativeLogger>();
            return NativeMessagePipe.Create(alloc, logger);
        });

        services.AddSingleton<Engine>(sp => 
        {
            var alloc = sp.GetRequiredService<IAllocator>();
            var logger = sp.GetService<NativeLogger>();
            var pipe = sp.GetService<NativeMessagePipe>();
            return Engine.Create(alloc, logger, pipe);
        });

        return services;
    }
}
