namespace KernelEngine.Window.Glfw;

/// <summary>
/// Project-level settings for the GLFW window plugin. Hydrated from the
/// <c>[runtime.window]</c> section of <c>Project.toml</c> when configured,
/// otherwise these compile-time defaults apply (chapter 16 §2.4).
/// </summary>
public sealed class WindowOptions
{
    public int    Width      { get; set; } = 1280;
    public int    Height     { get; set; } = 720;
    public string Title      { get; set; } = "KernelEngine";
    public bool   Fullscreen { get; set; } = false;
}
