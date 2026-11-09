using System.Numerics;
using System.Runtime.CompilerServices;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public partial struct Sprite2DComponent
{
    public _TextureBytes_e__FixedBuffer TextureBytes;
    public System.Numerics.Vector4 Region;
    public System.Numerics.Vector2 Size;
    public System.Numerics.Vector2 Pivot;
    public byte FlipH;
    public byte FlipV;
    public System.Numerics.Vector4 Color;
    public AlphaMode AlphaMode;

    public float AlphaCutoff;
    public TextureHandle TextureHandle;
    public byte Attached;

    [InlineArray(128)]
    public partial struct _TextureBytes_e__FixedBuffer
    {
        public sbyte e0;
    }
}
