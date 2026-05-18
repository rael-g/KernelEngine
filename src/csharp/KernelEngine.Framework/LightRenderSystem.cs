using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that reads directional/point/spot light components
/// from the ECS and writes them into the frame packet. Replaces the legacy C++
/// LightSystem.
/// </summary>
public sealed unsafe class LightRenderSystem : ISystem
{
    private readonly uint _lightCid;
    private readonly uint _pointCid;
    private readonly uint _spotCid;
    private readonly uint _transformCid;

    public LightRenderSystem(uint lightCid, uint pointCid, uint spotCid, uint transformCid)
    {
        _lightCid = lightCid;
        _pointCid = pointCid;
        _spotCid = spotCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld iworld, float dt, IFramePacket? ipacket = null, IInputReader? input = null)
    {
        if (ipacket == null) return;
        var world = (World)iworld;
        var packet = (FramePacket)ipacket;

        var registry = world.Registry;
        var raw = packet.NativePointer;

        // ── Directional ────────────────────────────────────────────────────────
        var dirLights = registry.Query<LightComponent>(_lightCid);
        if (dirLights.Length > 0)
        {
            var l = dirLights.Data[0];
            raw->dir_light.dir_x = l.DirX;
            raw->dir_light.dir_y = l.DirY;
            raw->dir_light.dir_z = l.DirZ;
            raw->dir_light.r = l.R;
            raw->dir_light.g = l.G;
            raw->dir_light.b = l.B;
            raw->dir_light.intensity = l.Intensity;
            raw->has_dir_light = true;
        }

        // ── Point ──────────────────────────────────────────────────────────────
        var pointLights = registry.Query<PointLightComponent>(_pointCid);
        var pointCap = raw->point_light_capacity;
        var pointN = (uint)Math.Min(pointLights.Length, (int)pointCap);
        for (uint i = 0; i < pointN; i++)
        {
            var tc = registry.GetComponent<TransformComponent>(pointLights.Entities[(int)i], _transformCid);
            var c = pointLights.Data[(int)i];
            raw->point_lights[i].pos_x = tc != null ? tc->Position.X : 0f;
            raw->point_lights[i].pos_y = tc != null ? tc->Position.Y : 0f;
            raw->point_lights[i].pos_z = tc != null ? tc->Position.Z : 0f;
            raw->point_lights[i].radius = c.Radius;
            raw->point_lights[i].r = c.R;
            raw->point_lights[i].g = c.G;
            raw->point_lights[i].b = c.B;
            raw->point_lights[i].intensity = c.Intensity;
        }
        raw->point_light_count = pointN;

        // ── Spot ───────────────────────────────────────────────────────────────
        var spotLights = registry.Query<SpotLightComponent>(_spotCid);
        var spotCap = raw->spot_light_capacity;
        var spotN = (uint)Math.Min(spotLights.Length, (int)spotCap);
        for (uint i = 0; i < spotN; i++)
        {
            var tc = registry.GetComponent<TransformComponent>(spotLights.Entities[(int)i], _transformCid);
            var c = spotLights.Data[(int)i];
            raw->spot_lights[i].pos_x = tc != null ? tc->Position.X : 0f;
            raw->spot_lights[i].pos_y = tc != null ? tc->Position.Y : 0f;
            raw->spot_lights[i].pos_z = tc != null ? tc->Position.Z : 0f;
            raw->spot_lights[i].range = c.Range;
            raw->spot_lights[i].dir_x = c.DirX;
            raw->spot_lights[i].dir_y = c.DirY;
            raw->spot_lights[i].dir_z = c.DirZ;
            raw->spot_lights[i].inner_angle = c.InnerAngle;
            raw->spot_lights[i].outer_angle = c.OuterAngle;
            raw->spot_lights[i].r = c.R;
            raw->spot_lights[i].g = c.G;
            raw->spot_lights[i].b = c.B;
            raw->spot_lights[i].intensity = c.Intensity;
        }
        raw->spot_light_count = spotN;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_lightCid, _pointCid, _spotCid, _transformCid],
        Writes = []
    };
}
