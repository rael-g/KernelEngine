using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;

using KernelEngine.Audio.Native;
using KernelEngine.Common;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Physics;
using KernelEngine.Render;

using NativeResult = KernelEngine.Result.Native.Result;

namespace Pong;

/// <summary>What Pong needs from C that the bindings leave to the caller: checked results and native text.</summary>
static unsafe class Native
{
    /// <summary>Exits with the result code when <paramref name="result"/> is not OK.</summary>
    public static void Check(string what, NativeResult result)
    {
        if (result == NativeResult.Ok) return;
        Console.Error.WriteLine($"{what} failed with result code 0x{(uint)result:x8}");
        Environment.Exit(1);
    }

    /// <summary>The NUL-terminated UTF-8 bytes of <paramref name="text"/>.</summary>
    public static byte[] Utf8(string text) => Encoding.UTF8.GetBytes(text + "\0");

    /// <summary>A NUL-terminated UTF-8 copy of <paramref name="text"/> that lives as long as the process.</summary>
    public static sbyte* Forever(string text)
    {
        var bytes = Utf8(text);
        var memory = (byte*)NativeMemory.Alloc((nuint)bytes.Length);
        bytes.CopyTo(new Span<byte>(memory, bytes.Length));
        return (sbyte*)memory;
    }

    /// <summary>An unmanaged copy of <paramref name="value"/> that lives as long as the process.</summary>
    public static T* Forever<T>(T value) where T : unmanaged
    {
        var memory = (T*)NativeMemory.AlignedAlloc((nuint)sizeof(T), 16);
        *memory = value;
        return memory;
    }

    /// <summary>An unmanaged array of <paramref name="values"/> that lives as long as the process.</summary>
    public static T* Forever<T>(ReadOnlySpan<T> values) where T : unmanaged
    {
        var memory = (T*)NativeMemory.AlignedAlloc((nuint)(sizeof(T) * values.Length), 16);
        values.CopyTo(new Span<T>(memory, values.Length));
        return memory;
    }

    /// <summary>Writes <paramref name="text"/> into a fixed char buffer of <paramref name="capacity"/> bytes, NUL-terminated.</summary>
    public static void Write(sbyte* buffer, int capacity, string text)
    {
        var span = new Span<byte>(buffer, capacity);
        span.Clear();
        Encoding.UTF8.GetBytes(text.AsSpan(), span[..(capacity - 1)]);
    }

    /// <summary>The text of a NUL-terminated fixed char buffer.</summary>
    public static string Read(sbyte* buffer) => Marshal.PtrToStringUTF8((nint)buffer) ?? "";

    /// <summary>The field table entry of a member: its name, variant type, offset and the bytes a scene may write.</summary>
    public static ComponentField Field(string name, VariantType type, int offset, int size) =>
        new() { Name = Forever(name), Type = type, Offset = (uint)offset, Size = (uint)size };

    /// <summary>The description of <typeparamref name="T"/> registered as <paramref name="name"/> with <paramref name="fields"/>.</summary>
    public static ke_component_params* Component<T>(string name, ReadOnlySpan<ComponentField> fields) where T : unmanaged =>
        Forever(new ke_component_params
        {
            name = Forever(name),
            size = (nuint)sizeof(T),
            alignment = (nuint)Math.Min(sizeof(T) & -sizeof(T), 16),
            fields = fields.IsEmpty ? null : Forever(fields),
            field_count = (uint)fields.Length,
        });
}

