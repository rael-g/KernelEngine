using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Cooperative writer of per-frame render state. Modules implement this to
/// stuff data (camera, lights, draw commands, etc.) into the shared
/// <see cref="IFramePacket"/> that the renderer consumes once per tick.
/// </summary>
/// <remarks>
/// TECH DEBT: the contribution model exists because the native renderer
/// (<c>core_renderer.cpp</c>) is still organized around <c>SubmitPacket</c> —
/// <c>submit_mesh</c> / <c>submit_skybox</c> / <c>set_directional_light</c> /
/// etc. are stubs. The doctrinal target (Option D + unified scheduler) wants
/// per-call setters on the renderer with internal state accumulation; that's a
/// dedicated R7+ render rewrite. Until then, framework modules write packets
/// via this interface and never expose <see cref="IFramePacket"/> to game code.
/// </remarks>
public interface IFrameContributor
{
    /// <summary>Writes the contributor's per-frame data into the packet.</summary>
    void Contribute(IFramePacket packet);
}
