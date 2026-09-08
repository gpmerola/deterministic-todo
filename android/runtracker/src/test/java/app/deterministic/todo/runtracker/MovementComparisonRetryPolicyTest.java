package app.deterministic.todo.runtracker;

import static org.junit.Assert.*;

import org.junit.Test;

public class MovementComparisonRetryPolicyTest {
    @Test public void missingReferenceGetsBoundedRetries() {
        assertTrue(MovementComparisonRetryPolicy.retryMissingReference(0));
        assertTrue(MovementComparisonRetryPolicy.retryMissingReference(3));
        assertFalse(MovementComparisonRetryPolicy.retryMissingReference(4));
    }

    @Test public void availableReferenceIsRefreshedTwiceForFitLag() {
        assertTrue(MovementComparisonRetryPolicy.refreshAvailableReference(0));
        assertTrue(MovementComparisonRetryPolicy.refreshAvailableReference(1));
        assertFalse(MovementComparisonRetryPolicy.refreshAvailableReference(2));
    }

    @Test public void permissionFailureStopsButHealthErrorsRetry() {
        assertFalse(MovementComparisonRetryPolicy.retryFailure("permission_required", 0));
        assertTrue(MovementComparisonRetryPolicy.retryFailure("health_error_IllegalStateException", 0));
        assertFalse(MovementComparisonRetryPolicy.retryFailure("health_error_IllegalStateException", 4));
    }

    @Test public void foregroundRecoveryUsesLatestSessionStatus() {
        assertTrue(MovementComparisonRetryPolicy.needsForegroundRecovery("scheduled"));
        assertTrue(MovementComparisonRetryPolicy.needsForegroundRecovery("health_error_IllegalStateException"));
        assertFalse(MovementComparisonRetryPolicy.needsForegroundRecovery("success"));
    }
}
