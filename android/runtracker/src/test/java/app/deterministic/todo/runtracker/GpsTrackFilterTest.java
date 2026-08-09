package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class GpsTrackFilterTest {
    @Test public void rejectsPoorAccuracyAndKeepsReason() {
        GpsTrackFilter filter = new GpsTrackFilter();
        GpsTrackFilter.Decision result = filter.evaluate(sample(0, 51.5000, -0.1200, 80));
        assertFalse(result.accepted());
        assertEquals("poor_accuracy", result.reason());
        assertEquals(0, result.totalMeters(), 0.001);
    }

    @Test public void stationaryNoiseDoesNotAccumulateDistance() {
        GpsTrackFilter filter = new GpsTrackFilter();
        assertTrue(filter.evaluate(sample(0, 51.500000, -0.120000, 10)).accepted());
        GpsTrackFilter.Decision result = filter.evaluate(sample(5_000, 51.500005, -0.120005, 10));
        assertFalse(result.accepted());
        assertEquals("stationary_accuracy_noise", result.reason());
        assertEquals(0, filter.totalMeters(), 0.001);
    }

    @Test public void rejectsImpossibleRunningJump() {
        GpsTrackFilter filter = new GpsTrackFilter();
        filter.evaluate(sample(0, 51.5000, -0.1200, 5));
        GpsTrackFilter.Decision result = filter.evaluate(sample(1_000, 51.5010, -0.1200, 5));
        assertFalse(result.accepted());
        assertEquals("implausible_speed_jump", result.reason());
    }

    @Test public void walkingProfileRejectsJumpAcceptedByRunningProfile() {
        GpsTrackFilter walking = new GpsTrackFilter(GpsTrackFilter.MAX_WALKING_SPEED_MPS);
        GpsTrackFilter running = new GpsTrackFilter(GpsTrackFilter.MAX_RUNNING_SPEED_MPS);
        GpsTrackFilter.Sample start = sample(0, 51.5000, -0.1200, 6);
        GpsTrackFilter.Sample jump = sample(10_000, 51.5009, -0.1200, 6);
        walking.evaluate(start);
        running.evaluate(start);

        assertFalse(walking.evaluate(jump).accepted());
        assertTrue(running.evaluate(jump).accepted());
    }

    @Test public void confirmedGpsDiscontinuityReanchorsWithoutAddingJump() {
        GpsTrackFilter walking = new GpsTrackFilter(GpsTrackFilter.MAX_WALKING_SPEED_MPS);
        walking.evaluate(sample(0, 51.5000, -0.1200, 6));
        assertEquals("implausible_speed_jump",
            walking.evaluate(sample(10_000, 51.5009, -0.1200, 6)).reason());

        GpsTrackFilter.Decision reanchor = walking.evaluate(sample(12_000, 51.50091, -0.1200, 6));
        assertFalse(reanchor.accepted());
        assertEquals("gps_discontinuity_reanchor", reanchor.reason());
        assertEquals(0, reanchor.totalMeters(), 0.001);

        GpsTrackFilter.Decision resumed = walking.evaluate(sample(17_000, 51.50096, -0.1200, 6));
        assertTrue(resumed.accepted());
        assertTrue(resumed.totalMeters() > 5 && resumed.totalMeters() < 6);
    }

    @Test public void acceptsPlausibleMovementAndAccumulates() {
        GpsTrackFilter filter = new GpsTrackFilter();
        filter.evaluate(sample(0, 51.5000, -0.1200, 5));
        GpsTrackFilter.Decision result = filter.evaluate(sample(10_000, 51.5005, -0.1200, 5));
        assertTrue(result.accepted());
        assertTrue(result.totalMeters() > 50 && result.totalMeters() < 60);
    }

    @Test public void rejectsShortSharpGpsZigzag() {
        GpsTrackFilter filter = new GpsTrackFilter();
        filter.evaluate(sample(0, 51.5000, -0.1200, 5));
        assertTrue(filter.evaluate(sample(5_000, 51.5000, -0.1198, 5)).accepted());
        GpsTrackFilter.Decision result = filter.evaluate(sample(10_000, 51.5000, -0.11995, 5));
        assertFalse(result.accepted());
        assertEquals("gps_zigzag", result.reason());
    }

    @Test public void rejectsNonMonotonicTimestamp() {
        GpsTrackFilter filter = new GpsTrackFilter();
        filter.evaluate(sample(5_000, 51.5000, -0.1200, 5));
        assertEquals("timestamp_non_monotonic", filter.evaluate(sample(5_000, 51.5001, -0.1200, 5)).reason());
    }

    private static GpsTrackFilter.Sample sample(long time, double lat, double lon, float accuracy) {
        return new GpsTrackFilter.Sample(time, lat, lon, accuracy);
    }
}
