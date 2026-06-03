using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_tree</c> primitive from the
/// <c>ke_framework</c> plugin. Owns the unmanaged handle and exposes the three
/// universal operations the contract promotes: root, find-by-path, destroy.
/// </summary>
/// <remarks>
/// Node lifecycle ticking (Awake/Start/Update/LateUpdate) and input dispatch are
/// C#-specific and stay in <see cref="Tree"/>. This wrapper handles only the
/// language-agnostic surface.
/// </remarks>
internal sealed unsafe class NativeSceneTree : IDisposable
{
    private ke_scene_tree* _native;

    public NativeSceneTree(KernelEngine.Kernel.Native.ke_world* world, Allocator allocator)
    {
        ke_scene_tree* p;
        // ke_world is opaque to the framework binding; cast across the two ClangSharp-generated
        // type identities (Kernel.Native vs Framework.Native) — both point to the same C struct.
        var worldFw = (KernelEngine.Framework.Native.ke_world*)world;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Native.NativeMethods.scene_tree_create(worldFw, allocator.Native, &p).ToManaged());
        _native = p;
    }

    public ulong Root => _native->root(_native);

    public ulong FindNode(string nameOrPath)
    {
        var bytes = Encoding.UTF8.GetBytes(nameOrPath + "\0");
        fixed (byte* p = bytes)
        {
            return _native->find_node(_native, (sbyte*)p);
        }
    }

    public void DestroyNode(ulong entity)
    {
        KernelException.ThrowIfFailed(
            _native->destroy_node(_native, entity).ToManaged());
    }

    public void DestroyAll() => _native->destroy_all(_native);

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
