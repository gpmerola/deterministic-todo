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
            .append("xmlns=\"http://www.topografix.com/GPX/1/1\">\n")
            .append("<metadata><time>").append(Instant.ofEpochMilli(session.startedAtMillis))
            .append("</time></metadata>\n<trk><name>Corsa ")
            .append(Instant.ofEpochMilli(session.startedAtMillis)).append("</name><trkseg>\n");
        for (TrackPoint point : points) {
            if (!point.accepted) continue;
            out.append(String.format(Locale.ROOT,
                "<trkpt lat=\"%.7f\" lon=\"%.7f\"><time>%s</time><hdop>%.1f</hdop></trkpt>\n",
                point.latitude, point.longitude, Instant.ofEpochMilli(point.timestampMillis),
                point.accuracyMeters));
        }
        out.append("</trkseg></trk>\n");
        for (TrackPoint point : points) {
            if (point.accepted) continue;
            out.append(String.format(Locale.ROOT,
                "<wpt lat=\"%.7f\" lon=\"%.7f\"><time>%s</time><type>rejected:%s</type></wpt>\n",
                point.latitude, point.longitude, Instant.ofEpochMilli(point.timestampMillis),
                xml(point.rejectionReason == null ? "unknown" : point.rejectionReason)));
        }
        return out.append("</gpx>\n").toString();
    }

    private static String xml(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");
    }
}
