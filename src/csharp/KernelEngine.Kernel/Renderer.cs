using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Hardware-accelerated renderer. Takes ownership of a <c>ke_render*</c> created by a plugin factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// </summary>
public sealed unsafe class Renderer : IDisposable
{
    private ke_render* _native;

    public ke_render* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>
    /// Wraps an already-created <c>ke_render*</c> and calls <c>on_initialize</c>.
    /// </summary>
    public Renderer(ke_render* native)
    {
        _native = native;
        KernelException.ThrowIfFailed(_native->on_initialize(_native));
    }

    /// <summary>Sets the background clear color for the next frame.</summary>
    public void ClearColor(float r, float g, float b, float a) =>
        KernelException.ThrowIfFailed(_native->clear_color(_native, r, g, b, a));

    /// <summary>Sets the background clear color for the next frame.</summary>
    public void ClearColor(Vector4 color) =>
        ClearColor(color.X, color.Y, color.Z, color.W);

    /// <summary>Toggles orthographic projection mode.</summary>
    public void SetOrthographic(bool enabled) =>
        KernelException.ThrowIfFailed(_native->set_orthographic(_native, enabled));

    /// <summary>Submits a draw call with the given world-space transform.</summary>
    public void Submit(Matrix4x4 transform)
    {
        // Matrix4x4 and ke_mat4 share the same float[16] row-major memory layout.
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        KernelException.ThrowIfFailed(_native->submit(_native, &mat));
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->on_shutdown(_native);
            _native->destroy(_native);
            _native = null;
        }
    }
}
