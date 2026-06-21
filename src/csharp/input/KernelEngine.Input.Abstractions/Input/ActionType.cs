namespace KernelEngine.Input;

/// <summary>
/// The kind of value an <see cref="InputAction"/> produces. Determines which value field
/// of <see cref="InputActionEvent"/> is meaningful and which polling accessor applies.
/// </summary>
public enum ActionType
{
    /// <summary><c>bool</c>. Pressed-this-frame, released-this-frame, currently down.</summary>
    Button = 0,
    /// <summary><c>float</c> in [-1, +1]. E.g. joystick axis, key pair, mouse scroll-Y.</summary>
    Axis1D = 1,
    /// <summary><see cref="System.Numerics.Vector2"/>. E.g. stick, mouse delta, composite WASD.</summary>
    Axis2D = 2,
    /// <summary><see cref="System.Numerics.Vector3"/>. Rare — VR/6DoF.</summary>
    Axis3D = 3,
}

/// <summary>
/// Lifecycle phase of an <see cref="InputActionEvent"/>. Mirrors Unity Input System / UE.
/// </summary>
public enum ActionPhase
{
    /// <summary>Action transitioned from inactive to active (button down, axis crossed deadzone).</summary>
    Started   = 1,
    /// <summary>Action continues to be active; value may have changed. Emitted per frame for active axes.</summary>
    Performed = 2,
    /// <summary>Action transitioned from active to inactive (button up, axis returned to zero).</summary>
    Canceled  = 3,
}
