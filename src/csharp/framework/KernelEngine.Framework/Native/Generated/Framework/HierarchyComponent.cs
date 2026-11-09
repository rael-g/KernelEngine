using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public partial struct HierarchyComponent
{
    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity Parent;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity FirstChild;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity LastChild;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity NextSibling;

    [NativeTypeName("ke_entity")]
    public global::KernelEngine.Ecs.Entity PrevSibling;
}
