package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;

import org.junit.Test;

public class DriveComparisonFingerprintTest {
    @Test public void identicalFitReadsShareOneImmutableSidecarIdentity() {
        HealthConnectGateway.GoogleFitComparison first = comparison(1000L, 750.0, 995L, 742.5, 41.0);
        HealthConnectGateway.GoogleFitComparison retry = comparison(1000L, 750.0, 995L, 742.5, 41.0);
        assertEquals(DriveTestExportManager.comparisonFingerprint(first),
            DriveTestExportManager.comparisonFingerprint(retry));
    }

    @Test public void changedFitValuesCreateANewSnapshotIdentity() {
        HealthConnectGateway.GoogleFitComparison first = comparison(1000L, 750.0, 995L, 742.5, 41.0);
        HealthConnectGateway.GoogleFitComparison updated = comparison(1000L, 750.0, 1002L, 748.0, 41.0);
        assertNotEquals(DriveTestExportManager.comparisonFingerprint(first),
            DriveTestExportManager.comparisonFingerprint(updated));
    }

    private static HealthConnectGateway.GoogleFitComparison comparison(
        long localSteps, double localDistance, Long fitSteps, Double fitDistance,
        Double calories
    ) {
        return new HealthConnectGateway.GoogleFitComparison(
            fitSteps, fitDistance, calories, localDistance, localSteps, 600_000L);
    }
}
