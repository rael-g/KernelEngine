using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// An input action a node names in one of its fields, the way a scene writes it
/// (<c>move_action = "PaddleLeftMove"</c>), read as of the last evaluation of the frame.
/// </summary>
/// <param name="Owner">The node whose field holds the reference; the actions are read through its scene.</param>
/// <param name="Name">The action's name; empty when the field was not written.</param>
public readonly record struct InputAction(Node? Owner, string Name)
{
    /// <summary>A reference to <paramref name="name"/> owned by no node, for assigning to a field.</summary>
    public static implicit operator InputAction(string name) => new(null, name);

    /// <summary>True while the action is active; false for an action no map has.</summary>
    public bool Down => Read(out var a, out var id) && a.IsActionDown(id);

    /// <summary>True on the frame the action became active.</summary>
    public bool JustPressed => Read(out var a, out var id) && a.WasActionPressed(id);

    /// <summary>True on the frame the action stopped being active.</summary>
    public bool JustReleased => Read(out var a, out var id) && a.WasActionReleased(id);

    /// <summary>The one-axis value, in [-1, 1].</summary>
    public float Axis => Read(out var a, out var id) ? a.GetAxis1d(id) : 0f;

    /// <summary>The two-axis value, each component in [-1, 1].</summary>
    public Vector2 Vector
    {
        get
        {
            if (!Read(out var a, out var id)) return Vector2.Zero;
            var (x, y) = a.GetAxis2d(id);
            return new(x, y);
        }
    }

    private bool Read(out InputActions actions, out int id)
    {
        actions = null!;
        id = -1;
        if (Owner?.Host?.Actions is not { } a || string.IsNullOrEmpty(Name)) return false;
        actions = a;
        id = Owner.Host.ActionId(Name);
        return id >= 0;
    }
}

/// <summary>
/// An input map a node names in one of its fields (<c>menu_map = "Menu"</c>), switched on and off
/// as a field.
/// </summary>
/// <param name="Owner">The node whose field holds the reference.</param>
/// <param name="Name">The map's name; empty when the field was not written.</param>
public readonly record struct InputMap(Node? Owner, string Name)
{
    /// <summary>A reference to <paramref name="name"/> owned by no node, for assigning to a field.</summary>
    public static implicit operator InputMap(string name) => new(null, name);

    /// <summary>Whether the map's actions are evaluated from the next frame on; false for a map that does not exist.</summary>
    public bool Enabled
    {
        get => Owner?.Host?.Actions is { } a && a.IsMapEnabled(a.GetMapId(Name));
        set
        {
            if (Owner?.Host?.Actions is not { } a) throw new InvalidOperationException($"the input map '{Name}' belongs to no bound node");
            a.SetMapEnabled(a.GetMapId(Name), value);
        }
    }
}
