module atom<Type>;

import std::io, std::collections, std::atomic;

import atom::contracts::typed, atom::faults, atom::subscriptions;

// Reducer may fault; on fault, the derived value is not updated.
alias Reducer = fn void?(Type* writable, any[] source_atoms, any ctx = null);

alias SubscriptionList = List{Subscription};

struct Derived (contracts::typed::Readable{Type}, Observer) {
    Atom* atom;
    Type* writable;
    Observable signal;
    any[] source_atoms;
    SubscriptionList subscriptions;
    Reducer reducer;
    any ctx;
    Atomic{bool} destroyed;
}

fn Derived{Type}*? derived(any[] source_atoms, Reducer reducer, Type* initial_value = null, Observable signal = null, any ctx = null) {
    if(initial_value == null) {
        initial_value = mem::new(Type);
        if (catch err = reducer(initial_value, source_atoms, ctx)) {
            mem::free(initial_value);
            return err~;
        }
    }

    Derived* derived = mem::new(Derived, {
        .atom = atom::new{Type}(initial_value)!,
        .writable = mem::new(Type),
        .reducer = reducer,
        .source_atoms = source_atoms,
        .signal = signal,
        .ctx = ctx,
        .destroyed = { .data = false },
    });

    if (catch err = derived.init()) {
        mem::free(derived.writable);
        if (derived.atom != null) {
            if (catch destroy_err = derived.atom.destroy()) {
                io::printn(destroy_err);
            }
        }
        mem::free(derived);
        return err~;
    }

    return derived;
}

fn void? Derived.update(&self) @dynamic => self.refresh();

fn Type? Derived.try_get(&self) @dynamic => self.atom.try_get()!;
fn Type*? Derived.get(&self) @dynamic => self.atom.get()!;

fn Subscription? Derived.subscribe(&self, SubscribeCallback{Type} callback, any ctx = null) @dynamic {
    return self.atom.subscribe(callback, ctx);
}

fn Subscription? Derived.observe(&self, Observer observer) @dynamic => self.atom.observe(observer);

fn void? Derived.init(&self) @private {
    self.subscriptions.init(mem);
    bool initialized = false;

    defer if (!initialized) {
        foreach(subscription : self.subscriptions) {
            if (catch unsub_err = subscription.unsubscribe()) {
                io::printn(unsub_err);
            }
        }
        self.subscriptions.clear();
        self.subscriptions.free();
    };

    if(self.signal) {
        Subscription sub = self.signal.observe(self)!;
        self.subscriptions.push(sub);
    } else {
        foreach(i, source_atom: self.source_atoms) {
            Observable observable = (Observable)source_atom;
            Subscription sub = observable.observe(self)!;
            self.subscriptions.push(sub);
        }
    }

    initialized = true;
}

fn void? Derived.refresh(&self) @private {
    self.reducer(self.writable, self.source_atoms, self.ctx)!;
    self.atom.set_value(*self.writable)!;
}

fn void? Derived.destroy(&self) @dynamic {
    if (self.destroyed.set(ACQUIRE_RELEASE)) {
        return;
    }

    foreach(subscription : self.subscriptions) {
        if(catch err = subscription.unsubscribe()){
            io::printn(err);
        };
    }

    self.subscriptions.clear();
    self.subscriptions.free();

    mem::free(self.writable);

    if(self.atom != null){
        self.atom.destroy()!!;
    }

    mem::free(self);
}
