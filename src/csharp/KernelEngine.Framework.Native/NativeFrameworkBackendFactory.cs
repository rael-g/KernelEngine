using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Concrete <see cref="IFrameworkBackendFactory"/> producing the C-plugin-backed implementations
/// (<see cref="NativeInputActions"/>, <see cref="NativeSceneTree"/>, <see cref="NativeSceneLoader"/>,
/// <see cref="NativeResourceCache"/>, <see cref="NativeAssetResolver"/>, <see cref="NativeResourceQueue"/>,
/// <see cref="NodeTypeRegistry"/>). Registered via the <c>AddNativeFramework()</c> DI extension.
/// </summary>
public sealed unsafe class NativeFrameworkBackendFactory : IFrameworkBackendFactory
{
    public IInputActionsBackend CreateInputActions() =>
        new NativeInputActions(new MallocAllocator());

    public ISceneTreeBackend CreateSceneTree(IWorld world) =>
        new NativeSceneTree(((World)world).Native, new MallocAllocator());

    public ISceneLoaderBackend CreateSceneLoader(IWorld world,
                                                   ISceneTreeBackend tree,
                                                   INodeTypeRegistry? registry,
                                                   string projectRoot) =>
        // registry is ignored — kept in the signature for one release so
        // external callers still compile; deletion lands in a follow-up.
        new NativeSceneLoader(new MallocAllocator(), (World)world,
                              (NativeSceneTree)tree,
                              projectRoot);

    public IResourceCacheBackend CreateResourceCache() =>
        new NativeResourceCache(new MallocAllocator());

    public IAssetResolverBackend CreateAssetResolver(IImageLoader? imageLoader, string projectRoot)
    {
        KernelEngine.Kernel.Native.ke_image_loader* nativeImg = null;
        if (imageLoader is INativeImageLoader ni) nativeImg = ni.Native;
        return new NativeAssetResolver(new MallocAllocator(), nativeImg, projectRoot);
    }

    public IResourceCommandQueue CreateResourceQueue() =>
        new NativeResourceQueue(new MallocAllocator());

    public INodeTypeRegistry CreateNodeTypeRegistry() =>
        new NodeTypeRegistry(new MallocAllocator());
}
