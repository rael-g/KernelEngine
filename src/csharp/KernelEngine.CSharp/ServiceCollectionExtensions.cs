using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.CSharp;

/// <summary>
/// DI extension for the C# language plugin. Registers kernel contract implementations that
/// are written in C# but do not reference <c>KernelEngine.Framework</c> — following the same
/// isolation pattern as <c>KernelEngine.Render.Bgfx</c> or <c>KernelEngine.Window.Glfw</c>.
/// </summary>
public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers the C# implementations of kernel contracts:
    /// <list type="bullet">
    ///   <item><see cref="INodeTypeRegistry"/> — node type lookup used by the scene loader.</item>
    ///   <item><see cref="ISceneLoader"/> — TOML scene loader using the node type registry.</item>
    /// </list>
    /// Call this after <c>AddKernel()</c> and before <c>Application.Run()</c>.
    /// </summary>
    public static IServiceCollection AddCSharpPlugin(this IServiceCollection services)
    {
        services.AddSingleton<INodeTypeRegistry>(sp =>
        {
            var alloc = sp.GetRequiredService<IAllocator>();
            // Allocator is the concrete type in KernelEngine.Kernel; the plugin references Kernel.
            return new NodeTypeRegistry((Allocator)alloc);
        });

        services.AddSingleton<ISceneLoader>(sp =>
        {
            var world    = sp.GetRequiredService<IWorld>();
            var registry = sp.GetRequiredService<INodeTypeRegistry>();
            var tree     = sp.GetRequiredService<ISceneTree>();
            return new CSharpSceneLoader(world, registry, tree);
        });

        return services;
    }
}
