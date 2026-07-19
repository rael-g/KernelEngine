using KernelEngine.Ecs;
using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Holds the component IDs for every registered framework component, indexed
/// by managed type. Game/framework code looks up the cid for a component
/// struct type via <see cref="CidOf{T}"/> instead of growing per-component
/// properties on this class — that keeps the surface flat as new components
/// are added.
/// </summary>
public sealed class ComponentRegistry : IComponentRegistry
{
    private readonly Dictionary<Type, uint> _byType = new();

    internal ComponentRegistry(IEcsRegistry ecs)
    {
        // Names that have kernel constants ("transform", "camera", etc.) must
        // match exactly so that the native scene-loader apply callbacks and
        // managed contributors share one ECS slot per component type.
        Register<TransformComponent>(ecs, "transform");
        Register<CameraComponent>(ecs, CameraComponent.Name);
        Register<MeshComponent>(ecs, MeshComponent.Name);
        Register<DirectionalLightComponent>(ecs, DirectionalLightComponent.Name);
        Register<PointLightComponent>(ecs, PointLightComponent.Name);
        Register<SpotLightComponent>(ecs, SpotLightComponent.Name);
        Register<AmbientLightComponent>(ecs, AmbientLightComponent.Name);
        Register<SkyboxComponent>(ecs, SkyboxComponent.Name);
        // Framework-only component (no kernel counterpart) keeps its own name.
        // MeshRendererComponent is the legacy bgfx material-based path; the v2
        // forward pass reads the "mesh" slot above instead.
        Register<MeshRendererComponent>(ecs, "MeshRenderer");
    }

    /// <summary>Returns the cid registered for the given component struct type.</summary>
    public uint CidOf<T>() where T : unmanaged
    {
        if (!_byType.TryGetValue(typeof(T), out var cid))
            throw new InvalidOperationException(
                $"Component type '{typeof(T).Name}' is not registered with the framework.");
        return cid;
    }

    private void Register<T>(IEcsRegistry ecs, string name) where T : unmanaged
        => _byType[typeof(T)] = ecs.RegisterComponent<T>(name);
}
