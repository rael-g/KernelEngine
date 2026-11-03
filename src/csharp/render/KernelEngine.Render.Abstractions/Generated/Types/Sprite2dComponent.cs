using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct Sprite2dComponent
{
    public _Texture_e__FixedBuffer Texture;
    public System.Numerics.Vector4 Region;
    public System.Numerics.Vector2 Size;
    public System.Numerics.Vector2 Pivot;
    public byte FlipH;
    public byte FlipV;
    public System.Numerics.Vector4 Color;
    public uint AlphaMode;

    public float AlphaCutoff;
    public TextureHandle TextureHandle;
    public byte Attached;

    [InlineArray(128)]
    public partial struct _Texture_e__FixedBuffer
    {
        public sbyte e0;
    }
}
