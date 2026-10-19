using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_module_create", ExactSpelling = true)]
    public static extern ke_physics_body2d_module_handle physics_body2d_module_create([NativeTypeName("const ke_physics_body2d_module_params *")] ke_physics_body2d_module_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_scene_component_set_handle")]
    public static extern KernelEngine.Framework.Native.ke_scene_component_set_handle physics_scene_components_create();
}
