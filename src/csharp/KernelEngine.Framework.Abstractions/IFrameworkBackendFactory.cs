using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Constructs the runtime backends the sugar layer depends on. Registered as a singleton by
/// the chosen backend assembly (today only <c>KernelEngine.Framework.Native</c> via
/// <c>AddNativeFramework()</c>); resolved by <c>Application</c> when the renderer/loaders
/// are ready, since some backends (asset resolver, resource queue) need other plugins injected.
/// </summary>
public interface IFrameworkBackendFactory
{
    IInputActionsBackend  CreateInputActions();
    ISceneTreeBackend     CreateSceneTree(IWorld world);
    ISceneLoaderBackend   CreateSceneLoader(IWorld world,
                                             ISceneTreeBackend tree,
                                             INodeTypeRegistry registry,
                                             string projectRoot);
    IResourceCacheBackend CreateResourceCache();
    IAssetResolverBackend CreateAssetResolver(IImageLoader? imageLoader, string projectRoot);
    IResourceCommandQueue CreateResourceQueue();
    INodeTypeRegistry     CreateNodeTypeRegistry();
}
