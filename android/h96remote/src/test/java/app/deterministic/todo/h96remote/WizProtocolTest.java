package app.deterministic.todo.h96remote;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import java.io.IOException;

import org.junit.Test;

public class WizProtocolTest {
    @Test public void commandsAreClampedJson() {
        assertEquals("{\"method\":\"setPilot\",\"params\":{\"state\":false}}", WizProtocol.power(false));
        assertEquals("{\"method\":\"setPilot\",\"params\":{\"state\":true,\"dimming\":10}}", WizProtocol.dimming(3));
        assertEquals("{\"method\":\"setPilot\",\"params\":{\"state\":true,\"dimming\":100}}", WizProtocol.dimming(140));
        assertEquals("{\"method\":\"setPilot\",\"params\":{\"state\":true,\"r\":255,\"g\":0,\"b\":128}}",
            WizProtocol.color(300, -5, 128));
        assertEquals("{\"method\":\"setPilot\",\"params\":{\"state\":true,\"temp\":2200}}", WizProtocol.white(1000));
    }

    @Test public void parsesGetPilotReply() {
        String reply = "{\"method\":\"getPilot\",\"env\":\"pro\",\"result\":{\"mac\":\"A8BB50AABBCC\","
            + "\"rssi\":-62,\"state\":true,\"sceneId\":0,\"r\":255,\"g\":10,\"b\":0,\"dimming\":45}}";
        WizProtocol.Pilot pilot = WizProtocol.parsePilot(reply);
        assertEquals("a8bb50aabbcc", pilot.mac);
        assertTrue(pilot.on);
        assertEquals(45, pilot.dimming);
        assertEquals(255, pilot.r);
        assertEquals(-1, pilot.kelvin);
    }

    @Test public void recognisesAcknowledgementsAndErrors() {
        assertTrue(WizProtocol.isSuccess("{\"method\":\"setPilot\",\"result\":{\"success\":true}}"));
        assertFalse(WizProtocol.isSuccess("{\"method\":\"setPilot\",\"error\":{\"code\":-32600}}"));
        assertNull(WizProtocol.parsePilot("{\"error\":{\"code\":-32601}}"));
    }

    @Test public void clientRefusesNonLanHosts() {
        try {
            new WizClient().request("8.8.8.8", WizProtocol.power(true));
            throw new AssertionError("an Internet host must be refused");
        } catch (IOException expected) {
            assertEquals("not a LAN address", expected.getMessage());
        }
    }
}