/// <summary>The engine's node types the scenes name, with the values their nodes are born with.</summary>
static unsafe class EngineNodeTypes
{
    /// <summary>Registers the engine node types Pong's scenes use.</summary>
    public static void Register(ke_node_types* types)
    {
        var transform = Native.Forever(new TransformComponent { Rotation = Quaternion.Identity, Scale = Vector3.One });
        var transform2d = Native.Forever(new Transform2dComponent { Scale = Vector2.One });
        var camera = Native.Forever(new CameraComponent { Fov = 60.0f, NearPlane = 0.1f, FarPlane = 1000.0f, OrthographicSize = 5.0f, CullMask = 0xFFFFFFFFu });
        var ambient = Native.Forever(new AmbientLightComponent { Color = new Vector3(0.05f) });
        var sprite = new Sprite2dComponent { Region = new Vector4(0, 0, 1, 1), Size = Vector2.One, Pivot = new Vector2(0.5f), Color = Vector4.One, AlphaMode = AlphaMode.Opaque, AlphaCutoff = 0.5f };
        var label = new LabelComponent { FontSize = 32.0f };
        label.Color[0] = 1.0f; label.Color[1] = 1.0f; label.Color[2] = 1.0f; label.Color[3] = 1.0f;
        var body = Native.Forever(new Body2dComponent { GravityScale = 1.0f });
        var collider = Native.Forever(new Collider2dComponent { HalfExtents = new Vector2(0.5f), Radius = 0.5f, Density = 1.0f, Friction = 0.3f, Layer = 1, Mask = 0xFFFFFFFFu });
        var sound = Native.Forever(new SoundComponent { Volume = 1.0f, Pitch = 1.0f });

        Register(types, "ambient_light", ("ambient_light", (nint)ambient), ("transform", (nint)transform));
        Register(types, "body2d", ("body2d", (nint)body), ("transform2d", (nint)transform2d));
        Register(types, "camera", ("camera", (nint)camera), ("transform", (nint)transform));
        Register(types, "collider2d", ("collider2d", (nint)collider), ("transform2d", (nint)transform2d));
        Register(types, "label", ("label", (nint)Native.Forever(label)), ("transform", (nint)transform));
        Register(types, "sound", ("sound", (nint)sound), ("transform", (nint)transform));
        Register(types, "sprite2d", ("sprite2d", (nint)Native.Forever(sprite)), ("transform2d", (nint)transform2d));
        Register(types, "transform2d", ("transform2d", (nint)transform2d));
        Register(types, "transform", ("transform", (nint)transform));
    }

    static void Register(ke_node_types* types, string name, params (string Component, nint Initial)[] with)
    {
        var withs = new NodeWith[with.Length];
        for (var i = 0; i < with.Length; i++) withs[i] = new NodeWith { Name = Native.Forever(with[i].Component), Initial = (void*)with[i].Initial };
        var desc = new NodeTypeDesc { Name = Native.Forever(name), With = Native.Forever<NodeWith>(withs), WithCount = (uint)withs.Length };
        ComponentId type;
        Native.Check(name, types->register_type(types, &desc, &type));
    }
}

[StructLayout(LayoutKind.Sequential)]
struct Paddle
{
    public ActionRef MoveAction;
    public float Speed;
    public float HalfHeight;
}

[StructLayout(LayoutKind.Sequential)]
unsafe struct Ball
{
    public fixed sbyte HitSound[256];
    public float HitVolume;
    public fixed sbyte ScoreSound[256];
    public float ScoreVolume;
    public float InitialSpeed;
    public Vector2 LastVelocity;
    public bool AwaitingLaunch;
    public bool LaunchRequested;
    public int Launches;
}

[StructLayout(LayoutKind.Sequential)]
struct Scoreboard
{
    public int Left;
    public int Right;
}

[StructLayout(LayoutKind.Sequential)]
struct GoalScored
{
    public bool LeftScored;
}

[StructLayout(LayoutKind.Sequential)]
struct BallLaunched
{
    public bool Launched;
}

/// <summary>What Pong's node types are given: the engine parts they call and the ids they look up once.</summary>
[StructLayout(LayoutKind.Sequential)]
unsafe struct Game
{
    public ke_node_types* Types;
    public ComponentId SlotType;
    public ComponentId Slot;
    public ComponentId SoundType;
    public ComponentId Sound;
    public ComponentId Label;
    public ComponentId Body;
    public ComponentId Transform2d;
    public ComponentId GoalScored;
    public ComponentId BallLaunched;
    public ActionRef Launch;
    public ActionRef Quit;

    const float FieldHalfWidth = 8.0f;
    const float FieldHalfHeight = 4.5f;
    const float WallHalfThickness = 0.25f;
    const float GoalLineMargin = 0.5f;
    const float ServeSpread = 0.6f;
    const string MenuScene = "res://scenes/Menu.scene.toml";
    const string MainScene = "res://scenes/Main.scene.toml";
    const string LaunchHint = "Press Space to launch";

    static readonly Entity NoEntity = new(0);

