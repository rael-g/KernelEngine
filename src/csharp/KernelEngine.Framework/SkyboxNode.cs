using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that designates a cubemap as the active skybox for this world.
/// Add exactly one <see cref="SkyboxNode"/> to the scene and set <see cref="CubemapHandle"/>
/// to a handle returned by <see cref="Renderer.CreateCubemap"/>.
/// The <see cref="SkyboxRenderSystem"/> renders it each frame and enables IBL
/// (image-based lighting) in the PBR shader.
/// </summary>
public class SkyboxNode : Node
{
    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(IEcsRegistry registry)
    {
        ComponentId = registry.RegisterComponent<SkyboxComponent>("Skybox");
    }

    /// <summary>
    /// GPU cubemap handle to use as the skybox. Must be a handle returned by
    /// <see cref="Renderer.CreateCubemap"/>.
    /// </summary>
    public TextureHandle CubemapHandle { get; init; } = TextureHandle.None;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue || !CubemapHandle.IsValid) return;
        var comp = AddComponent<SkyboxComponent>(ComponentId);
        comp[0].CubemapHandle = CubemapHandle;
    }
}
