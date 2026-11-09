using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using KernelEngine.Audio.Native;
using KernelEngine.Common;
using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework;
using KernelEngine.Framework.Nodes;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Physics;
using KernelEngine.Render;

namespace Pong;

/// <summary>The bytes of a value, as a node type's initial value or a spawned component is given.</summary>
static class Bytes
{
    /// <summary>A copy of the bytes of <paramref name="value"/>.</summary>
    public static byte[] Of<T>(T value) where T : unmanaged => MemoryMarshal.AsBytes(new[] { value }.AsSpan()).ToArray();
}

struct Paddle
{
    public ActionRef MoveAction;
    public float Speed;
    public float HalfHeight;
}

[InlineArray(256)]
struct SoundPath
{
    byte _first;
}

struct Ball
{
    public SoundPath HitSound;
    public float HitVolume;
    public SoundPath ScoreSound;
    public float ScoreVolume;
    public float InitialSpeed;
    public Vector2 LastVelocity;
    public bool AwaitingLaunch;
    public bool LaunchRequested;
    public int Launches;
}

struct Scoreboard
{
    public int Left;
    public int Right;
}

struct GoalScored
{
    public bool LeftScored;
}

struct BallLaunched
{
    public bool Launched;
}

/// <summary>The layout of a component struct, as its node type is registered with.</summary>
static class Layout
{
    struct Probe<T> where T : unmanaged
    {
        public byte Head;
        public T Value;
    }

    /// <summary>The alignment the runtime gives <typeparamref name="T"/>.</summary>
    public static nuint AlignOf<T>() where T : unmanaged
    {
        var probe = new Probe<T> { Head = 1 };
        return (nuint)Unsafe.ByteOffset(ref probe.Head, ref Unsafe.As<T, byte>(ref probe.Value));
    }

    /// <summary>The field table entry of <paramref name="field"/>, a member of <paramref name="value"/>.</summary>
    public static ComponentField Field<T, TField>(string name, VariantType type, ref T value, ref TField field, int size) where T : unmanaged => new()
    {
        Name = name,
        Type = type,
        Offset = (uint)Unsafe.ByteOffset(ref Unsafe.As<T, byte>(ref value), ref Unsafe.As<TField, byte>(ref field)),
        Size = (uint)size,
    };
}

/// <summary>Pong's node types, and the ids they look up once.</summary>
sealed class Game
{
    const float FieldHalfWidth = 8.0f;
    const float FieldHalfHeight = 4.5f;
    const float WallHalfThickness = 0.25f;
    const float GoalLineMargin = 0.5f;
    const float ServeSpread = 0.6f;
    const string MenuScene = "res://scenes/Menu.scene.toml";
    const string MainScene = "res://scenes/Main.scene.toml";
    const string LaunchHint = "Press Space to launch";

    readonly INodeTypes _types;
    readonly ComponentId _slotType;
    readonly ComponentId _slot;
    readonly ComponentId _soundType;
    readonly ComponentId _sound;
    readonly ComponentId _label;
    readonly ComponentId _body;
    readonly ComponentId _transform2d;
    readonly ComponentId _goalScored;
    readonly ComponentId _ballLaunched;
    ActionRef _launch;
    ActionRef _quit;