    /// <summary>Registers Pong's events and node types and looks up the ids the game keeps.</summary>
    public static Game* Register(ke_node_types* types)
    {
        var game = Native.Forever(new Game { Types = types });

        var goalParams = Native.Component<GoalScored>("pong.goal_scored", []);
        var launchedParams = Native.Component<BallLaunched>("pong.ball_launched", []);
        Native.Check("goal scored", types->register_event(types, goalParams, &game->GoalScored));
        Native.Check("ball launched", types->register_event(types, launchedParams, &game->BallLaunched));

        game->SlotType = FindType(types, "scene_slot");
        game->Slot = FindComponent(types, "scene_slot");
        game->SoundType = FindType(types, "sound");
        game->Sound = FindComponent(types, "sound");
        game->Label = FindComponent(types, "label");
        game->Body = FindComponent(types, "body2d");
        game->Transform2d = FindComponent(types, "transform2d");
        Native.Write((sbyte*)Unsafe.AsPointer(ref game->Launch.Name), 32, "Launch");
        Native.Write((sbyte*)Unsafe.AsPointer(ref game->Quit.Name), 32, "Quit");

        Paddle probePaddle = default;
        Ball probeBall = default;
        Scoreboard probeScoreboard = default;
        var paddleFields = Native.Component<Paddle>("pong.paddle", [
            Native.Field("move_action", VariantType.String, (int)((byte*)&probePaddle.MoveAction - (byte*)&probePaddle), 32),
            Native.Field("speed", VariantType.Float, (int)((byte*)&probePaddle.Speed - (byte*)&probePaddle), sizeof(float)),
            Native.Field("half_height", VariantType.Float, (int)((byte*)&probePaddle.HalfHeight - (byte*)&probePaddle), sizeof(float)),
        ]);
        var ballFields = Native.Component<Ball>("pong.ball", [
            Native.Field("hit_sound", VariantType.String, (int)((byte*)probeBall.HitSound - (byte*)&probeBall), 256),
            Native.Field("hit_volume", VariantType.Float, (int)((byte*)&probeBall.HitVolume - (byte*)&probeBall), sizeof(float)),
            Native.Field("score_sound", VariantType.String, (int)((byte*)probeBall.ScoreSound - (byte*)&probeBall), 256),
            Native.Field("score_volume", VariantType.Float, (int)((byte*)&probeBall.ScoreVolume - (byte*)&probeBall), sizeof(float)),
            Native.Field("initial_speed", VariantType.Float, (int)((byte*)&probeBall.InitialSpeed - (byte*)&probeBall), sizeof(float)),
            Native.Field("awaiting_launch", VariantType.Bool, (int)((byte*)&probeBall.AwaitingLaunch - (byte*)&probeBall), sizeof(bool)),
        ]);
        var boardFields = Native.Component<Scoreboard>("pong.scoreboard", [
            Native.Field("left", VariantType.Int, (int)((byte*)&probeScoreboard.Left - (byte*)&probeScoreboard), sizeof(int)),
            Native.Field("right", VariantType.Int, (int)((byte*)&probeScoreboard.Right - (byte*)&probeScoreboard), sizeof(int)),
        ]);

        var bodyWith = Native.Forever<NodeWith>([
            new NodeWith { Name = Native.Forever("body2d"), Initial = Native.Forever(new Body2dComponent { GravityScale = 1.0f }) },
            new NodeWith { Name = Native.Forever("transform2d"), Initial = Native.Forever(new Transform2dComponent { Scale = Vector2.One }) },
        ]);
        var paddleInitial = Native.Forever(new Paddle { Speed = 7.0f, HalfHeight = 0.9f });
        var ballInitial = Native.Forever(new Ball { HitVolume = 1.0f, ScoreVolume = 1.0f, InitialSpeed = 6.0f, AwaitingLaunch = true });
        var boardHandlers = Native.Forever<NodeHandler>([
            new NodeHandler { Event = game->GoalScored, On = &ScoreboardOnGoal },
            new NodeHandler { Event = game->BallLaunched, On = &ScoreboardOnLaunch },
        ]);

        ReadOnlySpan<NodeTypeDesc> descs = [
            new() { Name = Native.Forever("pong.paddle"), Fields = paddleFields, Initial = paddleInitial, With = bodyWith, WithCount = 2, FixedUpdate = &PaddleFixedUpdate, UserData = game },
            new() { Name = Native.Forever("pong.ball"), Fields = ballFields, Initial = ballInitial, With = bodyWith, WithCount = 2, Update = &BallUpdate, FixedUpdate = &BallFixedUpdate, UserData = game },
            new() { Name = Native.Forever("pong.scoreboard"), Fields = boardFields, On = boardHandlers, OnCount = 2, UserData = game },
            new() { Name = Native.Forever("pong.menu_controller"), Update = &MenuUpdate, UserData = game },
        ];
        foreach (var desc in descs)
        {
            ComponentId type;
            var copy = desc;
            Native.Check(Native.Read(desc.Name), types->register_type(types, &copy, &type));
        }
        return game;
    }

