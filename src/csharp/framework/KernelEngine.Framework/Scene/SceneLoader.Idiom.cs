namespace KernelEngine.Framework;

/// <summary>
/// Managed handle to a native scene loader: reads a scene file and builds its nodes,
/// components and signal connections. This part declares the constructor that calls the native
/// factory; the members that mirror the vtable are generated.
/// </summary>
public unsafe partial class SceneLoader
{
    /// <summary>
    /// Creates a native scene loader that spawns nodes in <paramref name="tree"/>, fills their
    /// components in <paramref name="ecs"/> as <paramref name="registry"/> describes them, wires
    /// connections into <paramref name="signals"/>, resolves every <c>res://</c> scene reference
    /// through <paramref name="assets"/> and reads every scene file through <paramref name="io"/>.
    /// </summary>
    /// <exception cref="ArgumentNullException">An argument other than <paramref name="signals"/> is null.</exception>
    /// <exception cref="Exception">The native factory fails.</exception>
    /// <param name="ecs">Holds the components; must outlive the loader.</param>
    /// <param name="tree">Receives the scene's nodes; must outlive the loader.</param>
    /// <param name="signals">Receives the scene's connections, or null to report and skip them.</param>
    /// <param name="registry">Describes the components; must outlive the loader.</param>
    /// <param name="assets">Resolves <c>res://</c> paths; must outlive the loader.</param>
    /// <param name="io">Reads the scene files; must outlive the loader.</param>
    public SceneLoader(KernelEngine.Ecs.INativeEcs ecs, SceneTree tree, SignalBus? signals, ComponentRegistry registry,
        AssetResolver assets, KernelEngine.Io.INativeIo io) : this(Create(ecs, tree, signals, registry, assets, io))
    {
        Hold(ecs.Owner);
        Hold(((INativeSceneTree)tree).Owner);
        Hold(signals is null ? null : ((INativeSignalBus)signals).Owner);
        Hold(((INativeComponentRegistry)registry).Owner);
        Hold(((INativeAssetResolver)assets).Owner);
        Hold(io.Owner);
    }

    private static ke_scene_loader_handle Create(KernelEngine.Ecs.INativeEcs ecs, SceneTree tree, SignalBus? signals,
        ComponentRegistry registry, AssetResolver assets, KernelEngine.Io.INativeIo io)
    {
        ArgumentNullException.ThrowIfNull(ecs);
        ArgumentNullException.ThrowIfNull(tree);
        ArgumentNullException.ThrowIfNull(registry);
        ArgumentNullException.ThrowIfNull(assets);
        ArgumentNullException.ThrowIfNull(io);

        ke_scene_loader_handle handle;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
            ecs.Native, ((INativeSceneTree)tree).Native, signals is null ? null : ((INativeSignalBus)signals).Native,
            ((INativeComponentRegistry)registry).Native, ((INativeAssetResolver)assets).Native, io.Native, &handle), "ke_scene_loader_create");
        return handle;
    }

    partial void OnDispose()
    {
    }
}