    /// <summary>Registers Pong's events and node types and looks up the ids the game keeps.</summary>
    public Game(INodeTypes types)
    {
        _types = types;
        _goalScored = types.RegisterEvent("pong.goal_scored", (nuint)Unsafe.SizeOf<GoalScored>(), 1, []);
        _ballLaunched = types.RegisterEvent("pong.ball_launched", (nuint)Unsafe.SizeOf<BallLaunched>(), 1, []);
        _slotType = types.FindType("scene_slot");
        _slot = types.FindComponent("scene_slot");
        _soundType = types.FindType("sound");
        _sound = types.FindComponent("sound");
        _label = types.FindComponent("label");
        _body = types.FindComponent("body2d");
        _transform2d = types.FindComponent("transform2d");
        _launch.NameText = "Launch";
        _quit.NameText = "Quit";

        var bodyWith = EngineNodeTypes.Body2dNodeWith;

        var paddle = new Paddle();
        types.RegisterType("pong.paddle", (nuint)Unsafe.SizeOf<Paddle>(), Layout.AlignOf<Paddle>(),
            [
                Layout.Field("move_action", VariantType.String, ref paddle, ref paddle.MoveAction, 32),
                Layout.Field("speed", VariantType.Float, ref paddle, ref paddle.Speed, sizeof(float)),
                Layout.Field("half_height", VariantType.Float, ref paddle, ref paddle.HalfHeight, sizeof(float)),
            ],
            Bytes.Of(new Paddle { Speed = 7.0f, HalfHeight = 0.9f }), bodyWith, fixedUpdate: PaddleFixedUpdate);

        var ball = new Ball();
        types.RegisterType("pong.ball", (nuint)Unsafe.SizeOf<Ball>(), Layout.AlignOf<Ball>(),
            [
                Layout.Field("hit_sound", VariantType.String, ref ball, ref ball.HitSound, 256),
                Layout.Field("hit_volume", VariantType.Float, ref ball, ref ball.HitVolume, sizeof(float)),
                Layout.Field("score_sound", VariantType.String, ref ball, ref ball.ScoreSound, 256),
                Layout.Field("score_volume", VariantType.Float, ref ball, ref ball.ScoreVolume, sizeof(float)),
                Layout.Field("initial_speed", VariantType.Float, ref ball, ref ball.InitialSpeed, sizeof(float)),
                Layout.Field("awaiting_launch", VariantType.Bool, ref ball, ref ball.AwaitingLaunch, sizeof(bool)),
            ],
            Bytes.Of(new Ball { HitVolume = 1.0f, ScoreVolume = 1.0f, InitialSpeed = 6.0f, AwaitingLaunch = true }), bodyWith,
            update: BallUpdate, fixedUpdate: BallFixedUpdate);

        var board = new Scoreboard();
        types.RegisterType("pong.scoreboard", (nuint)Unsafe.SizeOf<Scoreboard>(), Layout.AlignOf<Scoreboard>(),
            [
                Layout.Field("left", VariantType.Int, ref board, ref board.Left, sizeof(int)),
                Layout.Field("right", VariantType.Int, ref board, ref board.Right, sizeof(int)),
            ],
            events: [_goalScored, _ballLaunched], on: ScoreboardOn);

        types.RegisterType("pong.menu_controller", update: MenuUpdate);
    }

    /// <summary>Records into <paramref name="commands"/> a scene slot at the root holding the scene file <paramref name="path"/>.</summary>
    public void OpenSlot(INativeEcsCommands commands, string path)
    {
        var slot = new SceneSlotComponent();
        slot.PathText = path;
        _types.Spawn(commands, _slotType, "Scene", default, [new() { Component = _slot, Data = Bytes.Of(slot) }]);
    }

    void LabelText(INodeCtx ctx, string name, string text)
    {
        var child = ctx.Child(ctx.Self, name);
        if (child == default) return;
        ctx.Component<LabelComponent>(child, _label).TextText = text;
    }

    void ChangeScene(INodeCtx ctx, string path)
    {
        var holder = ctx.Ancestor(ctx.Self, _slot);
        if (holder == default) throw new InvalidOperationException("no scene slot holds this node");
        ctx.Component<SceneSlotComponent>(holder, _slot).PathText = path;
    }

    void Play(INodeCtx ctx, ReadOnlySpan<byte> path, float volume)
    {
        var sound = new SoundComponent { Volume = volume, Pitch = 1.0f, Playing = true, Release = SoundRelease.WhenDone };
        var end = path.IndexOf((byte)0);
        sound.PathText = System.Text.Encoding.UTF8.GetString(end < 0 ? path : path[..end]);
        ctx.Spawn(_soundType, "Sound", ctx.Self, [new() { Component = _sound, Data = Bytes.Of(sound) }]);
    }

