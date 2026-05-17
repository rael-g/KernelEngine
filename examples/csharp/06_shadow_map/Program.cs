using System.Numerics;
using System.Diagnostics;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using KernelEngine.Render.Bgfx;
using KernelEngine.Render.Core;
using KernelEngine.Framework;
using KernelEngine.Window.Glfw;
using Microsoft.Extensions.DependencyInjection;

static (ke_vertex[] verts, ushort[] idx) BuildCube()
{
    // 24 vértices (4 por face × 6 faces) com normal própria por face
    var v = new System.Collections.Generic.List<ke_vertex>(24);
    void AddFace(Vector3 n, Vector3 t, Vector3 p0, Vector3 p1, Vector3 p2, Vector3 p3)
    {
        v.Add(new ke_vertex { x=p0.X,y=p0.Y,z=p0.Z, nx=n.X,ny=n.Y,nz=n.Z, u=0,v=0, tx=t.X,ty=t.Y,tz=t.Z,tw=1 });
        v.Add(new ke_vertex { x=p1.X,y=p1.Y,z=p1.Z, nx=n.X,ny=n.Y,nz=n.Z, u=1,v=0, tx=t.X,ty=t.Y,tz=t.Z,tw=1 });
        v.Add(new ke_vertex { x=p2.X,y=p2.Y,z=p2.Z, nx=n.X,ny=n.Y,nz=n.Z, u=1,v=1, tx=t.X,ty=t.Y,tz=t.Z,tw=1 });
        v.Add(new ke_vertex { x=p3.X,y=p3.Y,z=p3.Z, nx=n.X,ny=n.Y,nz=n.Z, u=0,v=1, tx=t.X,ty=t.Y,tz=t.Z,tw=1 });
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
    .AddConsoleSink()
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
    var light = app.ActiveWorld.Scene.AddNode(
        new LightNode
        {
            Direction = Vector3.Normalize(new Vector3(0.5f, 1f, 0.5f)),
            Color = Vector3.One,
            Intensity = 10.0f,
        },
        "Sun");
    entityCount++;

    // Camera
    var cam = app.ActiveWorld.Scene.AddNode(
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

    // Floor
    var floor = app.ActiveWorld.Scene.AddNode(new MeshNode { MaterialHandle = floorMat }, "Floor");
    floor.LocalTransform = floor.LocalTransform with 
    { 
        Scale = new Vector3(10f, 0.1f, 10f),
        Position = new Vector3(0f, -0.05f, 0f) 
    };
    entityCount++;

    // Cube (Casting shadow)
    var (cubeVerts, cubeIdx) = BuildCube();
    var cubeMesh = resources.CreateMesh(cubeVerts, cubeIdx);
    var cube = app.ActiveWorld.Scene.AddNode(new MeshNode { MeshHandle = cubeMesh, MaterialHandle = cubeMat }, "Caster");
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
