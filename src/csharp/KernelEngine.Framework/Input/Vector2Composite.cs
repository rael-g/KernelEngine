using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Factories for the common Axis2D composite bindings. Built-ins for WASD and Arrows; arbitrary
/// 4-key compositions go through <see cref="KeyQuadAxis2DBinding"/> directly.
/// </summary>
public static class Vector2Composite
{
    /// <summary>W/S/A/D → (+Y / -Y / -X / +X). The classic FPS movement composite.</summary>
    public static KeyQuadAxis2DBinding WASD() =>
        new(up: Key.W, down: Key.S, left: Key.A, right: Key.D);

    /// <summary>Arrow keys → (+Y / -Y / -X / +X). Alternative to WASD for menu/cursor input.</summary>
    public static KeyQuadAxis2DBinding Arrows() =>
        new(up: Key.Up, down: Key.Down, left: Key.Left, right: Key.Right);
}

/// <summary>
/// Factories for the common Axis1D composite bindings (key-pair derived). Arbitrary key pairs
/// go through <see cref="KeyPairAxis1DBinding"/> directly.
/// </summary>
public static class Vector1Composite
{
    /// <summary>W/S → +1 / -1. The natural vertical control for top-down paddle / elevator inputs.</summary>
    public static KeyPairAxis1DBinding WS() => new(negative: Key.S, positive: Key.W);

    /// <summary>A/D → -1 / +1. The natural horizontal control for strafe input.</summary>
    public static KeyPairAxis1DBinding AD() => new(negative: Key.A, positive: Key.D);

    /// <summary>Up/Down arrows → +1 / -1.</summary>
    public static KeyPairAxis1DBinding UpDown() => new(negative: Key.Down, positive: Key.Up);

    /// <summary>Left/Right arrows → -1 / +1.</summary>
    public static KeyPairAxis1DBinding LeftRight() => new(negative: Key.Left, positive: Key.Right);
}
