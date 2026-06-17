using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_world_create", ExactSpelling = true)]
    public static extern ke_result world_create([NativeTypeName("const ke_world_params *")] ke_world_params* @params, ke_world** out_world, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    public static extern ke_result scene_tree_create(ke_ecs* ecs, ke_scene_tree** out_tree, ke_error** out_error);

    [NativeTypeName("#define KE_COMPONENT_NAME_HIERARCHY \"hierarchy\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_HIERARCHY => "hierarchy"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_NAME \"name\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_NAME => "name"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    public static extern ke_result scene_loader_create([NativeTypeName("struct ke_world *")] ke_world* world, [NativeTypeName("const char *")] sbyte* project_root, ke_scene_loader** out_loader, ke_error** out_error);

    [NativeTypeName("#define KE_SCENE_PROPERTIES_COMPONENT_NAME \"scene_properties\"")]
    public static ReadOnlySpan<byte> KE_SCENE_PROPERTIES_COMPONENT_NAME => "scene_properties"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    public static extern ke_result input_actions_create(ke_input_actions** out_actions, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    public static extern ke_result asset_resolver_create(ke_image_loader* image_loader, ke_font_loader* font_loader, [NativeTypeName("const char *")] sbyte* project_root, ke_asset_resolver** @out, ke_error** out_error);
}
