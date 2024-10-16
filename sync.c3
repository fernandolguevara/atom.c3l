module atom::sync(<TyA, TyB>);

import std::thread;
import std::collections::map;

import atom;

def BtoA = fn TyA!(TyB* a, any ctx = null);
def AtoB = fn TyB!(TyA* a, any ctx = null);

// Enum to represent sync direction
enum SyncDirection  {
    ONE_WAY_A_TO_B,
    ONE_WAY_B_TO_A,
    TWO_WAY
}

// Struct to hold synchronization between two atoms
struct SyncAtoms (Observable) {
    Atom(<TyA>)* atom_a;
    Atom(<TyB>)* atom_b;
    AtoB to_type_b;  // Function to convert TyA -> TyB
    BtoA to_type_a;  // Function to convert TyB -> TyA
    any ctx;
    bool sync_lock; // Prevent recursive updates
    SyncDirection direction; // New: sync direction (one-way or two-way)
    Subscription[] subscriptions;
}

// Function to set up synchronization between two atoms with sync direction
fn Observable! new(
    Atom(<TyA>)* atom_a, 
    Atom(<TyB>)* atom_b, 
    AtoB to_type_b, 
    BtoA to_type_a, 
    SyncDirection direction = SyncDirection.TWO_WAY, // Default to two-way sync
    any ctx = null
) {
    SyncAtoms* sync = mem::new(SyncAtoms, {
        .atom_a = atom_a,
        .atom_b = atom_b,
        .to_type_b = to_type_b,
        .to_type_a = to_type_a,
        .ctx = ctx,
        .sync_lock = false,
        .direction = direction
    });

    // Sync A → B if direction allows
    if (direction == SyncDirection.ONE_WAY_A_TO_B || direction == SyncDirection.TWO_WAY) {
        atom_a.subscribe(fn void(TyA* new_value, any ctx) {
            SyncAtoms* sync = (SyncAtoms*)ctx;
        
            if (!sync.sync_lock) {
                sync.sync_lock = true;
                TyB* new_value_b = mem::alloc(TyB);
                *new_value_b = sync.to_type_b(new_value, sync.ctx)!!;
                sync.atom_b.set(new_value_b)!!;
               

                subscriptions::notify(sync)!!;

                sync.sync_lock = false;
            }
        }, sync)!;
    }

    // Sync B → A if direction allows
    if (direction == SyncDirection.ONE_WAY_B_TO_A || direction == SyncDirection.TWO_WAY) {
        atom_b.subscribe(fn void(TyB* new_value, any ctx) {
            SyncAtoms* sync = (SyncAtoms*)ctx;

            if (!sync.sync_lock) {
                sync.sync_lock = true;
                TyA* new_value_a = mem::alloc(TyA);
                *new_value_a = sync.to_type_a(new_value, sync.ctx)!!;
                sync.atom_a.set(new_value_a)!!;

                subscriptions::notify(sync)!!;

                sync.sync_lock = false;
            }
        }, sync)!;
    }

    return (Observable)sync;
}

fn Subscription! SyncAtoms.observe(&self, Observer observer) @dynamic {
	return atom::subscriptions::new(self, observer);
}