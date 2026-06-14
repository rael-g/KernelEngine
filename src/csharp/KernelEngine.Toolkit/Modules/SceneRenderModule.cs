using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Wires the scene infrastructure: resolves the ECS adapter + component registry
/// registered by <c>FrameworkModule</c>, creates the <see cref="NodeWorld"/>,
/// registers all render contributors, and installs the BehaviorSystem that drives
/// per-node <see cref="Node.OnUpdate"/> callbacks each tick.
/// </summary>
/// <remarks>
/// Add <c>FrameworkModule</c> before this module; it registers the
/// <see cref="World"/>, <see cref="IEcsAdapter"/>, and <see cref="IComponentRegistry"/>
/// singletons that this module resolves from DI.
/// </remarks>
public sealed class SceneRenderModule : IRuntimeModule
{
    public string Name => "SceneRender";

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<NodeWorld>(sp =>
            new NodeWorld(
                sp.GetRequiredService<World>(),
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, CameraContributor>(sp =>
            new CameraContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>(),
                sp.GetRequiredService<IWindow>()));

        services.AddSingleton<IFrameContributor, AmbientLightContributor>(sp =>
            new AmbientLightContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, LightContributor>(sp =>
            new LightContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, PointLightContributor>(sp =>
            new PointLightContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, SpotLightContributor>(sp =>
            new SpotLightContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, MeshContributor>(sp =>
            new MeshContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, SkyboxContributor>(sp =>
            new SkyboxContributor(
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));

        services.AddSingleton<IFrameContributor, LabelContributor>(sp =>
            new LabelContributor(
                sp.GetRequiredService<NodeWorld>(),
                sp.GetRequiredService<IWindow>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _ = services.GetRequiredService<IComponentRegistry>();
        var nodeWorld = services.GetRequiredService<NodeWorld>();
        var input     = services.GetService<IInput>();

        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, dt) =>
        {
            input?.Update();
            var reader    = (input as Input)?.CaptureSnapshot();
            var view      = new View(nodeWorld, dt, reader);
            var behaviors = nodeWorld.Behaviors;
            for (int i = 0; i < behaviors.Count; i++)
                behaviors[i].OnUpdate(in view);
        }, pinnedThread: 1);
    }
}
