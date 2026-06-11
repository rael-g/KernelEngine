using KernelEngine.Ecs.Flecs;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Wires the framework's scene infrastructure: ECS adapter, component
/// registry, render contributors, and the <see cref="Tree"/> facade. Add this
/// before any <see cref="SceneModule"/>; without it, components aren't
/// registered and the Tree isn't available for spawning nodes.
/// </summary>
public sealed class SceneRenderModule : IRuntimeModule
{
    public string Name => "SceneRender";

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<EcsAdapter>(sp =>
            new EcsAdapter((FlecsEcs)sp.GetRequiredService<IEcs>()));

        services.AddSingleton<ComponentRegistry>(sp =>
            new ComponentRegistry(sp.GetRequiredService<EcsAdapter>()));

        services.AddSingleton<Tree>(sp =>
            new Tree(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>(),
                sp.GetRequiredService<IRenderer>()));

        services.AddSingleton<IFrameContributor, CameraContributor>(sp =>
            new CameraContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>(),
                sp.GetRequiredService<IWindow>()));

        services.AddSingleton<IFrameContributor, LightContributor>(sp =>
            new LightContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));

        services.AddSingleton<IFrameContributor, MeshContributor>(sp =>
            new MeshContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        // Force resolution so components are registered up front, before
        // SceneModule callbacks try to spawn nodes.
        _ = services.GetRequiredService<ComponentRegistry>();
        _ = services.GetRequiredService<Tree>();
    }
}
