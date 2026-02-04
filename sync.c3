module atom::sync<TyA, TyB>;

import std::thread;
import std::atomic;
import std::collections::list;

import atom;
import std::io;

alias BtoA = fn TyA?(TyB* a, any ctx = null);
alias AtoB = fn TyB?(TyA* a, any ctx = null);
alias ErrorCallback = fn void(fault err, any ctx = null);

// Enum to represent sync direction
enum SyncDirection  {
    ONE_WAY_A_TO_B,
    ONE_WAY_B_TO_A,
    TWO_WAY
}

// Struct to hold synchronization between two atoms
struct SyncAtoms (Observable) {
    Atom{TyA}* atom_a;
    Atom{TyB}* atom_b;
    AtoB to_type_b;  // Function to convert TyA -> TyB
    BtoA to_type_a;  // Function to convert TyB -> TyA
    any ctx;
    ErrorCallback on_error;
    Atomic{bool} sync_lock; // Prevent recursive updates
    SyncDirection direction; // New: sync direction (one-way or two-way)
    List{Subscription} subscriptions;
    Atomic{bool} destroyed;
    subscriptions::SubscriptionState subs;
}

fn void? update_a_to_b(SyncAtoms* sync, TyA* new_value) @private {
    TyB new_value_b = sync.to_type_b(new_value, sync.ctx)!;
    sync.atom_b.set_value(new_value_b)!;
    subscriptions::notify(&sync.subs)!;
}

fn void? update_b_to_a(SyncAtoms* sync, TyB* new_value) @private {
    TyA new_value_a = sync.to_type_a(new_value, sync.ctx)!;
    sync.atom_a.set_value(new_value_a)!;
    subscriptions::notify(&sync.subs)!;
}

fn void? SyncAtoms.destroy(&self) @dynamic {
    if (self.destroyed.set(ACQUIRE_RELEASE)) {
        return;
    }

    while (self.sync_lock.load(ACQUIRE)) {
        thread::yield();
    }

    foreach (subscription : self.subscriptions) {
        if (catch err = subscription.unsubscribe()) {
            io::printn(err);
        }
    }
    self.subscriptions.clear();
    self.subscriptions.free();

    if (subscriptions::has_subscription(&self.subs)) {
        subscriptions::remove_all(&self.subs)!;
    }
    subscriptions::deinit(&self.subs)!;

    mem::free(self);
}

// Function to set up synchronization between two atoms with sync direction
fn SyncAtoms*? new(
    Atom{TyA}* atom_a,
    Atom{TyB}* atom_b,
    AtoB to_type_b,
    BtoA to_type_a,
    SyncDirection direction = SyncDirection.TWO_WAY, // Default to two-way sync
    any ctx = null,
    ErrorCallback on_error = null
) {
    SyncAtoms* sync = mem::new(SyncAtoms, {
        .atom_a = atom_a,
        .atom_b = atom_b,
        .to_type_b = to_type_b,
        .to_type_a = to_type_a,
        .ctx = ctx,
        .on_error = on_error,
        .sync_lock = { .data = false },
        .direction = direction,
        .destroyed = { .data = false },
    });
    sync.subscriptions.init(mem);
    subscriptions::init(&sync.subs)!;

    // Sync A → B if direction allows
    if (direction == SyncDirection.ONE_WAY_A_TO_B || direction == SyncDirection.TWO_WAY) {
        Subscription sub = atom_a.subscribe(fn void(TyA* new_value, any ctx) {
            SyncAtoms* sync = (SyncAtoms*)ctx;

            if (sync.destroyed.load(ACQUIRE)) {
                return;
            }

            if (!sync.sync_lock.set(ACQUIRE_RELEASE)) {
                defer sync.sync_lock.clear(RELEASE);
                if (sync.destroyed.load(ACQUIRE)) {
                    return;
                }
                if (catch err = update_a_to_b(sync, new_value)) {
                    if (sync.on_error != null) {
                        sync.on_error(err, sync.ctx);
                    }
                    return;
                }
            }
        }, sync)!;
        sync.subscriptions.push(sub);
    }

    // Sync B → A if direction allows
    if (direction == SyncDirection.ONE_WAY_B_TO_A || direction == SyncDirection.TWO_WAY) {
        Subscription sub = atom_b.subscribe(fn void(TyB* new_value, any ctx) {
            SyncAtoms* sync = (SyncAtoms*)ctx;

            if (sync.destroyed.load(ACQUIRE)) {
                return;
            }

            if (!sync.sync_lock.set(ACQUIRE_RELEASE)) {
                defer sync.sync_lock.clear(RELEASE);
                if (sync.destroyed.load(ACQUIRE)) {
                    return;
                }
                if (catch err = update_b_to_a(sync, new_value)) {
                    if (sync.on_error != null) {
                        sync.on_error(err, sync.ctx);
                    }
                    return;
                }
            }
        }, sync)!;
        sync.subscriptions.push(sub);
    }

    // Initial sync is deterministic: TWO_WAY uses A -> B on creation.
    if (direction == SyncDirection.ONE_WAY_A_TO_B || direction == SyncDirection.TWO_WAY) {
        TyA current_a;
        if (atom_a.try_copy(&current_a)! && !sync.sync_lock.set(ACQUIRE_RELEASE)) {
            defer sync.sync_lock.clear(RELEASE);
            if (catch err = update_a_to_b(sync, &current_a)) {
                if (sync.on_error != null) {
                    sync.on_error(err, sync.ctx);
                }
            }
        }
    } else if (direction == SyncDirection.ONE_WAY_B_TO_A) {
        TyB current_b;
        if (atom_b.try_copy(&current_b)! && !sync.sync_lock.set(ACQUIRE_RELEASE)) {
            defer sync.sync_lock.clear(RELEASE);
            if (catch err = update_b_to_a(sync, &current_b)) {
                if (sync.on_error != null) {
                    sync.on_error(err, sync.ctx);
                }
            }
        }
    }

    return sync;
}

fn Subscription? SyncAtoms.observe(&self, Observer observer) @dynamic {
    return atom::subscriptions::add(&self.subs, observer, null);
}

fn void? destroy(SyncAtoms* sync) {
    if (sync == null) {
        return;
    }
    sync.destroy()!;
}
