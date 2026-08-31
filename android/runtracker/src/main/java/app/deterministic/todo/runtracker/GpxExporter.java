package app.deterministic.todo.runtracker;

import java.time.Instant;
import java.util.List;
import java.util.Locale;

public final class GpxExporter {
    private GpxExporter() {}

    public static String export(RunSession session, List<TrackPoint> points) {
        StringBuilder out = new StringBuilder();
        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
            .append("<gpx version=\"1.1\" creator=\"Deterministic Todo Run Tracker\" ")
            .append("xmlns=\"http://www.topografix.com/GPX/1/1\" ")
            .append("xmlns:dt=\"https://deterministic-todo.app/gpx/1\">\n")
            .append("<metadata><time>").append(Instant.ofEpochMilli(session.startedAtMillis))
            .append("</time></metadata>\n<trk><name>")
            .append("walk".equals(session.activityType) ? "Camminata " : "Corsa ")
            .append(Instant.ofEpochMilli(session.startedAtMillis)).append("</name><trkseg>\n");
        for (TrackPoint point : points) {
            if (!point.accepted) continue;
            out.append(String.format(Locale.ROOT,
                "<trkpt lat=\"%.7f\" lon=\"%.7f\"><time>%s</time><extensions><dt:accuracy_m>%.1f</dt:accuracy_m><dt:distance_total_m>%.2f</dt:distance_total_m></extensions></trkpt>\n",
                point.latitude, point.longitude, Instant.ofEpochMilli(point.timestampMillis),
                point.accuracyMeters, point.accumulatedDistanceMeters));
        }
        out.append("</trkseg></trk>\n");
        for (TrackPoint point : points) {
            if (point.accepted) continue;
            out.append(String.format(Locale.ROOT,
                "<wpt lat=\"%.7f\" lon=\"%.7f\"><time>%s</time><type>rejected:%s</type><extensions><dt:accuracy_m>%.1f</dt:accuracy_m><dt:distance_total_m>%.2f</dt:distance_total_m></extensions></wpt>\n",
                point.latitude, point.longitude, Instant.ofEpochMilli(point.timestampMillis),
                xml(point.rejectionReason == null ? "unknown" : point.rejectionReason),
                point.accuracyMeters, point.accumulatedDistanceMeters));
        }
        return out.append("</gpx>\n").toString();
    }

    private static String xml(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
