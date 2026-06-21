
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Render;
using KernelEngine.Input;
using KernelEngine.Runtime;
using KernelEngine.Window;

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

        services.AddSingleton<PrimitiveCache>();
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var components = services.GetRequiredService<IComponentRegistry>();
        var world      = services.GetRequiredService<World>();

        // Register C# apply callbacks so [entity.components.*] blocks in scene files
        // can populate framework-only components (parallel to ke_framework_apply_camera).
        world.RegisterComponentApply<AmbientLightComponent>(
            components.CidOf<AmbientLightComponent>(),
            static (ref AmbientLightComponent comp, in VariantReader reader) =>
            {
                if (reader.TryGetVec3("Color", out var c)) comp.Color = c;
            });

        var primitives = services.GetRequiredService<PrimitiveCache>();
        var renderer   = services.GetRequiredService<IRenderer>();
        var meshCid    = components.CidOf<MeshRendererComponent>();

        // [entity.components.MeshRenderer] — inline 2D visual via primitive name + color.
        // Scene files set: mesh = "quad", color = [r,g,b,a], roughness = f.
        // Runs on the render worker (scene load is pinned there) so GPU creation is safe.
        world.RegisterComponentApply<MeshRendererComponent>(
            meshCid,
            (ref MeshRendererComponent comp, in VariantReader reader) =>
            {
                if (reader.TryGetString("mesh", out var meshName) && meshName is not null)
                    comp.Mesh = primitives.Get(meshName);

                if (reader.TryGetVec4("color", out var color))
                {
                    float roughness = 1f;
                    reader.TryGetFloat("roughness", out roughness);
                    comp.Material = renderer.CreateMaterial(color, roughness: roughness);
                }
            });

        var nodeWorld  = services.GetRequiredService<NodeWorld>();
        var sceneTree  = services.GetRequiredService<World>().SceneTree;
        var input      = services.GetService<IInput>();

        IInputReader? prevSnapshot = null;
        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, dt) =>
        {
            input?.Update();
            sceneTree.PropagateTransforms();
            var snapshot  = input?.CaptureSnapshot();
            var view      = new View(nodeWorld, dt, snapshot, prevSnapshot);
            var behaviors = nodeWorld.Behaviors;
            for (int i = 0; i < behaviors.Count; i++)
                behaviors[i].OnUpdate(in view);
            prevSnapshot = snapshot;
        }, pinnedThread: 1);
    }
}