    /// <summary>Records into <paramref name="commands"/> a scene slot at the root holding the scene file <paramref name="path"/>.</summary>
    public static NativeResult OpenSlot(Game* game, ke_ecs_commands* commands, string path)
    {
        var slot = new SceneSlotComponent();
        Native.Write((sbyte*)Unsafe.AsPointer(ref slot.Path), 256, path);
        var component = new NodeComponent { Component = game->Slot, Data = &slot };
        Entity node;
        var name = Native.Utf8("Scene");
        fixed (byte* n = name)
            return game->Types->spawn(game->Types, commands, game->SlotType, (sbyte*)n, NoEntity, &component, 1, &node);
    }

    /// <summary>Releases what <see cref="Register"/> allocated for the game itself.</summary>
    public static void Free(Game* game) => NativeMemory.AlignedFree(game);

    static ComponentId FindType(ke_node_types* types, string name)
    {
        ComponentId id;
        fixed (byte* n = Native.Utf8(name)) Native.Check(name, types->find_type(types, (sbyte*)n, &id));
        return id;
    }

    static ComponentId FindComponent(ke_node_types* types, string name)
    {
        ComponentId id;
        fixed (byte* n = Native.Utf8(name)) Native.Check(name, types->find_component(types, (sbyte*)n, &id));
        return id;
    }

    static LabelComponent* ChildLabel(ke_node_ctx* ctx, Game* game, string name)
    {
        Entity child;
        fixed (byte* n = Native.Utf8(name)) child = ctx->child(ctx, ctx->self, (sbyte*)n);
        return child == NoEntity ? null : (LabelComponent*)ctx->component(ctx, child, game->Label);
    }

    static void LabelText(ke_node_ctx* ctx, Game* game, string name, string text)
    {
        var label = ChildLabel(ctx, game, name);
        if (label != null) Native.Write((sbyte*)Unsafe.AsPointer(ref label->Text), 256, text);
    }

    static NativeResult ChangeScene(ke_node_ctx* ctx, Game* game, string path)
    {
        var holder = ctx->ancestor(ctx, ctx->self, game->Slot);
        var slot = holder == NoEntity ? null : (SceneSlotComponent*)ctx->component(ctx, holder, game->Slot);
        if (slot == null) return NativeResult.NotFound;
        Native.Write((sbyte*)Unsafe.AsPointer(ref slot->Path), 256, path);
        return NativeResult.Ok;
    }

