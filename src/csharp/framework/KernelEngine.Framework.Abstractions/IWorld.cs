using KernelEngine.Ecs;
using KernelEngine.Render;
using KernelEngine.Input;
namespace KernelEngine.Framework;

/// <summary>
/// The ECS simulation world — owns the registry, drives the built-in C systems
/// (TransformSystem, ScriptSystem), and exposes managed-side <see cref="ISystem"/>s.
/// </summary>
public interface IWorld : IDisposable
{
    IEcsRegistry Registry { get; }

    uint TransformComponentId { get; }
    uint HierarchyComponentId { get; }
    uint NameComponentId { get; }
    uint ScriptComponentId { get; }

    /// <summary>
    /// Returns the component ID for <typeparamref name="T"/> in this world's registry, registering
    /// it on first call. Idempotent per-world. Lets game code keep IDs out of static fields, which
    /// makes the framework safe across multiple concurrent worlds (each world owns its own ID set).
    /// </summary>
    uint GetOrRegisterComponentId<T>(string name) where T : unmanaged;

    /// <summary>Entity ID of the active camera. Render systems read this each frame.</summary>
    ulong ActiveCamera { get; set; }

    /// <summary>Registers a managed system. Systems run once per frame after the built-in C systems.</summary>
    void AddSystem(ISystem system);

    /// <summary>
    /// Registers managed per-frame callbacks for an entity, driven by the built-in C ScriptSystem.
    /// All parameters are optional — pass only the hooks the caller needs. The function-pointer
    /// plumbing is handled internally; callers stay free of <c>unsafe</c>.
    /// </summary>
    void RegisterScript(
        ulong entity,
        Action? onAwake      = null,
        Action? onStart      = null,
        Action<float>? onUpdate     = null,
        Action<float>? onLateUpdate = null,
        Action? onDestroy    = null);

    /// <summary>Removes previously-registered script callbacks for an entity (call on destruction).</summary>
    void UnregisterScript(ulong entity);

    /// <summary>Advances the simulation by one frame.</summary>
    void Update(IInputReader? input = null);
}
