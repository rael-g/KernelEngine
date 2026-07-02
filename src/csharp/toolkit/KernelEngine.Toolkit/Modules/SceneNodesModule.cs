using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Ecs;
using KernelEngine.Input;
using KernelEngine.Render;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;
using KernelEngine.Window;

namespace KernelEngine.Framework;

/// <summary>
/// Scene infrastructure for the v2 (component-driven) render path. Registers the
/// <see cref="NodeWorld"/>, installs the BehaviorSystem that propagates transforms
/// and drives per-node <see cref="Node.OnUpdate"/>, and runs a one-shot scene
/// setup callback on the render worker. Unlike <c>SceneRenderModule</c> it
/// registers no IRenderer contributors — the render module's forward pass reads
/// the ECS components directly.
/// </summary>
/// <remarks>
/// Add <c>FrameworkModule</c> and the render module before this one: the render
/// module's OnLoad must create the render core (so mesh upload works) before the
/// setup callback runs. Topo-sort preserves registration order for independent
/// modules, so register the render module earlier in the list.
/// </remarks>
public sealed class SceneNodesModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly Action<NodeWorld, IServiceProvider> _setup;

    public string Name => "SceneNodes";

    public IEnumerable<Type> Dependencies => new[] { typeof(FrameworkModule) };

    /// <summary>Setup callback that only needs the node world.</summary>
    public SceneNodesModule(Action<NodeWorld> setup) => _setup = (nw, _) => setup(nw);

    /// <summary>Setup callback that also wants to resolve DI services.</summary>
    public SceneNodesModule(Action<NodeWorld, IServiceProvider> setup) => _setup = setup;

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<NodeWorld>(sp =>
            new NodeWorld(
                sp.GetRequiredService<World>(),
                sp.GetRequiredService<IEcsRegistry>(),
                sp.GetRequiredService<IComponentRegistry>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var nodeWorld = services.GetRequiredService<NodeWorld>();
        var world     = services.GetRequiredService<World>();
        var sceneTree = world.SceneTree;
        var input     = services.GetService<IInput>();
        var scheduler = services.GetRequiredService<IScheduler>();

        // [entity.components.AmbientLight] — backend-agnostic data mapping, no GPU
        // resources touched, so it's safe to register unconditionally (mirrors the
        // identical callback SceneRenderModule registers for the legacy bgfx path).
        var components = services.GetRequiredService<IComponentRegistry>();
        world.RegisterComponentApply<AmbientLightComponent>(
            components.CidOf<AmbientLightComponent>(),
            static (ref AmbientLightComponent comp, in VariantReader reader) =>
            {
                if (reader.TryGetVec3("Color", out var c)) comp.Color = c;
            });

        IInputReader? prevSnapshot = null;
        // The ctx-aware overload hands each tick its system context. Node create/
        // destroy issued from a behavior routes through it and defers the structural
        // change to the wave barrier — so this runs as an ordinary parallel-wave
        // system with no exclusive bypass.
        runtime.RegisterSystem("Scene.Behaviors", RuntimePhase.Update, (_, ctx, dt) =>
        {
            input?.Update();
            sceneTree.PropagateTransforms();
            var snapshot  = input?.CaptureSnapshot();
            var view      = new View(nodeWorld, dt, snapshot, prevSnapshot, ctx);
            var behaviors = nodeWorld.Behaviors;
            using (nodeWorld.EnterSystem(ctx))
            {
                for (int i = 0; i < behaviors.Count; i++)
                    behaviors[i].OnUpdate(in view);
            }
            prevSnapshot = snapshot;
        }, pinnedThread: 1);

        // Optional: only registered when the active render module implements
        // IRenderResources (render-v2). The legacy bgfx path renders labels through
        // its own IFrameContributor bridge and applies [entity.components.MeshRenderer]
        // through SceneRenderModule instead.
        var resources = services.GetService<IRenderResources>();
        var window    = services.GetService<IWindow>();
        if (resources != null && window != null)
        {
            LabelUiSystem.Register(runtime, nodeWorld, resources, window);

            // [entity.components.MeshRenderer] — render-v2 analog of SceneRenderModule's
            // MeshRendererComponent apply: resolves a named primitive mesh + a flat-color
            // material through IRenderResources instead of the legacy IRenderer. Named
            // primitives are uploaded once and cached (scene files reuse the same few
            // shapes across many entities — e.g. every Pong sprite is "quad").
            var primitiveCache = new Dictionary<string, MeshHandle>(StringComparer.OrdinalIgnoreCase);
            world.RegisterComponentApply<MeshComponent>(
                components.CidOf<MeshComponent>(),
                (ref MeshComponent comp, in VariantReader reader) =>
                {
                    if (reader.TryGetString("mesh", out var meshName) && meshName is not null)
                    {
                        if (!primitiveCache.TryGetValue(meshName, out var handle))
                        {
                            handle = meshName switch
                            {
                                "quad"   => KernelEngine.Render.MeshPrimitives.Quad(resources),
                                "plane"  => KernelEngine.Render.MeshPrimitives.Plane(resources),
                                "cube"   => KernelEngine.Render.MeshPrimitives.Cube(resources),
                                "sphere" => KernelEngine.Render.MeshPrimitives.UvSphere(resources),
                                _ => throw new InvalidOperationException(
                                    $"[entity.components.MeshRenderer] unknown primitive '{meshName}'"),
                            };
                            primitiveCache[meshName] = handle;
                        }
                        comp.Mesh = handle;
                    }

                    if (reader.TryGetVec4("color", out var color))
                    {
                        float roughness = 1f;
                        reader.TryGetFloat("roughness", out roughness);
                        comp.Material = resources.CreateMaterial(color, roughness: roughness);
                    }
                });
        }

        // Scene setup runs on the render worker (GPU upload has thread affinity),
        // after the render module's OnLoad created the core + registered components.
        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { _setup(nodeWorld, services); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err != null) throw new InvalidOperationException("Scene setup failed", err);
    }
}
