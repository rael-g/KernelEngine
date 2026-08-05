using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_node_host_handle
{
    public ke_node_host* @ref;

    [NativeTypeName("void (*)(ke_node_host *)")]
    public delegate* unmanaged[Cdecl]<ke_node_host*, void> destroy;
}
