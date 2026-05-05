using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Read-only interface for input state. Used by the simulation thread.
/// </summary>
public interface IInputReader
{
    bool IsKeyDown(int keyCode);
    bool IsKeyPressed(int keyCode);
    bool IsKeyReleased(int keyCode);

    Vector2 MousePosition { get; }
    Vector2 MouseDelta { get; }
    Vector2 ScrollDelta { get; }

    bool IsMouseButtonDown(int button);
    bool IsMouseButtonPressed(int button);
    bool IsMouseButtonReleased(int button);
}
