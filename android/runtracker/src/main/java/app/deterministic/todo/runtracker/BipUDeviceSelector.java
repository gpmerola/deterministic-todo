package app.deterministic.todo.runtracker;

import java.util.Locale;

/** Pure name matching kept separate from Android BLE orchestration for testing. */
final class BipUDeviceSelector {
    private BipUDeviceSelector() {}

    static boolean matchesName(String name) {
        return name != null && name.toLowerCase(Locale.ROOT).contains("bip u");
    }
}
