using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_world_create", ExactSpelling = true)]
    public static extern ke_result world_create([NativeTypeName("const ke_world_params *")] ke_world_params* @params, ke_world** out_world);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    public static extern ke_result scene_tree_create(ke_ecs* ecs, ke_allocator* alloc, ke_scene_tree** out_tree);

    [NativeTypeName("#define KE_COMPONENT_NAME_TRANSFORM \"transform\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_TRANSFORM => "transform"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_HIERARCHY \"hierarchy\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_HIERARCHY => "hierarchy"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_NAME \"name\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_NAME => "name"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_CAMERA \"camera\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_CAMERA => "camera"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_DIRECTIONAL_LIGHT \"directional_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_DIRECTIONAL_LIGHT => "directional_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_POINT_LIGHT \"point_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_POINT_LIGHT => "point_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_SPOT_LIGHT \"spot_light\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_SPOT_LIGHT => "spot_light"u8;

    [NativeTypeName("#define KE_COMPONENT_NAME_MESH \"mesh\"")]
    public static ReadOnlySpan<byte> KE_COMPONENT_NAME_MESH => "mesh"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    public static extern ke_result scene_loader_create(ke_allocator* alloc, [NativeTypeName("struct ke_world *")] ke_world* world, [NativeTypeName("const char *")] sbyte* project_root, ke_scene_loader** out_loader);

    [NativeTypeName("#define KE_SCENE_PROPERTIES_COMPONENT_NAME \"scene_properties\"")]
    public static ReadOnlySpan<byte> KE_SCENE_PROPERTIES_COMPONENT_NAME => "scene_properties"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    public static extern ke_result input_actions_create(ke_allocator* alloc, ke_input_actions** out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    public static extern ke_result asset_resolver_create(ke_allocator* alloc, ke_image_loader* image_loader, [NativeTypeName("const char *")] sbyte* project_root, ke_asset_resolver** @out);
}
