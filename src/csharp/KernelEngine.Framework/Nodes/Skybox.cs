using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A Tree node that designates a cubemap as the active skybox for this world.
/// Add exactly one <see cref="Skybox"/> to the Tree and set <see cref="CubemapHandle"/>
/// to a handle returned by <see cref="Renderer.CreateCubemap"/>.
/// The <see cref="SkyboxRenderSystem"/> renders it each frame and enables IBL
/// (image-based lighting) in the PBR shader.
/// </summary>
public class Skybox : Node
{
    /// <summary>
    /// GPU cubemap handle to use as the skybox. Must be a handle returned by
    /// <see cref="Renderer.CreateCubemap"/>.
    /// </summary>
    public TextureHandle CubemapHandle { get; init; } = TextureHandle.None;

    protected override void Start()
    {
        if (World == null || !CubemapHandle.IsValid) return;
        var cid = World.GetOrRegisterComponentId<SkyboxComponent>("Skybox");
        var comp = AddComponent<SkyboxComponent>(cid);
        comp[0].CubemapHandle = CubemapHandle;
    }
}
