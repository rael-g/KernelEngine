namespace KernelEngine.Input;

/// <summary>
/// Typed <see cref="Key"/>/<see cref="MouseButton"/> overloads over <see cref="IInputReader"/>'s
/// raw <c>int</c> keycode API, so game code reads <c>input.IsKeyDown(Key.W)</c> instead of
/// <c>input.IsKeyDown(87)</c>. Enum values are the GLFW codes, so these are plain casts.
/// </summary>
public static class InputReaderExtensions
{
    public static bool IsKeyDown(this IInputReader input, Key key) => input.IsKeyDown((int)key);
    public static bool IsMouseButtonDown(this IInputReader input, MouseButton button) => input.IsMouseButtonDown((int)button);
}
