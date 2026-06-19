namespace KernelEngine.Kernel;

/// <summary>Modifier keys held during an input event. Matches GLFW modifier bits.</summary>
[System.Flags]
public enum KeyModifiers
{
    None = 0,
    Shift = 1,
    Control = 2,
    Alt = 4,
    Super = 8,
}
