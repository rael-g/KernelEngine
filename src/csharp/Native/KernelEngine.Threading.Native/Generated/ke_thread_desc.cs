using System.Runtime.InteropServices;

namespace KernelEngine.Threading.Native;

/// <summary>Construction parameters for ke_thread_create.</summary>
public unsafe partial struct ke_thread_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("void (*)(void *)")]
    public delegate* unmanaged[Cdecl]<void*, void> func;

    public void* user_data;

    [NativeTypeName("uint64_t")]
    public ulong affinity_mask;
}
