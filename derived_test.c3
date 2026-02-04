module atom::derived::test @test;

import std::io;
import std::atomic;

import atom;

faultdef REDUCER_FAIL;
faultdef INIT_FAIL;

fn void new_derived() {
    Atom{int}* atom_int = atom::new_with_value{int}(10)!!;

    // double the value of atom_int
    Derived{int}* double_int = atom::derived{int}(
        { atom_int }, // source_atoms
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];

            *writable = atom_int.try_get()!! * 2;
        }
    )!!;

    assert (double_int != null, "Readable should not be null");

    assert (double_int.try_get()!! == 20, "Readable value should be 20");

    atom_int.set_value(2)!!;

    assert (atom_int.try_get()!! == 2, "Atom value should be 2");

    assert (double_int.try_get()!! == 4, "Readable value should be 4");

    if(catch err = atom_int.destroy()){
        io::printn(err);
    }

    if(catch err = double_int.destroy()){
        io::printn(err);
    };
}

fn void derived_subscription() {
    Atom{int}* atom_int = atom::new_with_value{int}(10)!!;

    // double the value of atom_int
    Derived{int}* double_int = atom::derived{int}(
        { atom_int }, // source_atoms
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];

            *writable = atom_int.try_get()!! * 2;
        }
    )!!;

    Subscription subscription = double_int.subscribe(fn void(int* new_value, any ctx) {
        Atom{int}* atom_int = (Atom{int}*)ctx;
        assert (*new_value == atom_int.try_get()!! * 2, "Subscription should report doubled value of atom_int");
    }, atom_int)!!;

    atom_int.set_value(100)!!;

    assert(double_int.try_get()!! == 200, "Derived should be 200");

    atom_int.set_value(4)!!;

    assert(double_int.try_get()!! == 8, "Derived should be 8");

    subscription.unsubscribe()!!;

    atom_int.destroy()!!;

    double_int.destroy()!!;
}

fn void derived_unsubscribe_stops_updates() {
    Atom{int}* atom_int = atom::new_with_value{int}(3)!!;
    Derived{int}* double_int = atom::derived{int}(
        { atom_int },
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];
            *writable = atom_int.try_get()!! * 2;
        }
    )!!;

    int* hit = mem::alloc(int);
    *hit = 0;

    Subscription subscription = double_int.subscribe(fn void(int* new_value, any ctx) {
        int* hit = (int*)ctx;
        *hit = *hit + 1;
        assert(*new_value == 8, "Derived callback should see 8");
    }, hit)!!;

    atom_int.set_value(4)!!;

    subscription.unsubscribe()!!;

    atom_int.set_value(5)!!;

    assert(*hit == 1, "Derived callback should not fire after unsubscribe");

    mem::free(hit);
    atom_int.destroy()!!;
    double_int.destroy()!!;
}

fn void derived_reducer_fault_does_not_update() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;
    Derived{int}* double_int = atom::derived{int}(
        { atom_int },
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];
            int value = atom_int.try_get()!!;
            if (value == 2) {
                return REDUCER_FAIL~;
            }
            *writable = value * 2;
        }
    )!!;

    assert(double_int.try_get()!! == 2, "Derived should start at 2");

    if (catch err = atom_int.set_value(2)) {
        assert(err == REDUCER_FAIL, "Reducer fault should surface on notify");
    } else {
        unreachable("Reducer fault should propagate");
    }

    assert(double_int.try_get()!! == 2, "Derived value should remain unchanged on fault");

    atom_int.destroy()!!;
    double_int.destroy()!!;
}

fn void derived_signal_only_updates_on_signal() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;
    Atom{int}* signal = atom::new_with_value{int}(0)!!;

    Derived{int}* double_int = atom::derived{int}(
        { atom_int },
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];
            *writable = atom_int.try_get()!! * 2;
        },
        null,
        (Observable)signal
    )!!;

    assert(double_int.try_get()!! == 2, "Derived should start at 2");

    atom_int.set_value(3)!!;
    assert(double_int.try_get()!! == 2, "Derived should not update without signal");

    signal.set_value(1)!!;
    assert(double_int.try_get()!! == 6, "Derived should update when signal fires");

    atom_int.destroy()!!;
    signal.destroy()!!;
    double_int.destroy()!!;
}

fn void derived_init_reducer_fault_returns_error() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    if (catch err = atom::derived{int}(
        { atom_int },
        fn void?(int* writable, any[] source_atoms, any ctx) {
            return INIT_FAIL~;
        }
    )) {
        assert(err == INIT_FAIL, "Derived init should return reducer fault");
    } else {
        unreachable("Derived init should have faulted");
    }

    atom_int.destroy()!!;
}

fn void derived_initial_value_skips_init_reducer() {
    Atom{int}* atom_int = atom::new_with_value{int}(2)!!;

    Atomic{int} hits;
    hits.store(0, RELAXED);

    int* initial = mem::alloc(int);
    *initial = 99;

    Derived{int}* derived_int = atom::derived{int}(
        { atom_int },
        fn void?(int* writable, any[] source_atoms, any ctx) {
            Atomic{int}* hits = (Atomic{int}*)ctx;
            hits.add(1, RELAXED);
            Atom{int}* atom_int = (Atom{int}*)source_atoms[0];
            *writable = atom_int.try_get()!! * 2;
        },
        initial,
        null,
        &hits
    )!!;

    assert(derived_int.try_get()!! == 99, "Derived should use provided initial value");
    assert(hits.load(RELAXED) == 0, "Reducer should not run on init when initial value provided");

    atom_int.set_value(4)!!;

    assert(derived_int.try_get()!! == 8, "Derived should update after source change");
    assert(hits.load(RELAXED) == 1, "Reducer should run on refresh after source change");

    atom_int.destroy()!!;
    derived_int.destroy()!!;
}
