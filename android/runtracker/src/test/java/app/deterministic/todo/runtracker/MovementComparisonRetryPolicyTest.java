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
}
