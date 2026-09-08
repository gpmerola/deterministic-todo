package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import java.util.List;
import org.junit.Test;

public class GpxExporterTest {
    @Test public void exportsAcceptedTrackAndRejectedDiagnostics() {
        RunSession session = new RunSession(); session.startedAtMillis = 1_700_000_000_000L;
        TrackPoint accepted = point(true, null, 51.5, -0.12);
        TrackPoint rejected = point(false, "poor_accuracy", 51.6, -0.13);
        String gpx = GpxExporter.export(session, List.of(accepted, rejected));
        assertTrue(gpx.contains("<trkpt lat=\"51.5000000\""));
        assertTrue(gpx.contains("<wpt lat=\"51.6000000\""));
        assertTrue(gpx.contains("rejected:poor_accuracy"));
        assertTrue(gpx.contains("xmlns:dt=\"https://deterministic-todo.app/gpx/1\""));
        assertTrue(gpx.contains("<dt:accuracy_m>5.0</dt:accuracy_m>"));
        assertFalse(gpx.contains("<hdop>"));
    }

    private static TrackPoint point(boolean accepted, String reason, double lat, double lon) {
        TrackPoint point = new TrackPoint(); point.accepted = accepted; point.rejectionReason = reason;
        point.latitude = lat; point.longitude = lon; point.timestampMillis = 1_700_000_001_000L; point.accuracyMeters = 5;
        return point;
    }
}
