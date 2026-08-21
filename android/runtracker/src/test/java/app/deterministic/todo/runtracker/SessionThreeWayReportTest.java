package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import java.util.List;
import org.json.JSONObject;
import org.junit.Test;

public class SessionThreeWayReportTest {
    @Test public void alignsSharedMetricsAndPreservesBipHeartRate() throws Exception {
        RunSession session = new RunSession();
        session.id = 7; session.activityType = "run"; session.startedAtMillis = 1_000;
        session.endedAtMillis = 121_000L; session.distanceMeters = 210;
        DirectStepTimeline phone = new DirectStepTimeline();
        phone.add(1_000, 0, "active"); phone.add(31_000, 50, "active");
        phone.add(91_000, 130, "active");
        TrackPoint point = new TrackPoint(); point.timestampMillis = 31_000;
        point.accumulatedDistanceMeters = 210; point.accepted = true;
        BipUActivitySample first = bip(1_000, 48, 150);
        BipUActivitySample second = bip(61_000, 70, 155);
        SessionThreeWayReport.FitSnapshot fit =
            new SessionThreeWayReport.FitSnapshot(125L, 205.0, 20.0, 130_000, "success");

        JSONObject report = SessionThreeWayReport.build(session, List.of(point), phone,
            List.of(first, second), fit, 140_000);

        assertEquals("movement_session_three_way", report.getString("kind"));
        assertEquals(130, report.getJSONObject("totals").getJSONObject("todo_test").getLong("steps"));
        assertEquals(118, report.getJSONObject("totals").getJSONObject("bip_u").getLong("steps"));
        assertEquals(152.5, report.getJSONObject("totals").getJSONObject("bip_u")
            .getDouble("heart_rate_mean_bpm"), 0.001);
        assertTrue(report.getJSONObject("comparisons").getJSONObject("steps")
            .getJSONObject("bip_vs_fit").getBoolean("available"));
        assertEquals(2, report.getJSONArray("timeline").length());
        assertEquals(155, report.getJSONArray("bip_u_native_samples").getJSONObject(1)
            .getInt("heart_rate_bpm"));
    }

    private static BipUActivitySample bip(long time, int steps, int heart) {
        BipUActivitySample sample = new BipUActivitySample();
        sample.timestampMillis = time; sample.steps = steps; sample.heartRate = heart;
        return sample;
    }
}
