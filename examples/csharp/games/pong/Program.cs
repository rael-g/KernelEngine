using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;

using KernelEngine.Audio.MiniAudio;
using KernelEngine.Configuration;
using KernelEngine.Ecs.Flecs;
using KernelEngine.FileSystem.Std;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Input;
using KernelEngine.Io.Pool;
using KernelEngine.Physics.Box2D;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.TaskPool.Enki;
using KernelEngine.Text.StbTrueType;
using KernelEngine.View;
using KernelEngine.Window.Glfw;

using Pong;

using static Pong.Native;

using NodesNative = KernelEngine.Framework.Nodes.Native.NativeMethods;

unsafe
{
    var projectDir = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
    var shaderDir = Path.Combine(projectDir, "shaders");
    var font = Path.Combine(projectDir, "assets", "fonts", "LiberationSans-Regular.ttf");

    using var pool = new EnkiTaskPool(uint.MaxValue);
    using var files = new StdFileSystem(".");
    using var io = new PoolIo(pool, files);

    KernelEngine.Configuration.Native.ke_configuration_handle configHandle;
    Check("configuration", KernelEngine.Configuration.Native.NativeMethods.configuration_create(&configHandle));
    using var config = new Configuration(configHandle);
    KernelEngine.Configuration.Native.ke_configuration_source_handle tomlHandle;
    Check("toml source", KernelEngine.Configuration.Native.NativeMethods.configuration_toml_create(((KernelEngine.Io.INativeIo)io).Native, &tomlHandle));
    using var toml = new ConfigurationSource(tomlHandle);
    toml.Load(config, Path.Combine(projectDir, "Project"));

    using var input = new Input();
    using var window = new GlfwWindow(input,
        config.GetString("runtime.window", "title", "Pong"),
        (int)config.GetInt("runtime.window", "width", 1280),
        (int)config.GetInt("runtime.window", "height", 720),
        config.GetBool("runtime.window", "fullscreen", false));

    using var ecs = new FlecsEcsRegistry(1048576);
    var runtimeParams = new KernelEngine.Runtime.Native.ke_runtime_params { fixed_dt = 1.0f / 60.0f, fixed_dt_max_accum = 0.25f, max_systems_per_phase = 256 };
    KernelEngine.Runtime.Native.ke_runtime_handle runtimeHandle;
    Check("runtime", KernelEngine.Runtime.Native.NativeMethods.runtime_create(((KernelEngine.Ecs.INativeEcs)ecs).Native, ((KernelEngine.TaskPool.INativeTaskPool)pool).Native, &runtimeParams, &runtimeHandle));
    var runtime = Runtime.Borrow(runtimeHandle.@ref);

    using var gpu = new WebgpuGpuDevice(null, false, false);
    var mailbox = config.GetString("runtime.renderer", "present_mode", "fifo") == "mailbox";
    using var target = new WebgpuWindowGpuRenderTarget(gpu, window, mailbox ? GpuPresentMode.Mailbox : GpuPresentMode.Fifo);

    using var fonts = new StbFontLoader(io);
    KernelEngine.Asset.Native.ke_asset_resolver_handle assetsHandle;
    fixed (byte* root = Utf8(projectDir))
        Check("asset resolver", KernelEngine.Framework.Native.NativeMethods.asset_resolver_create(null, ((KernelEngine.Text.INativeFontLoader)fonts).Native, (sbyte*)root, ((KernelEngine.Io.INativeIo)io).Native, &assetsHandle));
    using var assets = new AssetResolver(assetsHandle);

    KernelEngine.Framework.Native.ke_scene_tree_handle treeHandle;
    Check("scene tree", KernelEngine.Framework.Native.NativeMethods.scene_tree_create(((KernelEngine.Ecs.INativeEcs)ecs).Native, ((KernelEngine.Runtime.INativeRuntime)runtime).Native, &treeHandle));
    using var tree = new SceneTree(treeHandle);

    using var binder = new GroupedRenderResourceBinder(gpu, shaderDir, io);
    var clearColor = new Vector4(
        (float)config.GetDouble("render", "clear_color.0", 0.0),
        (float)config.GetDouble("render", "clear_color.1", 0.0),
        (float)config.GetDouble("render", "clear_color.2", 0.0),
        (float)config.GetDouble("render", "clear_color.3", 1.0));
    using var service = new DefaultRenderService(gpu, target, ecs, io, binder, shaderDir, GpuTextureFormat.Rgba16Float, GpuTextureFormat.D32Float, clearColor);
    using var viewSpace = new RhViewSpace();
    using var camera = new DefaultRenderCamera(viewSpace, gpu);
    using var scene = new DefaultRenderSceneResolve(runtime, ecs, service);
    using var frame = new DefaultRenderFrame(runtime, ecs, service, camera, scene);
    using var shadow = new RenderShadow(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, 1024, 25.0f, 20.0f, 0.1f, 50.0f);
    using var cluster = new RenderCluster(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, 16, 9, 24, 64);
    using var gbuffer = new RenderGbuffer(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
    using var deferred = new RenderDeferredLighting(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, true, gbuffer.Resources, shadow.Resources, cluster.Resources);
    using var forward = new RenderForward(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, true, shadow.Resources, cluster.Resources);
    using var tonemap = new RenderTonemap(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
    using var ui = new DefaultRenderUi(runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
    using var labels = new RenderLabelResolve(runtime, ecs, service, gpu, viewSpace, camera, scene, frame, ui, assets, font);

    using var physics = new Box2dPhysics2D(
        (float)config.GetDouble("runtime.physics_2d", "gravity_x", 0.0),
        (float)config.GetDouble("runtime.physics_2d", "gravity_y", 0.0));
    var bodiesParams = new KernelEngine.Physics.Native.ke_physics_body2d_module_params { runtime = ((KernelEngine.Runtime.INativeRuntime)runtime).Native, ecs = ((KernelEngine.Ecs.INativeEcs)ecs).Native, physics = ((KernelEngine.Physics.INativePhysics2d)physics).Native, scene_tree = ((KernelEngine.Framework.INativeSceneTree)tree).Native };
    KernelEngine.Physics.Native.ke_physics_body2d_module_handle bodies;
    Check("body2d module", KernelEngine.Physics.Native.NativeMethods.physics_body2d_module_create(&bodiesParams, &bodies));

    using var audio = new MiniaudioAudio(io);
    KernelEngine.Audio.Native.ke_sound_module_handle sounds;
    fixed (byte* root = Utf8(projectDir))
    {
        var soundConfig = new KernelEngine.Audio.Native.SoundModuleConfig { Root = (sbyte*)root };
        Check("sound module", KernelEngine.Audio.Native.NativeMethods.sound_module_create(((KernelEngine.Runtime.INativeRuntime)runtime).Native, ((KernelEngine.Ecs.INativeEcs)ecs).Native, ((KernelEngine.Audio.INativeAudio)audio).Native, &soundConfig, &sounds));
    }

    KernelEngine.Framework.Native.ke_input_actions_handle actions;
    fixed (byte* section = "input"u8)
    {
        var actionsConfig = new KernelEngine.Framework.Native.InputActionsConfig { Section = (sbyte*)section };
        Check("input actions", KernelEngine.Framework.Native.NativeMethods.input_actions_create(((KernelEngine.Runtime.INativeRuntime)runtime).Native, ((KernelEngine.Input.INativeInput)input).Native, ((KernelEngine.Configuration.INativeConfiguration)config).Native, &actionsConfig, &actions));
    }
    ke_node_types_handle types;
    Check("node types", NodesNative.node_types_create(((KernelEngine.Runtime.INativeRuntime)runtime).Native, ((KernelEngine.Ecs.INativeEcs)ecs).Native, ((KernelEngine.Framework.INativeSceneTree)tree).Native, actions.@ref, &types));
    ke_scene_files_handle scenes;
    Check("scene files", NodesNative.scene_files_create(((KernelEngine.Ecs.INativeEcs)ecs).Native, types.@ref, ((KernelEngine.Framework.INativeAssetResolver)assets).Native, ((KernelEngine.Io.INativeIo)io).Native, &scenes));

    EngineNodeTypes.Register(types.@ref);
    var game = Game.Register(types.@ref);

    var firstScene = $"res://scenes/{config.GetString("project", "default_scene", "Menu")}.scene.toml";
    Check("first scene", Game.OpenSlot(game, ((KernelEngine.Runtime.INativeRuntime)runtime).Native->commands(((KernelEngine.Runtime.INativeRuntime)runtime).Native), firstScene));

    var clock = Stopwatch.StartNew();
    var previous = clock.Elapsed.TotalSeconds;
    while (!window.ShouldClose() && !runtime.ExitRequested())
    {
        window.PollEvents();
        var current = clock.Elapsed.TotalSeconds;
        runtime.Tick((float)(current - previous));
        previous = current;
    }
    Check("flush render", ((KernelEngine.Runtime.INativeRuntime)runtime).Native->flush_render(((KernelEngine.Runtime.INativeRuntime)runtime).Native));
    runtime.UnloadModules();

    scenes.destroy(scenes.@ref);
    types.destroy(types.@ref);
    actions.destroy(actions.@ref);
    sounds.destroy(sounds.@ref);
    bodies.destroy(bodies.@ref);
    Game.Free(game);
    runtimeHandle.destroy(runtimeHandle.@ref);
}
