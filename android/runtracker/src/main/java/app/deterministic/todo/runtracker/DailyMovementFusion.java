package app.deterministic.todo.runtracker;

/** Conservative fusion: overlapping phone and watch totals are never summed. */
public final class DailyMovementFusion {
    private DailyMovementFusion() {}

    public record Result(long steps, String source) {}

    public static Result combine(long phoneSteps, long bipSteps) {
        long phone = Math.max(0, phoneSteps);
        long bip = Math.max(0, bipSteps);
        if (bip > phone) return new Result(bip, "bip_u_max");
        return new Result(phone, "phone_step_counter");
    }
}
