package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

public final class HeartRateMeasurementParserTest {
    @Test public void parsesEightAndSixteenBitMeasurements() {
        assertEquals(Integer.valueOf(72), HeartRateMeasurementParser.parse(
            new byte[] {0x00, 72}));
        assertEquals(Integer.valueOf(180), HeartRateMeasurementParser.parse(
            new byte[] {0x01, (byte) 180, 0x00}));
    }

    @Test public void rejectsMalformedOrImplausibleMeasurements() {
        assertNull(HeartRateMeasurementParser.parse(null));
        assertNull(HeartRateMeasurementParser.parse(new byte[] {0x01, 90}));
        assertNull(HeartRateMeasurementParser.parse(new byte[] {0x00, 10}));
    }
}
