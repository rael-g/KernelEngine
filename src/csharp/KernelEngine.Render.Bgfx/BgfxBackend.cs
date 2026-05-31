namespace KernelEngine.Render.Bgfx;

/// <summary>
/// Graphics backend passed to the bgfx renderer. Values map 1-to-1 to
/// <c>bgfx::RendererType::Enum</c>; <see cref="Auto"/> is a sentinel that lets
/// the C++ factory pick the platform default (currently Vulkan on Windows/Linux).
/// </summary>
public enum BgfxBackend : uint
{
    /// <summary>Factory-chosen default (currently Vulkan on Windows/Linux).</summary>
    Auto = uint.MaxValue,

    /// <summary>No-op renderer. Headless; useful for unit tests without a GPU.</summary>
    Noop = 0,

    /// <summary>Direct3D 11.</summary>
    Direct3D11 = 2,

    /// <summary>Direct3D 12.</summary>
    Direct3D12 = 3,

    /// <summary>Metal (macOS / iOS).</summary>
    Metal = 5,

    /// <summary>OpenGL ES 2.0+.</summary>
    OpenGLES = 7,

    /// <summary>OpenGL 2.1+.</summary>
    OpenGL = 8,

    /// <summary>Vulkan.</summary>
    Vulkan = 9,
}
