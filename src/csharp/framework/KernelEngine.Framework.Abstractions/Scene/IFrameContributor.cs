using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Reads ECS component data each frame and writes the results into an
/// <see cref="IFramePacket"/> for the renderer. One contributor per render
/// concern (camera, lights, meshes, skybox, …).
/// </summary>
public interface IFrameContributor
{
    /// <summary>Called once per frame during the Extract phase.</summary>
    void Contribute(IFramePacket packet);
}
