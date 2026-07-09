using KernelEngine.Render;
using KernelEngine.Input;
namespace KernelEngine.Framework;

/// <summary>
/// Declares which components a system intends to read from or write to.
/// Used by the scheduler to run non-conflicting systems in parallel.
/// </summary>
public readonly struct ComponentAccess
{
    /// <summary>IDs of components this system only reads.</summary>
    public IReadOnlyList<uint> Reads { get; init; }

    /// <summary>IDs of components this system might modify.</summary>
    public IReadOnlyList<uint> Writes { get; init; }

    /// <summary>Empty access declaration. Forces serial execution as a safety barrier.</summary>
    public static readonly ComponentAccess None = new() { Reads = [], Writes = [] };
}

/// <summary>
/// A managed simulation system registered with <see cref="IWorld.AddSystem"/>.
/// Called once per frame after the built-in C systems (Script + Transform).
/// </summary>
public interface ISystem
{
    /// <summary>Advances this system by one frame.</summary>
    /// <param name="world">The active ECS world.</param>
    /// <param name="dt">Delta time since last frame.</param>
    /// <param name="input">Immutable snapshot of input state for this frame.</param>
    void Update(IWorld world, float dt, IInputReader? input = null);

    /// <summary>
    /// Returns the component access pattern for this system.
    /// Default implementation returns <see cref="ComponentAccess.None"/> (serial barrier).
    /// </summary>
    ComponentAccess GetAccess() => ComponentAccess.None;
}
