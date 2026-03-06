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
    /// <summary>Cubemap handle that is currently active for the world. Reset by <see cref="Initialize"/>.</summary>
    internal static uint ActiveHandle { get; private set; } = uint.MaxValue;

    /// <summary>Resets the active skybox handle. Called by <see cref="Application"/> at world creation.</summary>
    internal static void Initialize() => ActiveHandle = uint.MaxValue;

    /// <summary>
    /// GPU cubemap handle to use as the skybox. Must be a handle returned by
    /// <see cref="Renderer.CreateCubemap"/> or <see cref="TextureLoader.LoadCubemapFiles"/>.
    /// </summary>
    public uint CubemapHandle { get; init; } = uint.MaxValue;

    protected override void OnStart()
    {
        if (CubemapHandle != uint.MaxValue)
            ActiveHandle = CubemapHandle;
    }
}
