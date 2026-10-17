package app.deterministic.todo.deterministic_todo;

/** Provider identity, not an in-memory receipt, decides whether a retry inserts. */
final class AgendaCopyOperation {
    interface Store {
        String find(String key);
        String insert();
        void update(String id);
    }
    static String apply(String key, Store store) {
        String id = store.find(key);
        if (id == null) return store.insert();
        store.update(id);
        return id;
    }
    private AgendaCopyOperation() {}
}
