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

        // Ambient runs FIRST so a directional light's Ambient field can
        // overwrite the scene-wide ambient when both exist.
        services.AddSingleton<IFrameContributor, AmbientLightContributor>(sp =>
            new AmbientLightContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));

        services.AddSingleton<IFrameContributor, LightContributor>(sp =>
            new LightContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));

        services.AddSingleton<IFrameContributor, PointLightContributor>(sp =>
            new PointLightContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));

        services.AddSingleton<IFrameContributor, MeshContributor>(sp =>
            new MeshContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));

        services.AddSingleton<IFrameContributor, SkyboxContributor>(sp =>
            new SkyboxContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        // Force resolution so components are registered up front, before
        // SceneModule callbacks try to spawn nodes.
        _ = services.GetRequiredService<ComponentRegistry>();
        var tree  = services.GetRequiredService<Tree>();
        var input = services.GetService<IInput>(); // optional — only if .AddInput() was called

        // BehaviorSystem — calls Node.OnUpdate for every bound node that
        // overrode it. Runs in Update phase (before Extract, so behaviors
        // mutate transforms/component state that contributors then read).
        // Pinned to the render worker for now because Tree mutations route
        // through EcsAdapter and the storage layer isn't yet free-threaded;
        // ticking Input here too keeps Update + reads on a single worker.
        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, dt) =>
        {
            input?.Update();
            var reader    = (input as Input)?.CaptureSnapshot();
            var view      = new View(tree, dt, reader);
            var behaviors = tree.Behaviors;
            // Index loop avoids enumerator allocation on the hot path.
            for (int i = 0; i < behaviors.Count; i++)
                behaviors[i].OnUpdate(in view);
        }, pinnedThread: 1);
    }
}
