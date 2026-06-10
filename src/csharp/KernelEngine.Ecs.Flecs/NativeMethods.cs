using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Ecs.Flecs;

/// <summary>
/// Hand-rolled P/Invoke for ke_ecs_flecs_create. Until R2.5c we keep this
/// minimal (one function); the ClangSharp-generated bindings come back when
/// the ke_ecs surface expands (multi-component query + filters + observers).
/// </summary>
internal static unsafe partial class NativeMethods
{
    [DllImport("ke_ecs_flecs", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_ecs_flecs_create", ExactSpelling = true)]
    internal static extern ke_result ecs_flecs_create(
        ke_allocator* alloc,
        ke_ecs_flecs_params* @params,
        ke_ecs** out_ecs);
}

/// <summary>
/// Layout-compatible mirror of the C <c>ke_ecs_flecs_params</c> struct.
/// One <c>int</c> reserved field; expanded as the plugin grows.
/// </summary>
internal struct ke_ecs_flecs_params
{
    public int reserved;
}