    static NativeResult Play(ke_node_ctx* ctx, Game* game, sbyte* path, float volume)
    {
        var sound = new SoundComponent { Volume = volume, Pitch = 1.0f, Playing = true, Release = SoundRelease.WhenDone };
        Native.Write((sbyte*)Unsafe.AsPointer(ref sound.Path), 256, Native.Read(path));
        var component = new NodeComponent { Component = game->Sound, Data = &sound };
        Entity node;
        fixed (byte* n = "Sound\0"u8)
            return ctx->spawn(ctx, game->SoundType, (sbyte*)n, ctx->self, &component, 1, &node);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult PaddleFixedUpdate(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
        {
            var paddle = (Paddle*)ctx->fields;
            var body = (Body2dComponent*)ctx->get(ctx, game->Body);
            var pose = (Transform2dComponent*)ctx->get(ctx, game->Transform2d);
            var vy = ctx->axis(ctx, &paddle->MoveAction) * paddle->Speed;
            var maxY = FieldHalfHeight - WallHalfThickness - paddle->HalfHeight;
            if (vy > 0 && pose->Position.Y >= maxY) vy = 0;
            if (vy < 0 && pose->Position.Y <= -maxY) vy = 0;
            body->Velocity = new Vector2(0.0f, vy);
        }
        return NativeResult.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult BallUpdate(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
        {
            var ball = (Ball*)ctx->fields;
            if (ctx->pressed(ctx, &game->Quit)) return ChangeScene(ctx, game, MenuScene);
            if (ctx->pressed(ctx, &game->Launch) && ball->AwaitingLaunch) ball->LaunchRequested = true;
        }
        return NativeResult.Ok;
    }

    static NativeResult Serve(ke_node_ctx* ctx, Game* game, Ball* ball, Body2dComponent* body)
    {
        ball->AwaitingLaunch = false;
        ball->LaunchRequested = false;
        var launched = new BallLaunched { Launched = true };
        var raised = ctx->raise(ctx, game->BallLaunched, &launched, (nuint)sizeof(BallLaunched));
        if (raised != NativeResult.Ok) return raised;
        var dirX = ball->Launches % 2 == 0 ? 1.0f : -1.0f;
        ball->Launches++;
        var dirY = (Random.Shared.NextSingle() - 0.5f) * ServeSpread;
        var direction = Vector2.Normalize(new Vector2(dirX, dirY));
        body->Velocity = direction * ball->InitialSpeed;
        ball->LastVelocity = body->Velocity;
        return NativeResult.Ok;
    }

    static NativeResult Score(ke_node_ctx* ctx, Game* game, Ball* ball, Body2dComponent* body, Transform2dComponent* pose, bool leftScored)
    {
        var goal = new GoalScored { LeftScored = leftScored };
        var raised = ctx->raise(ctx, game->GoalScored, &goal, (nuint)sizeof(GoalScored));
        if (raised != NativeResult.Ok) return raised;
        pose->Position = Vector2.Zero;
        body->Velocity = Vector2.Zero;
        ball->LastVelocity = Vector2.Zero;
        ball->AwaitingLaunch = true;
        return Play(ctx, game, ball->ScoreSound, ball->ScoreVolume);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult BallFixedUpdate(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
        {
            var ball = (Ball*)ctx->fields;
            var body = (Body2dComponent*)ctx->get(ctx, game->Body);
            var pose = (Transform2dComponent*)ctx->get(ctx, game->Transform2d);
            if (ball->LaunchRequested)
            {
                var served = Serve(ctx, game, ball, body);
                if (served != NativeResult.Ok) return served;
            }
            if (ball->AwaitingLaunch) continue;

            var bounced = ball->LastVelocity.X != 0 && (body->Velocity.X > 0) != (ball->LastVelocity.X > 0);
            ball->LastVelocity = body->Velocity;
            if (bounced)
            {
                var played = Play(ctx, game, ball->HitSound, ball->HitVolume);
                if (played != NativeResult.Ok) return played;
            }

            var leftScored = pose->Position.X > FieldHalfWidth + GoalLineMargin;
            if (leftScored || pose->Position.X < -FieldHalfWidth - GoalLineMargin)
            {
                var scored = Score(ctx, game, ball, body, pose, leftScored);
                if (scored != NativeResult.Ok) return scored;
            }
        }
        return NativeResult.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult ScoreboardOnGoal(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
        {
            var board = (Scoreboard*)ctx->fields;
            var goal = (GoalScored*)ctx->@event;
            if (goal->LeftScored) board->Left++;
            else board->Right++;
            LabelText(ctx, game, "ScoreLeft", board->Left.ToString());
            LabelText(ctx, game, "ScoreRight", board->Right.ToString());
            LabelText(ctx, game, "ScoreHint", LaunchHint);
        }
        return NativeResult.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult ScoreboardOnLaunch(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
            LabelText(ctx, game, "ScoreHint", "");
        return NativeResult.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static NativeResult MenuUpdate(ke_node_ctx* ctx, void* userData)
    {
        var game = (Game*)userData;
        while (ctx->next(ctx))
        {
            if (ctx->pressed(ctx, &game->Launch)) return ChangeScene(ctx, game, MainScene);
            if (ctx->pressed(ctx, &game->Quit)) ctx->exit(ctx);
        }
        return NativeResult.Ok;
    }
}
