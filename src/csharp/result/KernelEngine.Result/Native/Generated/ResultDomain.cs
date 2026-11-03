using System.Numerics;

namespace KernelEngine.Result.Native;

[NativeTypeName("unsigned int")]
public enum ResultDomain : uint
{
    KE_RESULT_DOMAIN_GENERAL = 0,
    Asset = 1,
    Audio = 2,
    Configuration = 3,
    Ecs = 4,
    Framework = 5,
    Input = 6,
    Logger = 7,
    Math = 8,
    Physics = 9,
    Render = 10,
    ResourceCache = 11,
    Runtime = 12,
    TaskPool = 13,
    Spatial = 14,
    Text = 15,
    View = 16,
    Window = 17,
}
