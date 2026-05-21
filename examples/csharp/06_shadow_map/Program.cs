using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Render.Bgfx;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

static (Vertex[] verts, ushort[] idx) BuildCube()
{
    // 24 vértices (4 por face × 6 faces) com normal própria por face
    var v = new System.Collections.Generic.List<Vertex>(24);
    void AddFace(Vector3 n, Vector3 t, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
    {
        v.Add(new Vertex { X=p0.X,Y=p0.Y,Z=p0.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=0,V=0, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p1.X,Y=p1.Y,Z=p1.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=1,V=0, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p2.X,Y=p2.Y,Z=p2.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=1,V=1, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
        v.Add(new Vertex { X=p3.X,Y=p3.Y,Z=p3.Z, Nx=n.X,Ny=n.Y,Nz=n.Z, U=0,V=1, Tx=t.X,Ty=t.Y,Tz=t.Z,Tw=1 });
    }
    // +X
    AddFace(new(1,0,0),  new(0,0,-1), new(0.5f,-0.5f,0.5f), new(0.5f,-0.5f,-0.5f), new(0.5f,0.5f,-0.5f), new(0.5f,0.5f,0.5f));
    // -X
    AddFace(new(-1,0,0), new(0,0,1),  new(-0.5f,-0.5f,-0.5f), new(-0.5f,-0.5f,0.5f), new(-0.5f,0.5f,0.5f), new(-0.5f,0.5f,-0.5f));
    // +Y
    AddFace(new(0,1,0),  new(1,0,0),  new(-0.5f,0.5f,0.5f), new(0.5f,0.5f,0.5f), new(0.5f,0.5f,-0.5f), new(-0.5f,0.5f,-0.5f));
    // -Y
    AddFace(new(0,-1,0), new(1,0,0),  new(-0.5f,-0.5f,-0.5f), new(0.5f,-0.5f,-0.5f), new(0.5f,-0.5f,0.5f), new(-0.5f,-0.5f,0.5f));
    // +Z
    AddFace(new(0,0,1),  new(1,0,0),  new(-0.5f,-0.5f,0.5f), new(0.5f,-0.5f,0.5f), new(0.5f,0.5f,0.5f), new(-0.5f,0.5f,0.5f));
    // -Z
    AddFace(new(0,0,-1), new(-1,0,0), new(0.5f,-0.5f,-0.5f), new(-0.5f,-0.5f,-0.5f), new(-0.5f,0.5f,-0.5f), new(0.5f,0.5f,-0.5f));

    var idx = new ushort[36];
    for (ushort f = 0; f < 6; f++)
    {
        ushort b = (ushort)(f * 4);
        idx[f*6+0] = b; idx[f*6+1] = (ushort)(b+1); idx[f*6+2] = (ushort)(b+2);
        idx[f*6+3] = b; idx[f*6+4] = (ushort)(b+2); idx[f*6+5] = (ushort)(b+3);
    }
    return (v.ToArray(), idx);
}

var services = new ServiceCollection()
    .AddKernel()
    .AddLogger()
    .AddConsoleSink(LogLevel.Info)
    .AddGlfwWindow(1280, 720, "KernelEngine — 06 Shadow Map Verification")
    .AddBgfxRenderer(Path.Combine(AppContext.BaseDirectory, "shaders"));

using var app = new Application();

int entityCount = 0;

app.OnReady = (resources) =>
{
    Console.WriteLine("[KernelEngine] Example: 06_shadow_map");
    Console.WriteLine("[KernelEngine] Features: shadow_mapping, directional_light, floor_plane, cube");

    // Directional light (Sun). Per LightNode docs, Direction is the vector pointing
    // FROM the lit surface TOWARD the light source. Sun in upper-right-back → (+x, +y, +z).
    var light = app.Scene.AddNode(
        new AnimatedSun
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = Vector3.One,
            Intensity = 10.0f,
        },
        "Sun");
    entityCount++;

    // Camera
    var cam = app.Scene.AddNode(
        new CameraNode { Fov = 60f, Near = 0.1f, Far = 1000f },
        "Camera");
    cam.LocalTransform = cam.LocalTransform with
    {
        Position = new Vector3(0f, 5.0f, 10.0f)
    };
    app.ActiveWorld.ActiveCamera = cam.Entity;
    entityCount++;

    // Materials
    var floorMat = resources.CreateMaterial(new Vector4(0.5f, 0.5f, 0.5f, 1f), metallic: 0.0f, roughness: 0.8f);
    var cubeMat = resources.CreateMaterial(new Vector4(0.8f, 0.2f, 0.2f, 1f), metallic: 0.2f, roughness: 0.3f);

    // Floor. The default mesh (handle 0) is a quad in the XY plane (normal +Z), i.e. it stands up
    // facing the camera. Rotate -90° about X to lay it flat as a ground plane (normal +Y); local Y
    // then becomes world depth, so scale BOTH X and Y for the floor size (Z is flat, irrelevant).
    var floor = app.Scene.AddNode(new MeshNode { MaterialHandle = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with
    {
        Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitX, -MathF.PI / 2f),
        Scale = new Vector3(10f, 10f, 1f),
        Position = new Vector3(0f, 0f, 0f)
    };
    entityCount++;

    // Cube (Casting shadow)
    var (cubeVerts, cubeIdx) = BuildCube();
    var cubeMesh = resources.CreateMesh(cubeVerts, cubeIdx);
    var cube = app.Scene.AddNode(new MeshNode { MeshHandle = cubeMesh, MaterialHandle = cubeMat }, "Caster");
    cube.LocalTransform = cube.LocalTransform with { Position = new Vector3(0f, 1f, 0f) };
    entityCount++;
};

Stopwatch sw = Stopwatch.StartNew();
int frameCount = 0;

app.OnUpdate = (scene, input) =>
{
    scene.ClearColor(0.1f, 0.1f, 0.15f, 1f);
    scene.SetAmbientLight(0.15f, 0.15f, 0.15f);

    frameCount++;
    if (sw.Elapsed.TotalSeconds >= 5.0)
    {
        double fps = frameCount / sw.Elapsed.TotalSeconds;
        Console.WriteLine($"[KernelEngine] FPS: {fps:F2}  Entities: {entityCount}");
        frameCount = 0;
        sw.Restart();
    }
};

app.Run(services);

// ── Helpers ──────────────────────────────────────────────────────────────────

/// <summary>
/// Directional light that sweeps its azimuth back and forth over time, so the cube's shadow
/// slides across the floor — a visual check that the shadow projection tracks the light.
/// </summary>
sealed class AnimatedSun : LightNode
{
    private float _t;

    protected override void OnUpdate(float dt)
    {
        _t += dt;
        float a = MathF.Sin(_t * 0.8f);                       // -1..1 sweep
        var dir = Vector3.Normalize(new Vector3(a * 0.8f, 1.0f, 0.5f));

        var comp = GetComponent<LightComponent>(ComponentId);
        if (comp.IsEmpty) return;
        comp[0].DirX = dir.X;
        comp[0].DirY = dir.Y;
        comp[0].DirZ = dir.Z;
    }
}
