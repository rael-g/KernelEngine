using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct RenderFrameGlobals
{
    public _View_e__FixedBuffer View;
    public _Proj_e__FixedBuffer Proj;
    public _ViewProj_e__FixedBuffer ViewProj;
    public _InvViewProj_e__FixedBuffer InvViewProj;
    public _InvProj_e__FixedBuffer InvProj;
    public _CameraPos_e__FixedBuffer CameraPos;
    public _Viewport_e__FixedBuffer Viewport;

    public float Time;

    public float Dt;

    public float NearPlane;

    public float FarPlane;

    [InlineArray(16)]
    public partial struct _View_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _Proj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _ViewProj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _InvViewProj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(16)]
    public partial struct _InvProj_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _CameraPos_e__FixedBuffer
    {
        public float e0;
    }

    [InlineArray(4)]
    public partial struct _Viewport_e__FixedBuffer
    {
        public float e0;
    }
}
