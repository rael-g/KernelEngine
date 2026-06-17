namespace KernelEngine.Kernel;

/// <summary>
/// Managed apply callback invoked by the native scene loader when it encounters
/// a <c>[entity.components.X]</c> block matching a registered component type.
/// </summary>
/// <typeparam name="T">The unmanaged component struct to populate.</typeparam>
/// <param name="component">Reference to the component memory in ECS storage.</param>
/// <param name="reader">Read-only view of the TOML key-value entries in the block.</param>
public delegate void ComponentApplyCallback<T>(ref T component, in VariantReader reader) where T : unmanaged;
