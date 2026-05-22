namespace KernelEngine.Kernel;

/// <summary>State of a key or mouse button in an input event. Matches GLFW action codes.</summary>
public enum InputAction
{
    /// <summary>The key or button was released.</summary>
    Up = 0,
    /// <summary>The key or button was pressed.</summary>
    Down = 1,
    /// <summary>The key was held down until it repeated.</summary>
    Hold = 2,
}
