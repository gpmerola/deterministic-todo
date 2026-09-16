package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.util.List;
import org.junit.Test;

public class StrideCalibratorTest {
    @Test public void acceptsOnlyLongPlausibleSamples() {
        assertTrue(StrideCalibrator.eligible("walking", 1200, 1600));
        assertTrue(StrideCalibrator.eligible("running", 15000, 15000));
        assertFalse(StrideCalibrator.eligible("walking", 500, 700));
        assertFalse(StrideCalibrator.eligible("running", 15000, 5000));
    }

    @Test public void medianRejectsSingleOutlier() {
        assertEquals(1.01, StrideCalibrator.median(List.of(1.00, 1.01, 1.50)), 0.001);
    }
}
