using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NodeTypeRegistryNativeMethods
{
    [DllImport("ke_node_type_registry", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_type_registry_create", ExactSpelling = true)]
    public static extern ke_result node_type_registry_create(ke_allocator* alloc, ke_node_type_registry** out_registry);
}
