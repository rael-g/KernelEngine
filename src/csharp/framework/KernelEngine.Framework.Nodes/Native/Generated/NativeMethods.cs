using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_types_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result node_types_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_scene_tree *")] KernelEngine.Framework.Native.ke_scene_tree* scene_tree, [NativeTypeName("ke_input_actions *")] KernelEngine.Framework.Native.ke_input_actions* input_actions, ke_node_types_handle* out_types);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_files_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scene_files_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_node_types* node_types, [NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* assets, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, ke_scene_files_handle* out_files);
}
