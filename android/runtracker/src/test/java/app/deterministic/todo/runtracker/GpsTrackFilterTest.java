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
