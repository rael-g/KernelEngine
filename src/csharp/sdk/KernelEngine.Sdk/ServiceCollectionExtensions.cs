using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace KernelEngine;

/// <summary>Registration of an engine in a container.</summary>
public static class ServiceCollectionExtensions
{
    /// <summary>Registers the engine of <see cref="DefaultEngine"/> and its node types as C# registers them.</summary>
    public static IServiceCollection AddKernelEngine(this IServiceCollection services)
    {
        services.AddSingleton(sp => new Engine(sp));
        services.AddSingleton(sp => sp.GetRequiredService<Engine>().Nodes);
        return services;
    }

    /// <summary>
    /// Registers a <see cref="KernelEngineHost"/>, as itself and as <see cref="IHost"/>, that opens its assembly
    /// with <paramref name="open"/> and writes <paramref name="compose"/> into it, in order, when it starts; the
    /// instance <c>node_types</c> keyed by its name; and the node types as C# registers them. Nothing is created
    /// before the host starts, and asking for an instance before then fails.
    /// </summary>
    /// <param name="services">The container.</param>
    /// <param name="open">Makes the assembly, with whatever it reads its sections from.</param>
    /// <param name="compose">Each adds parts and composition to the assembly.</param>
    public static IServiceCollection AddKernelEngine(this IServiceCollection services, Func<IServiceProvider, KernelEngine.Assembly.Assembly> open, params Action<KernelEngine.Assembly.Assembly>[] compose)
    {
        services.AddSingleton(sp => new KernelEngineHost(sp, open, compose));
        services.AddSingleton<IHost>(sp => sp.GetRequiredService<KernelEngineHost>());
        services.AddKernelEngineInstance("node_types", "ke_node_types", native => (INodeTypes)NodeTypesOf(native));
        services.AddSingleton(sp => new NodeWorld(sp.GetRequiredKeyedService<INodeTypes>("node_types"), sp.GetService<ILoggerFactory>()));
        return services;
    }

    /// <summary>
    /// Registers the instance <paramref name="name"/>, as the vtable of <paramref name="contract"/> wrapped by
    /// <paramref name="wrap"/>, keyed by its name; asking for it before the host started fails.
    /// </summary>
    public static IServiceCollection AddKernelEngineInstance<T>(this IServiceCollection services, string name, string contract, Func<nint, T> wrap) where T : class =>
        services.AddKeyedSingleton(name, (sp, _) => wrap(sp.GetRequiredService<KernelEngineHost>().Instance(name, contract)));

    /// <summary>
    /// Registers <see cref="IOptions{T}"/> read from the section <paramref name="section"/> of
    /// <paramref name="configuration"/>: each public settable property of <typeparamref name="T"/> that is a number,
    /// a boolean or a string takes the key of its name in snake case, and keeps its initial value when the section
    /// has no such key.
    /// </summary>
    public static IServiceCollection AddKernelEngineOptions<T>(this IServiceCollection services, Func<IServiceProvider, Configuration.Configuration> configuration, string section) where T : class, new() =>
        services.AddSingleton<IOptions<T>>(sp => Options.Create(SettingsOptions.Read<T>(configuration(sp), section)));

    static unsafe NodeTypes NodeTypesOf(nint native) => NodeTypes.Borrow((ke_node_types*)native);
}
