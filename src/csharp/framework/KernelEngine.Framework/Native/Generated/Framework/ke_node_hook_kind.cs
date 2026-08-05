using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

[NativeTypeName("unsigned int")]
public enum ke_node_hook_kind : uint
{
    KE_NODE_HOOK_UPDATE = 0,
}
