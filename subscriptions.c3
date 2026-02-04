module atom::subscriptions;

import std::thread, std::collections::list, atom::contracts;

alias ObserverFree = fn void(void* observer);

// Invariants:
// - observers holds active entries; pending_frees holds entries deferred due to notify.
// - notifying_count tracks active notify() calls; refcount tracks per-entry in-flight use.
struct SubscriptionState {
    List{ObserverEntry*} observers;
    List{ObserverEntry*} pending_frees;
    Mutex mu;
    bool initialized;
    usz notifying_count;
}

struct ObserverEntry (Subscription) {
    Observer observer;
    ObserverFree free_observer;
    bool unsubscribe_on_update;
    SubscriptionState* state;
    usz refcount;
    bool pending_free;
}

fn void free_observer_entry(ObserverEntry* entry) @private {
    if (entry.free_observer != null) {
        entry.free_observer(entry.observer);
    }
    mem::free(entry);
}

fn void? init(SubscriptionState* state) {
    state.observers.init(mem);
    state.pending_frees.init(mem);
    state.mu.init()!;
    state.initialized = true;
    state.notifying_count = 0;
}

fn void? deinit(SubscriptionState* state) {
    if (!state.initialized) {
        return;
    }

    while (true) {
        state.mu.lock()!;
        if (state.notifying_count == 0) {
            break;
        }
        state.mu.unlock()!;
        thread::yield();
    }

    foreach (observer_entry : state.observers) {
        free_observer_entry(observer_entry);
    }
    state.observers.clear();

    foreach (observer_entry : state.pending_frees) {
        free_observer_entry(observer_entry);
    }
    state.pending_frees.clear();
    state.mu.unlock()!;

    state.observers.free();
    state.pending_frees.free();
    state.mu.destroy()!;
    state.initialized = false;
}

fn Subscription? add(SubscriptionState* state, Observer observer, ObserverFree free_observer = null) {
    ObserverEntry* observer_entry = mem::new(ObserverEntry, {
        .observer = observer,
        .free_observer = free_observer,
        .unsubscribe_on_update = false,
        .state = state,
        .refcount = 0,
        .pending_free = false,
    });

    state.mu.lock()!;
    state.observers.push(observer_entry);
    state.mu.unlock()!;

    return observer_entry;
}

fn Subscription? once(SubscriptionState* state, Observer observer, ObserverFree free_observer = null) {
    Subscription sub = add(state, observer, free_observer)!;
    ObserverEntry* entry = (ObserverEntry*)sub;
    entry.unsubscribe_on_update = true;
    return sub;
}

// notify() will invoke all observers, even if some fault; it returns the first fault.
fn void? notify(SubscriptionState* state) {
    state.mu.lock()!;
    if (state.observers.is_empty()) {
        state.mu.unlock()!;
        return;
    }

    List{ObserverEntry*} observers;
    observers.init(mem);
    foreach (observer_entry : state.observers) {
        observer_entry.refcount += 1;
        observers.push(observer_entry);
    }
    state.notifying_count += 1;
    state.mu.unlock()!;

    List{ObserverEntry*} once_entries;
    once_entries.init(mem);

    fault first_err;
    bool has_err = false;
    foreach (observer_entry : observers) {
        if (catch err = observer_entry.observer.update()) {
            if (!has_err) {
                first_err = err;
                has_err = true;
            }
        }
        if (observer_entry.unsubscribe_on_update) {
            once_entries.push(observer_entry);
        }
    }

    foreach (observer_entry : once_entries) {
        observer_entry.unsubscribe()!;
    }
    once_entries.free();

    state.mu.lock()!;
    foreach (observer_entry : observers) {
        observer_entry.refcount -= 1;
    }
    state.notifying_count -= 1;

    usz i = 0;
    while (i < state.pending_frees.size) {
        ObserverEntry* pending = state.pending_frees.entries[i];
        if (pending.refcount == 0 && pending.pending_free && state.notifying_count == 0) {
            state.pending_frees.remove_at(i);
            state.mu.unlock()!;
            free_observer_entry(pending);
            state.mu.lock()!;
            continue;
        }
        i += 1;
    }
    state.mu.unlock()!;
    observers.free();
    if (has_err) {
        return first_err~;
    }
}

// remove_all waits for in-flight notify() calls to finish before freeing entries.
fn void? remove_all(SubscriptionState* state) {
    if (!state.initialized) {
        return;
    }

    while (true) {
        state.mu.lock()!;
        if (state.notifying_count == 0) {
            break;
        }
        state.mu.unlock()!;
        thread::yield();
    }
    foreach (observer_entry : state.observers) {
        free_observer_entry(observer_entry);
    }
    state.observers.clear();

    foreach (observer_entry : state.pending_frees) {
        free_observer_entry(observer_entry);
    }
    state.pending_frees.clear();
    state.mu.unlock()!;
}

fn bool has_subscription(SubscriptionState* state) {
    return !state.observers.is_empty();
}

fn void? ObserverEntry.unsubscribe(&self) @dynamic {
    if (self.state == null) {
        return;
    }

    SubscriptionState* state = self.state;

    state.mu.lock()!;
    state.observers.remove_item(self);
    self.pending_free = true;

    if (self.refcount == 0 && state.notifying_count == 0) {
        self.state = null;
        state.mu.unlock()!;
        free_observer_entry(self);
        return;
    }

    state.pending_frees.push(self);
    self.state = null;
    state.mu.unlock()!;
}
