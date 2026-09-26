package app.deterministic.todo.runtracker;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.List;

public class PassiveEpisodeAnalyzerTest {
    private PassiveEpisodeAnalyzer.MinuteEvidence minute(long start, long steps,
                                                          long walking, long running,
                                                          long bipSteps) {
        return new PassiveEpisodeAnalyzer.MinuteEvidence(start, start + 60_000,
            steps, steps * 0.72, walking, running, steps - walking - running,
            0, 0, 0, steps, steps * 0.69, bipSteps, bipSteps > 0 ? 80 : null,
            bipSteps > 0 ? 1 : 0);
    }

    @Test public void bridgesOnePauseAndKeepsThreeSourcesAligned() {
        List<PassiveEpisodeAnalyzer.Episode> episodes = PassiveEpisodeAnalyzer.episodes(List.of(
            minute(0, 90, 90, 0, 88),
            minute(60_000, 0, 0, 0, 0),
            minute(120_000, 100, 100, 0, 97)
        ));
        assertEquals(1, episodes.size());
        PassiveEpisodeAnalyzer.Episode episode = episodes.get(0);
        assertEquals(2, episode.activeMinutes());
        assertEquals(1, episode.pauseMinutes());
        assertEquals(190, episode.todoSteps());
        assertEquals(185, episode.bipSteps());
        assertEquals(Integer.valueOf(80), episode.bipHeartRateMean());
    }

    @Test public void splitsLongPauseAndMarksMissingWatch() {
        List<PassiveEpisodeAnalyzer.Episode> episodes = PassiveEpisodeAnalyzer.episodes(List.of(
            minute(0, 80, 80, 0, 0),
            minute(60_000, 0, 0, 0, 0),
            minute(120_000, 0, 0, 0, 0),
            minute(180_000, 85, 0, 85, 0)
        ));
        assertEquals(2, episodes.size());
        assertEquals("walking", episodes.get(0).activity());
        assertEquals("running", episodes.get(1).activity());
        assertTrue(episodes.get(0).qualityFlags().contains("bip_not_observed"));
    }

    @Test public void reconstructsOneImplicitMissingMinuteAsPause() {
        List<PassiveEpisodeAnalyzer.Episode> episodes = PassiveEpisodeAnalyzer.episodes(List.of(
            minute(0, 80, 80, 0, 75),
            minute(120_000, 85, 85, 0, 82)
        ));
        assertEquals(1, episodes.size());
        assertEquals(1, episodes.get(0).pauseMinutes());
        assertEquals(180_000, episodes.get(0).endMillis());
    }
}
