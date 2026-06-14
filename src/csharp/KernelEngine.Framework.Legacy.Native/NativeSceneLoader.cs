using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Legacy.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Managed wrapper over the native <c>ke_scene_loader</c> primitive. The C plugin handles
/// TOML parsing, nested scene resolution, transforms, component-field writes, and
/// per-language script-factory dispatch. The C# shell only owns the unmanaged handle and
/// presents the path-string ABI in a managed-friendly form.
/// </summary>
internal sealed unsafe class NativeSceneLoader : ISceneLoaderBackend
{
    private GCHandle _scriptHandle;
    private Func<ulong, string, bool>? _scriptClosure;

    private ke_scene_loader* _native;

    public NativeSceneLoader(Allocator allocator,
                              ke_world* world,
                              NativeSceneTree tree,
                              string? projectRoot)
    {
        ke_scene_loader* p;
        byte[]? rootBytes = projectRoot is null ? null : Encoding.UTF8.GetBytes(projectRoot + "\0");
        var worldFw = (KernelEngine.Framework.Legacy.Native.ke_world*)world;
        fixed (byte* rootPtr = rootBytes)
        {
            KernelException.ThrowIfFailed(
                KernelEngine.Framework.Legacy.Native.NativeMethods.scene_loader_create(
                    allocator.Native,
                    worldFw,
                    tree.NativePtr,
                    (sbyte*)rootPtr,
                    &p).ToManaged());
        }
        _native = p;
    }

    public void Load(string path)
    {
        var bytes = Encoding.UTF8.GetBytes(path + "\0");
        s_pendingException = null;
        ke_result result;
        fixed (byte* p = bytes)
        {
            result = _native->load(_native, (sbyte*)p);
        }
        // A managed exception inside the script trampoline was captured
        // out-of-band; rethrow it now that the native stack has unwound.
        if (s_pendingException is { } pending)
        {
            s_pendingException = null;
            throw pending;
        }
        KernelException.ThrowIfFailed(result.ToManaged());
    }

    // Pending exception slot for any managed throw that occurs inside the
    // ScriptTrampoline. Cleared at the start of every Load.
    [System.Runtime.CompilerServices.ModuleInitializer]
    internal static void InitPendingException() => s_pendingException = null;
    private static System.Exception? s_pendingException;

    public void RegisterScriptFactory(Func<ulong, string, bool> factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        if (_native is null) throw new ObjectDisposedException(nameof(NativeSceneLoader));

        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
        _scriptClosure = factory;
        _scriptHandle  = GCHandle.Alloc(factory);
        var ctx        = GCHandle.ToIntPtr(_scriptHandle);

        var rc = _native->register_script_factory(_native, &ScriptTrampoline, (void*)ctx);
        KernelException.ThrowIfFailed(rc.ToManaged());
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static ke_result ScriptTrampoline(void* ctx, ulong entity, sbyte* typeName)
    {
        try
        {
            var gch = GCHandle.FromIntPtr((IntPtr)ctx);
            if (gch.Target is Func<ulong, string, bool> factory)
            {
                var name = typeName != null ? Marshal.PtrToStringUTF8((IntPtr)typeName) ?? "" : "";
                return factory(entity, name) ? ke_result.KE_OK : ke_result.KE_ERROR_NOT_FOUND;
            }
        }
        catch (Exception ex)
        {
            // Surface managed exceptions: store and rethrow once the native
            // stack has unwound (the C plugin can't propagate managed throws).
            s_pendingException ??= ex;
        }
        return ke_result.KE_ERROR;
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
        if (_scriptHandle.IsAllocated) _scriptHandle.Free();
    }
}
