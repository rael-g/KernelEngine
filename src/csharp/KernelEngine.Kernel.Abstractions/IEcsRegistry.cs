namespace KernelEngine.Kernel;

/// <summary>
/// Managed view over the ECS component registry. Component-data accessors that require
/// pointer arithmetic (raw queries, in-place mutation) live on the concrete
/// <c>KernelEngine.Kernel.EcsRegistry</c> class — this interface only exposes the safe surface
/// callable from Framework / user code.
/// </summary>
public interface IEcsRegistry
{
    /// <summary>Registers a managed component type and returns its stable component ID.</summary>
    uint RegisterComponent<T>(string name) where T : unmanaged;

    /// <summary>Returns true if <paramref name="entity"/> has the component with the given <paramref name="cid"/>.</summary>
    bool HasComponent(ulong entity, uint cid);
}
