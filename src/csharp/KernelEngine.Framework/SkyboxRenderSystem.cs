using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Submits the skybox draw call each frame when a <see cref="SkyboxNode"/> is active.
/// Must be registered <em>after</em> <see cref="CameraRenderSystem"/> (which sets the view
/// transform) and <em>before</em> <see cref="MeshRenderSystem"/> (which needs IBL state).
/// </summary>
public sealed class SkyboxRenderSystem : ISystem
{
    private readonly Renderer _renderer;

    /// <param name="renderer">The renderer to submit the skybox draw call to.</param>
    public SkyboxRenderSystem(Renderer renderer) => _renderer = renderer;

    /// <inheritdoc/>
    public void Update(World world, float dt, FramePacket? packet = null)
    {
        if (SkyboxNode.ActiveHandle != uint.MaxValue)
        {
            packet?.SetSkybox(SkyboxNode.ActiveHandle);
        }
    }
}
