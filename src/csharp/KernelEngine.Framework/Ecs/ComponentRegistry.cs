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
        Register<TransformComponent>(ecs, "Transform");
        Register<MeshRendererComponent>(ecs, "MeshRenderer");
        Register<CameraComponent>(ecs, "Camera");
        Register<DirectionalLightComponent>(ecs, "DirectionalLight");
        Register<SkyboxComponent>(ecs, "Skybox");
        Register<PointLightComponent>(ecs, "PointLight");
        Register<AmbientLightComponent>(ecs, "AmbientLight");
        Register<SpotLightComponent>(ecs, "SpotLight");
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
