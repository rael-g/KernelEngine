using KernelEngine.Common.Native;
using System.Runtime.CompilerServices;

namespace KernelEngine.Render.Native;

public partial struct ke_render_frame_globals
{
    [NativeTypeName("float[16]")]
    public _view_e__FixedBuffer view;

    [NativeTypeName("float[16]")]
    public _proj_e__FixedBuffer proj;

    [NativeTypeName("float[16]")]
    public _view_proj_e__FixedBuffer view_proj;

    [NativeTypeName("float[16]")]
    public _inv_view_proj_e__FixedBuffer inv_view_proj;

    [NativeTypeName("float[16]")]
    public _inv_proj_e__FixedBuffer inv_proj;

    [NativeTypeName("float[4]")]
    public _camera_pos_e__FixedBuffer camera_pos;

    [NativeTypeName("float[4]")]
    public _viewport_e__FixedBuffer viewport;

    public float time;

    public float dt;

    public float near_plane;

    public float far_plane;

    [InlineArray(16)]
    public partial struct _view_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _proj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _view_proj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _inv_view_proj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _inv_proj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _camera_pos_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _viewport_e__FixedBuffer
    {
        public float e0;
    }
}
