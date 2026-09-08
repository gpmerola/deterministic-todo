package app.deterministic.todo.runtracker;

import android.animation.ValueAnimator;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.view.View;
import android.view.animation.OvershootInterpolator;

import java.util.Locale;

/** Compact native counterpart of the global Flutter step ring. */
final class DailyStepGoalView extends View {
    private final Paint track = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint progressPaint = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final Paint text = new Paint(Paint.ANTI_ALIAS_FLAG);
    private long steps;
    private int goal = DailyStepGoalPolicy.DEFAULT_GOAL;
    private float animatedProgress;
    private float pulse = 1f;
    private boolean celebrated;

    DailyStepGoalView(Context context) {
        super(context);
        track.setColor(Color.argb(35, 80, 80, 80));
        track.setStyle(Paint.Style.STROKE);
        track.setStrokeWidth(dp(5));
        progressPaint.setStyle(Paint.Style.STROKE);
        progressPaint.setStrokeCap(Paint.Cap.ROUND);
        progressPaint.setStrokeWidth(dp(5));
        text.setColor(Color.rgb(75, 75, 82));
        text.setTextAlign(Paint.Align.CENTER);
        text.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        text.setTextSize(dp(12));
        setContentDescription("Obiettivo passi giornaliero");
    }

    void setProgress(long steps, int goal) {
        this.steps = Math.max(0, steps);
        this.goal = DailyStepGoalPolicy.normalize(goal);
        float target = DailyStepGoalPolicy.progress(steps, this.goal);
        ValueAnimator animator = ValueAnimator.ofFloat(animatedProgress, target);
        animator.setDuration(450);
        animator.addUpdateListener(value -> {
            animatedProgress = (float) value.getAnimatedValue();
            invalidate();
        });
        animator.start();
        if (target >= 1f && !celebrated) {
            celebrated = true;
            ValueAnimator pop = ValueAnimator.ofFloat(1f, 1.18f, 1f);
            pop.setDuration(800);
            pop.setInterpolator(new OvershootInterpolator());
            pop.addUpdateListener(value -> {
                pulse = (float) value.getAnimatedValue();
                invalidate();
            });
            pop.start();
        } else if (target < 1f) celebrated = false;
        setContentDescription(String.format(Locale.ITALY,
            "%,d passi su %,d", this.steps, this.goal));
    }

    @Override protected void onDraw(Canvas canvas) {
        super.onDraw(canvas);
        float cx = getWidth() / 2f;
        float cy = getHeight() / 2f;
        float radius = Math.min(cx, cy) - dp(5);
        canvas.save();
        canvas.scale(pulse, pulse, cx, cy);
        canvas.drawCircle(cx, cy, radius, track);
        progressPaint.setColor(animatedProgress >= 1f
            ? Color.rgb(245, 166, 35) : Color.rgb(219, 64, 53));
        RectF arc = new RectF(cx - radius, cy - radius, cx + radius, cy + radius);
        canvas.drawArc(arc, -90, animatedProgress * 360f, false, progressPaint);
        String value = steps >= 1_000
            ? String.format(Locale.ROOT, "%.1fk", steps / 1_000f)
            : Long.toString(steps);
        Paint.FontMetrics metrics = text.getFontMetrics();
        canvas.drawText(animatedProgress >= 1f ? "★" : value, cx,
            cy - (metrics.ascent + metrics.descent) / 2f, text);
        canvas.restore();
    }

    private float dp(int value) {
        return value * getResources().getDisplayMetrics().density;
    }
}
