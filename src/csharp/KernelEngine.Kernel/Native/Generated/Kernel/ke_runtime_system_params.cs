// MANUAL PATCH PENDING REGEN: extended with access_list/access_count/exclusive
// fields that R2.5c added to the C ke_runtime_system_params layout. ClangSharp
// regen will overwrite this; do not lose the field order / signature change of
// `execute` (now ke_system_ctx*, not ke_runtime*).
namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_runtime_system_params
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    public ke_phase phase;

    [NativeTypeName("const ke_component_access *")]
    public ke_component_access* access_list;

    public uint access_count;

    [NativeTypeName("bool")]
    public byte exclusive;

    public void* user_data;

    [NativeTypeName("void (*)(ke_system_ctx *, void *, float)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void*, float, void> execute;
}

// Helper types added alongside the patch — also pending real ClangSharp regen.
public enum ke_access
{
    KE_ACCESS_READ  = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
}

public unsafe partial struct ke_component_access
{
    public uint cid;
    public ke_access access;
}
