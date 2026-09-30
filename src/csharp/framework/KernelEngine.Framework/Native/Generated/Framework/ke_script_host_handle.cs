using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_script_host_handle
{
    public ke_script_host* @ref;

    [NativeTypeName("void (*)(ke_script_host *)")]
    public delegate* unmanaged[Cdecl]<ke_script_host*, void> destroy;
}
