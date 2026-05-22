namespace KernelEngine.Framework.Animation;

/// <summary>Base for time-driven scalar animations. Call <see cref="Update"/> each frame with the delta time.</summary>
public abstract class AnimationBase(float from, float to)
{
    public float From { get; protected set; } = from;
    public float To { get; protected set; } = to;
    public float Current { get; protected set; } = from;
    public bool IsCompleted { get; protected set; }

    protected float ElapsedTime { get; set; }
    protected float Weight { get; set; }

    public abstract void Update(float deltaTime);

    public void Reset()
    {
        ElapsedTime = 0f;
        Current = From;
        Weight = 0f;
        IsCompleted = false;
    }

    protected static float Interpolate(float from, float to, float weight, EasingFunction? easingFunction = null)
    {
        easingFunction ??= Easing.Linear;
        return from + (to - from) * easingFunction(weight);
    }
}
