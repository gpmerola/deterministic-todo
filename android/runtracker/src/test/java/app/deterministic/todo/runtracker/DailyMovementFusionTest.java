package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import org.junit.Test;

public final class DailyMovementFusionTest {
    @Test public void overlappingSourcesAreNeverSummed() {
        DailyMovementFusion.Result result = DailyMovementFusion.combine(4200, 3900);
        assertEquals(4200, result.steps());
        assertEquals("phone_step_counter", result.source());
    }

    @Test public void watchCanCoverAPhoneGapWithoutAddition() {
        DailyMovementFusion.Result result = DailyMovementFusion.combine(1200, 3100);
        assertEquals(3100, result.steps());
        assertEquals("bip_u_max", result.source());
    }

    @Test public void negativeInputsAreClamped() {
        assertEquals(0, DailyMovementFusion.combine(-4, -2).steps());
    }
}
