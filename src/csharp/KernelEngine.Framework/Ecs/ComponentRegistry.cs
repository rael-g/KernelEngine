namespace KernelEngine.Framework;

/// <summary>
/// Holds the component IDs for the built-in framework components, registered
/// once during the runtime startup. Render systems pull cids from here.
/// </summary>
public sealed class ComponentRegistry
{
    public uint TransformCid        { get; }
    public uint MeshRendererCid     { get; }
    public uint CameraCid           { get; }
    public uint DirectionalLightCid { get; }
    public uint SkyboxCid           { get; }

    internal ComponentRegistry(EcsAdapter ecs)
    {
        TransformCid        = ecs.Register<TransformComponent>("Transform");
        MeshRendererCid     = ecs.Register<MeshRendererComponent>("MeshRenderer");
        CameraCid           = ecs.Register<CameraComponent>("Camera");
        DirectionalLightCid = ecs.Register<DirectionalLightComponent>("DirectionalLight");
        SkyboxCid           = ecs.Register<SkyboxComponent>("Skybox");
    }
}
