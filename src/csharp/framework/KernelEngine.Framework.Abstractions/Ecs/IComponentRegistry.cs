namespace KernelEngine.Framework;

/// <summary>
/// Maps managed component types to their runtime ECS component IDs.
/// Implemented by <c>ComponentRegistry</c> in Framework; consumed by
/// <c>Tree</c> and contributors in Toolkit via this interface.
/// </summary>
public interface IComponentRegistry
{
    /// <summary>Returns the ECS component ID for <typeparamref name="T"/>, registering it on first call.</summary>
    uint CidOf<T>() where T : unmanaged;
}
