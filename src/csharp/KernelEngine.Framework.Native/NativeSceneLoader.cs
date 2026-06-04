using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_loader</c> primitive. The C plugin handles
/// TOML parsing, nested scene resolution, transforms, and property dispatch via
/// <c>ke_node_type_registry</c> callbacks. The C# shell only owns the unmanaged handle and
/// presents the path-string ABI in a managed-friendly form.
/// </summary>
internal sealed unsafe class NativeSceneLoader : ISceneLoaderBackend
{
    private ke_scene_loader* _native;

    public NativeSceneLoader(Allocator allocator,
                              World world,
                              NativeSceneTree tree,
                              NodeTypeRegistry registry,
                              string? projectRoot)
    {
        ke_scene_loader* p;
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        // ke_world is opaque to this plugin binding; cross-cast across Kernel.Native / Framework.Native
        // generated identities (both reference the same C struct).
        var worldFw = (KernelEngine.Framework.Native.ke_world*)world.Native;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Native.NativeMethods.scene_loader_create(
                    allocator.Native,
                    worldFw,
                    tree.NativePtr,
                    registry.Native,
                    (sbyte*)rootPtr,
                    &p).ToManaged());
        }
        _native = p;
    }

    public void Load(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        NodeTypeRegistry.PendingTrampolineException = null;
        ke_result result;
        fixed (byte* p = bytes)
        {
            result = _native->load(_native, (sbyte*)p);
        }
        // A managed exception inside the create/set_property trampolines was captured
        // out-of-band; rethrow it now that the native stack has unwound.
        if (NodeTypeRegistry.PendingTrampolineException is { } pending)
        {
            NodeTypeRegistry.PendingTrampolineException = null;
            throw pending;
        }
        KernelException.ThrowIfFailed(result.ToManaged());
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