    void PaddleFixedUpdate(INodeCtx ctx)
    {
        while (ctx.Next())
        {
            ref var paddle = ref ctx.Fields<Paddle>();
            ref var body = ref ctx.Get<Body2dComponent>(_body);
            ref var pose = ref ctx.Get<Transform2dComponent>(_transform2d);
            var vy = ctx.Axis(ref paddle.MoveAction) * paddle.Speed;
            var maxY = FieldHalfHeight - WallHalfThickness - paddle.HalfHeight;
            if (vy > 0 && pose.Position.Y >= maxY) vy = 0;
            if (vy < 0 && pose.Position.Y <= -maxY) vy = 0;
            body.Velocity = new Vector2(0.0f, vy);
        }
    }

    void BallUpdate(INodeCtx ctx)
    {
        while (ctx.Next())
        {
            ref var ball = ref ctx.Fields<Ball>();
            if (ctx.Pressed(ref _quit))
            {
                ChangeScene(ctx, MenuScene);
                return;
            }
            if (ctx.Pressed(ref _launch) && ball.AwaitingLaunch) ball.LaunchRequested = true;
        }
    }

    void Serve(INodeCtx ctx, ref Ball ball, ref Body2dComponent body)
    {
        ball.AwaitingLaunch = false;
        ball.LaunchRequested = false;
        ctx.Raise(_ballLaunched, new BallLaunched { Launched = true });
        var dirX = ball.Launches % 2 == 0 ? 1.0f : -1.0f;
        ball.Launches++;
        var dirY = (Random.Shared.NextSingle() - 0.5f) * ServeSpread;
        body.Velocity = Vector2.Normalize(new Vector2(dirX, dirY)) * ball.InitialSpeed;
        ball.LastVelocity = body.Velocity;
    }

    void BallFixedUpdate(INodeCtx ctx)
    {
        while (ctx.Next())
        {
            ref var ball = ref ctx.Fields<Ball>();
            ref var body = ref ctx.Get<Body2dComponent>(_body);
            ref var pose = ref ctx.Get<Transform2dComponent>(_transform2d);
            if (ball.LaunchRequested) Serve(ctx, ref ball, ref body);
            if (ball.AwaitingLaunch) continue;

            var bounced = ball.LastVelocity.X != 0 && (body.Velocity.X > 0) != (ball.LastVelocity.X > 0);
            ball.LastVelocity = body.Velocity;
            if (bounced) Play(ctx, ball.HitSound, ball.HitVolume);

            var leftScored = pose.Position.X > FieldHalfWidth + GoalLineMargin;
            if (!leftScored && pose.Position.X >= -FieldHalfWidth - GoalLineMargin) continue;
            ctx.Raise(_goalScored, new GoalScored { LeftScored = leftScored });
            pose.Position = Vector2.Zero;
            body.Velocity = Vector2.Zero;
            ball.LastVelocity = Vector2.Zero;
            ball.AwaitingLaunch = true;
            Play(ctx, ball.ScoreSound, ball.ScoreVolume);
        }
    }

    void ScoreboardOn(INodeCtx ctx)
    {
        while (ctx.Next())
        {
            if (ctx.EventType == _ballLaunched)
            {
                LabelText(ctx, "ScoreHint", "");
                continue;
            }
            ref var board = ref ctx.Fields<Scoreboard>();
            if (ctx.Event<GoalScored>().LeftScored) board.Left++;
            else board.Right++;
            LabelText(ctx, "ScoreLeft", board.Left.ToString());
            LabelText(ctx, "ScoreRight", board.Right.ToString());
            LabelText(ctx, "ScoreHint", LaunchHint);
        }
    }

    void MenuUpdate(INodeCtx ctx)
    {
        while (ctx.Next())
        {
            if (ctx.Pressed(ref _launch))
            {
                ChangeScene(ctx, MainScene);
                return;
            }
            if (ctx.Pressed(ref _quit)) ctx.Exit();
        }
    }
}
