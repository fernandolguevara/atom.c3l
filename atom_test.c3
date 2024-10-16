module atom::test @test;

import atom;

fn void! new_atom() {
    Atom(<int>)* atom_int = atom::new(<int>)()!;

    assert (atom_int != null, "Atom should not be null");
}

fn void! new_atom_empty() {
    Atom(<int>)* atom_int = atom::new(<int>)()!;

    assert (atom_int.is_empty()!, "Atom should be empty");
}

fn void! new_atom_with_value() {
    Atom(<int>)* atom_int = atom::new_with_value(<int>)(1)!;

    assert (!atom_int.is_empty()!, "Atom should not be empty");

    assert(atom_int.try_get()! == 1, "Atom value should be 1");
}

fn void! atom_subscription() {
    Atom(<int>)* atom_int = atom::new_with_value(<int>)(1)!;

    assert(atom_int.try_get()! == 1, "Atom value should be 1");

    atom_int.subscribe(fn void(int* new_value, any ctx) {
        assert(*new_value == 2, "Atom new_value should be 2");
    })!;

    atom_int.set_value(2)!;
    
    assert(atom_int.try_get()! == 2, "Atom value should be 2");
}

fn void! atom_cancel_subscription() {
    Atom(<int>)* atom_int = atom::new_with_value(<int>)(1)!;

    assert(atom_int.try_get()! == 1, "Atom value should be 1");

    Subscription subscription = atom_int.subscribe(fn void(int* new_value, any ctx) {
        unreachable("Atom callback should be called on unsubscribed");
    })!;

    subscription.unsubscribe()!;

    atom_int.set_value(2)!;
    
    assert(atom_int.try_get()! == 2, "Atom value should be 2");
}