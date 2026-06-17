using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Provided to a <see cref="RenderPass"/> record callback during execution. Wraps the native
/// <c>ke_render_pass_ctx*</c> and exposes only the read-only accessors a pass needs to
/// query its bound resources — never the renderer's internal state.
/// </summary>
/// <remarks>
/// Lifetime is the call to the record callback. Storing the context past that point produces
/// undefined behaviour; the native side reuses the same TLS-backed storage for the next pass.
/// </remarks>
public readonly unsafe ref struct RenderPassContext
{
    private readonly ke_render_pass_ctx* _native;

    internal RenderPassContext(ke_render_pass_ctx* native) { _native = native; }

    /// <summary>Texture handle bound at <paramref name="resourceName"/>; <see cref="TextureHandle.None"/> if the pass did not declare it.</summary>
    public TextureHandle GetTexture(string resourceName)
    {
        var bytes = stackalloc sbyte[256];
        int n = System.Text.Encoding.ASCII.GetBytes(resourceName, new Span<byte>(bytes, 255));
        bytes[n] = 0;
        var h = _native->get_texture(_native, bytes);
        return h.idx == uint.MaxValue ? TextureHandle.None : new TextureHandle(h.idx);
    }

    /// <summary>Current backbuffer dimensions in pixels. Useful for fullscreen passes uploading a size uniform.</summary>
    public (uint Width, uint Height) GetBackbufferSize()
    {
        uint w = 0, h = 0;
        _native->get_backbuffer_size(_native, &w, &h);
        return (w, h);
    }
}
