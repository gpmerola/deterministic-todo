package app.deterministic.todo.h96remote;

/** Abstract remote commands, independent of transport. Values are Android KeyEvent codes. */
public enum RemoteCommand {
    UP(19), DOWN(20), LEFT(21), RIGHT(22), OK(23),
    HOME(3), BACK(4),
    VOLUME_UP(24), VOLUME_DOWN(25), MUTE(164),
    DELETE(67), ENTER(66),
    POWER(26);

    public final int keyCode;

    RemoteCommand(int keyCode) {
        this.keyCode = keyCode;
    }

    /** Parses the name used by the Flutter channel; null when unknown. */
    public static RemoteCommand parse(String name) {
        if (name == null) return null;
        for (RemoteCommand command : values()) if (command.name().equalsIgnoreCase(name)) return command;
        return null;
    }
}
