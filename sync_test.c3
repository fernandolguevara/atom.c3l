module atom::sync::test @test;

import std::io;
import std::thread;
import std::atomic;
import atom;
import atom::sync;
import atom::test_helpers;

alias AtomFloat = Atom{float};

alias CelciusToFahrenheit = atom::sync::AtoB{float, float};
alias FahrenheitToCelcius = atom::sync::BtoA{float, float};

faultdef SYNC_FAIL;


struct FailOnceCtx {
    bool fail_next;
    Atomic{int}* errors;
}



CelciusToFahrenheit celsius_to_fahrenheit = fn float? (float* celsius, any ctx  = null) {
    return (float)((*celsius * 9.0 / 5.0) + 32.0);
};

FahrenheitToCelcius fahrenheit_to_celsius = fn float? (float* fahrenheit, any ctx = null) {
    return (float)((*fahrenheit - 32.0) * 5.0 / 9.0);
};

AtoB{float, float} a_to_b_fail_once = fn float? (float* value, any ctx = null) {
    FailOnceCtx* fail_ctx = (FailOnceCtx*)ctx;
    if (fail_ctx.fail_next) {
        fail_ctx.fail_next = false;
        return SYNC_FAIL~;
    }
    return *value + 10.0;
};

BtoA{float, float} b_to_a_fail_once = fn float? (float* value, any ctx = null) {
    FailOnceCtx* fail_ctx = (FailOnceCtx*)ctx;
    if (fail_ctx.fail_next) {
        fail_ctx.fail_next = false;
        return SYNC_FAIL~;
    }
    return *value - 10.0;
};

AtoB{float, float} a_to_b_identity = fn float? (float* value, any ctx = null) {
    return *value;
};

BtoA{float, float} b_to_a_identity = fn float? (float* value, any ctx = null) {
    return *value;
};


sync::ErrorCallback{float, float} on_sync_error = fn void(fault err, any ctx) {
    FailOnceCtx* fail_ctx = (FailOnceCtx*)ctx;
    if (fail_ctx.errors != null) {
        fail_ctx.errors.add(1, RELAXED);
    }
};

fn void sync_two_way() {
    AtomFloat* celsius_atom = atom::new_with_value{float}(25.0)!!;
    AtomFloat* fahrenheit_atom = atom::new_with_value{float}(celsius_to_fahrenheit(celsius_atom.get()!!))!!;

    assert(fahrenheit_atom.try_get()!! == 77.0, "Fahrenheit atom should be 77.0");

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(celsius_atom, fahrenheit_atom, celsius_to_fahrenheit, fahrenheit_to_celsius)!!;

    fahrenheit_atom.set_value(140.0)!!;

    assert(celsius_atom.try_get()!! == 60.0, "Celcius atom should be 60.0");

    celsius_atom.set_value(200.0)!!;

    assert(fahrenheit_atom.try_get()!! == 392.0, "Fahrenheit atom should be 392.0");

    if (catch err = sync_signal.destroy()) {
        io::printn(err);
    }

    celsius_atom.destroy()!!;
    fahrenheit_atom.destroy()!!;
}

fn void sync_two_way_initial_sync_prefers_a() {
    AtomFloat* atom_a = atom::new_with_value{float}(5.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(99.0)!!;

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_identity,
        b_to_a_identity
    )!!;

    assert(atom_b.try_get()!! == 5.0, "Two-way initial sync should apply A to B");
    assert(atom_a.try_get()!! == 5.0, "Atom A should remain unchanged");

    sync_signal.destroy()!!;
    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_one_way_a_to_b() {
    AtomFloat* celsius_atom = atom::new_with_value{float}(10.0)!!;
    AtomFloat* fahrenheit_atom = atom::new_with_value{float}(celsius_to_fahrenheit(celsius_atom.get()!!))!!;

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        celsius_atom,
        fahrenheit_atom,
        celsius_to_fahrenheit,
        fahrenheit_to_celsius,
        sync::SyncDirection.ONE_WAY_A_TO_B
    )!!;

    celsius_atom.set_value(20.0)!!;

    assert(fahrenheit_atom.try_get()!! == 68.0, "Fahrenheit should update from Celsius");

    fahrenheit_atom.set_value(32.0)!!;

    assert(celsius_atom.try_get()!! == 20.0, "Celsius should not update from Fahrenheit");

    if (catch err = sync_signal.destroy()) {
        io::printn(err);
    }

    celsius_atom.destroy()!!;
    fahrenheit_atom.destroy()!!;
}

fn void sync_one_way_b_to_a() {
    AtomFloat* celsius_atom = atom::new_with_value{float}(0.0)!!;
    AtomFloat* fahrenheit_atom = atom::new_with_value{float}(32.0)!!;

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        celsius_atom,
        fahrenheit_atom,
        celsius_to_fahrenheit,
        fahrenheit_to_celsius,
        sync::SyncDirection.ONE_WAY_B_TO_A
    )!!;

    fahrenheit_atom.set_value(212.0)!!;

    assert(celsius_atom.try_get()!! == 100.0, "Celsius should update from Fahrenheit");

    celsius_atom.set_value(10.0)!!;

    assert(fahrenheit_atom.try_get()!! == 212.0, "Fahrenheit should not update from Celsius");

    if (catch err = sync_signal.destroy()) {
        io::printn(err);
    }

    celsius_atom.destroy()!!;
    fahrenheit_atom.destroy()!!;
}

