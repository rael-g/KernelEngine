using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Audio.Native;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.EngineNodes.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_engine_nodes", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_engine_nodes_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result engine_nodes_create([NativeTypeName("ke_node_types *")] KernelEngine.Framework.Nodes.Native.ke_node_types* types, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_owner);

    [DllImport("ke_engine_nodes", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_engine_nodes_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* engine_nodes_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_engine_nodes", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_engine_nodes_set_log_callback", ExactSpelling = true)]
    public static extern void engine_nodes_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
