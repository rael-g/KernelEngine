namespace KernelEngine.Kernel;

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

    /// <summary>Entity ID of the active camera. Render systems read this each frame.</summary>
    ulong ActiveCamera { get; set; }

    /// <summary>Registers a managed system. Systems run once per frame after the built-in C systems.</summary>
    void AddSystem(ISystem system);

    /// <summary>Advances the simulation by one frame.</summary>
    Result Update(IFramePacket? packet = null, IInputReader? input = null);
}