fn void sync_fail_a_to_b_resets_lock() {
    AtomFloat* atom_a = atom::new_with_value{float}(1.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(11.0)!!;

    FailOnceCtx* ctx = mem::new(FailOnceCtx, { .fail_next = false, .errors = null });

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_fail_once,
        b_to_a_fail_once,
        sync::SyncDirection.ONE_WAY_A_TO_B,
        ctx
    )!!;

    ctx.fail_next = true;
    atom_a.set_value(2.0)!!;

    assert(atom_b.try_get()!! == 11.0, "A->B sync should skip update on fault");

    atom_a.set_value(3.0)!!;

    assert(atom_b.try_get()!! == 13.0, "A->B sync should recover after fault");

    sync_signal.destroy()!!;
    mem::free(ctx);
    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_fail_b_to_a_resets_lock() {
    AtomFloat* atom_a = atom::new_with_value{float}(1.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(11.0)!!;

    FailOnceCtx* ctx = mem::new(FailOnceCtx, { .fail_next = false, .errors = null });

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_fail_once,
        b_to_a_fail_once,
        sync::SyncDirection.ONE_WAY_B_TO_A,
        ctx
    )!!;

    ctx.fail_next = true;
    atom_b.set_value(25.0)!!;

    assert(atom_a.try_get()!! == 1.0, "B->A sync should skip update on fault");

    atom_b.set_value(30.0)!!;

    assert(atom_a.try_get()!! == 20.0, "B->A sync should recover after fault");

    sync_signal.destroy()!!;
    mem::free(ctx);
    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_error_callback_called() {
    AtomFloat* atom_a = atom::new_with_value{float}(1.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(11.0)!!;

    Atomic{int} errors;
    errors.store(0, RELAXED);

    FailOnceCtx* ctx = mem::new(FailOnceCtx, { .fail_next = true, .errors = &errors });

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_fail_once,
        b_to_a_fail_once,
        sync::SyncDirection.ONE_WAY_A_TO_B,
        ctx,
        on_sync_error
    )!!;

    atom_a.set_value(2.0)!!;

    assert(errors.load(RELAXED) == 1, "Error callback should fire on conversion fault");

    atom_a.set_value(3.0)!!;

    assert(errors.load(RELAXED) == 1, "Error callback should not fire after recovery");

    sync_signal.destroy()!!;
    mem::free(ctx);
    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_destroy_does_not_destroy_sources() {
    AtomFloat* atom_a = atom::new_with_value{float}(5.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(15.0)!!;

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_identity,
        b_to_a_identity
    )!!;

    sync_signal.destroy()!!;

    atom_a.set_value(6.0)!!;
    atom_b.set_value(16.0)!!;

    assert(atom_a.try_get()!! == 6.0, "Atom A should remain valid after sync destroy");
    assert(atom_b.try_get()!! == 16.0, "Atom B should remain valid after sync destroy");

    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_initial_empty_skips_update() {
    AtomFloat* atom_a = atom::new{float}()!!;
    AtomFloat* atom_b = atom::new_with_value{float}(50.0)!!;

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_identity,
        b_to_a_identity,
        sync::SyncDirection.ONE_WAY_A_TO_B
    )!!;

    assert(atom_b.try_get()!! == 50.0, "Initial sync should skip when source is empty");

    atom_a.set_value(7.0)!!;

    assert(atom_b.try_get()!! == 7.0, "Atom B should update after source becomes set");

    sync_signal.destroy()!!;
    atom_a.destroy()!!;
    atom_b.destroy()!!;
}

fn void sync_destroy_waits_for_conversion() {
    AtomFloat* atom_a = atom::new_with_value{float}(1.0)!!;
    AtomFloat* atom_b = atom::new_with_value{float}(1.0)!!;

    Atomic{bool} lock_cleared;
    lock_cleared.store(false, RELAXED);

    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        atom_a,
        atom_b,
        a_to_b_identity,
        b_to_a_identity,
        sync::SyncDirection.ONE_WAY_A_TO_B
    )!!;

    sync_signal.sync_lock.set(ACQUIRE_RELEASE);

    test_helpers::SyncLockReleaseArgs release_args = {
        .lock = &sync_signal.sync_lock,
        .cleared = &lock_cleared,
    };
    Thread releaser;
    releaser.create(&test_helpers::sync_release_lock_after_delay, &release_args)!!;

    sync_signal.destroy()!!;

    releaser.join()!!;

    assert(lock_cleared.load(RELAXED), "Destroy should wait for lock release");

    atom_a.destroy()!!;
    atom_b.destroy()!!;
}
