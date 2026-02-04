module atom::faults;

faultdef EMPTY, INITIALIZATION_FAILED, SUBSCRIBER_ALREADY_REGISTERED;

module atom<Type>;

import std::thread, std::io, std::atomic;

import atom::faults, atom::subscriptions;

fn void free_atom_observer(void* observer) {
    mem::free(observer);
}

struct Atom (Observable, contracts::typed::Readable{Type}, contracts::typed::Writable{Type}, contracts::typed::Subscribable{Type}) {
    Mutex mu;
    Type* v;
    Atomic{bool} destroyed;
    subscriptions::SubscriptionState subs;
}

struct AtomObserverWithCallback (Observer) {
    Atom{Type}* atom;
    SubscribeCallback{Type} callback;
    any ctx;
}

struct AtomObserverWithValueCallback (Observer) {
    Atom{Type}* atom;
    SubscribeValueCallback{Type} callback;
    any ctx;
}

fn void? AtomObserverWithCallback.update(&self) @dynamic {
    self.callback(self.atom.get()!, self.ctx);
}

fn void? AtomObserverWithValueCallback.update(&self) @dynamic {
    Type value;
    if (!self.atom.try_copy(&value)!) {
        return;
    }
    self.callback(value, self.ctx);
}

fn Atom*? new(Type* initial_value = null) {
    Atom* atom = mem::new(Atom, { .v = initial_value, .destroyed = { .data = false }});

    if (catch atom.mu.init()) {
        mem::free(atom);
        if (initial_value != null) {
            mem::free(initial_value);
        }
        return faults::INITIALIZATION_FAILED~;
    }

    if (catch err = subscriptions::init(&atom.subs)) {
        atom.mu.destroy()!;
        if (initial_value != null) {
            mem::free(initial_value);
        }
        mem::free(atom);
        return err~;
    }

    return atom;
}

fn Atom*? new_with_value(Type value) {
    Type* initial_value = mem::alloc(Type);
    *initial_value = value;

    return new(initial_value);
}


fn Subscription? Atom.subscribe(&self, SubscribeCallback{Type} callback, any ctx = null) @dynamic {
    AtomObserverWithCallback* observer = mem::new(AtomObserverWithCallback,  {
        .atom = self,
        .callback = callback,
        .ctx = ctx
    });

    return subscriptions::add(&self.subs, observer, &free_atom_observer);
}

fn Subscription? Atom.subscribe_value(&self, SubscribeValueCallback{Type} callback, any ctx = null) @dynamic {
    AtomObserverWithValueCallback* observer = mem::new(AtomObserverWithValueCallback,  {
        .atom = self,
        .callback = callback,
        .ctx = ctx
    });

    return subscriptions::add(&self.subs, observer, &free_atom_observer);
}

fn Subscription? Atom.subscribe_once(&self, SubscribeCallback{Type} callback, any ctx = null) @dynamic {
    AtomObserverWithCallback* observer = mem::new(AtomObserverWithCallback,  {
        .atom = self,
        .callback = callback,
        .ctx = ctx
    });

    return subscriptions::once(&self.subs, observer, &free_atom_observer);
}

fn Subscription? Atom.observe(&self, Observer observer) @dynamic {
    return subscriptions::add(&self.subs, observer, null);
}

fn Type? Atom.try_get(&self) @dynamic {
    self.mu.lock()!;

    Type* value = self.v;

    self.mu.unlock()!;

    if (null == value) {
        return faults::EMPTY~;
    }

    return *value;
}

fn bool? Atom.try_copy(&self, Type* out) @dynamic {
    self.mu.lock()!;

    if (self.v == null) {
        self.mu.unlock()!;
        return false;
    }

    *out = *self.v;
    self.mu.unlock()!;
    return true;
}

// Returns a raw pointer that is only safe to use while no other thread
// can clear/destroy this atom. Prefer try_get() or with_lock() in
// multi-threaded contexts.
fn Type*? Atom.get(&self) @dynamic {
    self.mu.lock()!;

    Type* value = self.v;

    self.mu.unlock()!;

    return value;
}

fn void? Atom.set_value(&self, Type value) @dynamic {
    self.mu.lock()!;

    if (self.v == null) {
        self.v = mem::alloc(Type);
    }
    *self.v = value;

    self.mu.unlock()!;

    subscriptions::notify(&self.subs)!;
}

fn void? Atom.reset(&self, Type value) @dynamic {
    self.set_value(value)!;
}

fn void? Atom.with_lock(&self, typed::Locker{Type} locker, any ctx = null) @dynamic {
    self.mu.lock()!;
    defer self.mu.unlock()!!;

    if (self.v == null) {
        self.v = mem::alloc(Type);
    }
    locker(self.v, ctx);

    subscriptions::notify(&self.subs)!;
}

fn void? Atom.update(&self, typed::Updater{Type} updater, any ctx = null)  @dynamic {
    self.mu.lock()!;
    defer self.mu.unlock()!!;

    Type* state = self.v;
    Type next_value = updater(state, ctx)!;
    if (self.v == null) {
        self.v = mem::alloc(Type);
    }
    *self.v = next_value;

    subscriptions::notify(&self.subs)!;
}

fn void? Atom.clear(&self) {
    self.mu.lock()!;

    Type* old_value = self.v;
    self.v = null;

    self.mu.unlock()!;

    if (old_value != null) {
        mem::free(old_value);
    }

    subscriptions::notify(&self.subs)!;
}

fn bool? Atom.is_empty(&self) {
    return null == self.get();
}

fn void? Atom.destroy(&self) @dynamic {
    if (self.destroyed.set(ACQUIRE_RELEASE)) {
        return;
    }
    if (subscriptions::has_subscription(&self.subs)) {
        subscriptions::remove_all(&self.subs)!;
    }
    subscriptions::deinit(&self.subs)!;

    NativeMutex nmu = (NativeMutex)self.mu;
    if (nmu.is_initialized()) {
        self.mu.lock()!;
        mem::free(self.v);
        self.mu.unlock()!;
        self.mu.destroy()!;
    } else {
        mem::free(self.v);
    }

    mem::free(self);
}
