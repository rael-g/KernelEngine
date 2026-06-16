using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_world_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int world_create([NativeTypeName("const ke_world_params *")] ke_world_params* @params, ke_world** out_world);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int scene_tree_create(ke_ecs* ecs, ke_scene_tree** out_tree);

    [NativeTypeName("#define KE_COMPONENT_NAME_HIERARCHY \"hierarchy\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_HIERARCHY => "hierarchy"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_NAME \"name\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_NAME => "name"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int scene_loader_create([NativeTypeName("struct ke_world *")] ke_world* world, [NativeTypeName("const char *")] sbyte* project_root, ke_scene_loader** out_loader);

    [NativeTypeName("#define KE_SCENE_PROPERTIES_COMPONENT_NAME \"scene_properties\"")]
    public static ReadOnlySpan<byte> KE_SCENE_PROPERTIES_COMPONENT_NAME => "scene_properties"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int input_actions_create(ke_input_actions** out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern int asset_resolver_create(ke_image_loader* image_loader, ke_font_loader* font_loader, [NativeTypeName("const char *")] sbyte* project_root, ke_asset_resolver** @out);
}
