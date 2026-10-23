using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct ke_hierarchy_component
{
    [NativeTypeName("ke_entity")]
    public ulong parent;

    [NativeTypeName("ke_entity")]
    public ulong first_child;

    [NativeTypeName("ke_entity")]
    public ulong last_child;

    [NativeTypeName("ke_entity")]
    public ulong next_sibling;

    [NativeTypeName("ke_entity")]
    public ulong prev_sibling;
}
