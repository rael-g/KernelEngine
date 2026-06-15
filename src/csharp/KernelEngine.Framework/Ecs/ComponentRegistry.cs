using KernelEngine.Kernel;

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
        Register<CameraComponent>(ecs, "camera");
        Register<DirectionalLightComponent>(ecs, "directional_light");
        Register<PointLightComponent>(ecs, "point_light");
        Register<SpotLightComponent>(ecs, "spot_light");
        // Framework-only components (no kernel counterpart) keep their own names.
        Register<MeshRendererComponent>(ecs, "MeshRenderer");
        Register<SkyboxComponent>(ecs, "Skybox");
        Register<AmbientLightComponent>(ecs, "AmbientLight");
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
