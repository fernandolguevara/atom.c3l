module atom::derived::test @test;

import atom;

fn void! new_derived() {
    Atom(<int>)* atom_int = atom::new_with_value(<int>)(10)!;

    // double the value of atom_int
    contracts::typed::Readable(<int>) double_int = atom::derived(<int>)(
        { atom_int }, // source_atoms
        fn void!(int* writable, any[] source_atoms, any ctx) {
            Atom(<int>)* atom_int = (Atom(<int>)*)source_atoms[0];

            *writable = atom_int.try_get()! * 2;
        }
    )!;

    assert (double_int != null, "Readable should not be null");

    assert (double_int.try_get()! == 20, "Readable value should be 20");

    atom_int.set_value(2)!;

    assert (atom_int.try_get()! == 2, "Atom value should be 2");

    assert (double_int.try_get()! == 4, "Readable value should be 4");
}

fn void! derived_subscription() {
    Atom(<int>)* atom_int = atom::new_with_value(<int>)(10)!;

    // double the value of atom_int
    contracts::typed::Readable(<int>) double_int = atom::derived(<int>)(
        { atom_int }, // source_atoms
        fn void!(int* writable, any[] source_atoms, any ctx) {
            Atom(<int>)* atom_int = (Atom(<int>)*)source_atoms[0];

            *writable = atom_int.try_get()! * 2;
        }
    )!;

    Subscription subscription = double_int.subscribe(fn void(int* new_value, any ctx) {
        Atom(<int>)* atom_int = (Atom(<int>)*)ctx;
        assert (*new_value == atom_int.try_get()!! * 2, "Subscription should report doubled value of atom_int");
    }, atom_int)!;

    atom_int.set_value(100)!;

    assert(double_int.try_get()! == 200, "Derived should be 200");

    atom_int.set_value(4)!;

    assert(double_int.try_get()! == 8, "Derived should be 8");
}