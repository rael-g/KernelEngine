using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Backend contract for the input-action system. Implemented by the native plugin wrapper
/// (<c>NativeInputActions</c> in <c>KernelEngine.Framework.Native</c>) — sugar types
/// (<see cref="InputActionMap{TEnum}"/>) consume only this interface, never the concrete
/// pointer-holding wrapper.
/// </summary>
public interface IInputActionsBackend : IDisposable
{
    /// <summary>
    /// CLR type of the game's action enum this backend is bound to. The dispatcher writes
    /// it onto every event fired by <see cref="Evaluate"/>.
    /// </summary>
    Type EnumType { get; set; }

    /// <summary>Loads bindings from a <c>.input</c> TOML file at <paramref name="path"/>.</summary>
    void Load(string path);

    /// <summary>Registers a new action by name; returns the assigned id.</summary>
    int AddAction(string name, ActionType type);

    void BindKey(int actionId, Key key);
    void BindMouseButton(int actionId, MouseButton button);
    void BindKeyPair(int actionId, Key negative, Key positive);
    void BindKeyQuad(int actionId, Key up, Key down, Key left, Key right);

    /// <summary>Returns the id for <paramref name="name"/>, or -1 when unknown.</summary>
    int GetActionId(string name);

    bool IsActionDown(int id);
    bool WasActionPressed(int id);
    bool WasActionReleased(int id);

    float   GetAxis1D(int id);
    Vector2 GetAxis2D(int id);
    Vector3 GetAxis3D(int id);

    /// <summary>
    /// Runs one frame of dispatch against <paramref name="snapshot"/>, appending every
    /// phase-transition event to <paramref name="output"/>.
    /// </summary>
    void Evaluate(IInputReader snapshot, List<InputActionEvent> output);
}
