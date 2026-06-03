using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public partial struct ke_resource_command
{
    public ke_resource_command_kind kind;

    [NativeTypeName("__AnonymousRecord_resource_queue_L86_C9")]
    public _u_e__Union u;

    [StructLayout(LayoutKind.Explicit)]
    public partial struct _u_e__Union
    {
        [FieldOffset(0)]
        public ke_create_mesh_cmd create_mesh;

        [FieldOffset(0)]
        public ke_create_texture_cmd create_texture;

        [FieldOffset(0)]
        public ke_create_cubemap_cmd create_cubemap;

        [FieldOffset(0)]
        public ke_create_material_cmd create_material;

        [FieldOffset(0)]
        public ke_create_shadow_map_cmd create_shadow_map;

        [FieldOffset(0)]
        public ke_destroy_handle_cmd destroy;
    }
}
