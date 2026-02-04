module atom::test @test;

import std::io;
import atom;
import atom::faults;

faultdef UPDATE_FAIL;

struct SubCtx {
    Subscription* sub;
    int* hits;
}

struct ValueCtx {
    int* hits;
    int* last;
}

fn void new_atom() {
    Atom{int}* atom_int = atom::new{int}()!!;

    assert (atom_int != null, "Atom should not be null");

    atom_int.destroy()!!;
}

fn void new_atom_empty() {
    Atom{int}* atom_int = atom::new{int}()!!;

    assert (atom_int.is_empty()!!, "Atom should be empty");

    if (catch err = atom_int.try_get()) {
        assert(err == faults::EMPTY, "try_get should return EMPTY when atom is empty");
    } else {
        unreachable("try_get should have faulted on empty atom");
    }

    atom_int.destroy()!!;
}

fn void new_atom_with_value() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    assert (!atom_int.is_empty()!!, "Atom should not be empty");

    assert(atom_int.try_get()!! == 1, "Atom value should be 1");

    atom_int.destroy()!!;
}

fn void atom_subscription() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    assert(atom_int.try_get()!! == 1, "Atom value should be 1");

    atom_int.subscribe(fn void(int* new_value, any ctx) {
        assert(*new_value == 2, "Atom new_value should be 2");
    })!!;

    atom_int.set_value(2)!!;

    assert(atom_int.try_get()!! == 2, "Atom value should be 2");

    atom_int.destroy()!!;
}

fn void atom_cancel_subscription() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    assert(atom_int.try_get()!! == 1, "Atom value should be 1");

    Subscription subscription = atom_int.subscribe(fn void(int* new_value, any ctx) {
        unreachable("Atom callback should be called on unsubscribed");
    })!!;

    subscription.unsubscribe()!!;

    atom_int.set_value(2)!!;

    assert(atom_int.try_get()!! == 2, "Atom value should be 2");

    atom_int.destroy()!!;
}

fn void atom_clear_and_empty() {
    Atom{int}* atom_int = atom::new_with_value{int}(3)!!;

    assert(!atom_int.is_empty()!!, "Atom should not be empty");

    atom_int.clear()!!;

    assert(atom_int.is_empty()!!, "Atom should be empty after clear");

    if (catch err = atom_int.try_get()) {
        assert(err == faults::EMPTY, "try_get should return EMPTY after clear");
    }

    atom_int.destroy()!!;
}

fn void atom_clear_idempotent() {
    Atom{int}* atom_int = atom::new_with_value{int}(3)!!;

    atom_int.clear()!!;
    atom_int.clear()!!;

    assert(atom_int.is_empty()!!, "Atom should remain empty after repeated clear");

    atom_int.destroy()!!;
}

fn void atom_set_pointer() {
    Atom{int}* atom_int = atom::new{int}()!!;

    atom_int.set_value(42)!!;

    assert(atom_int.try_get()!! == 42, "Atom should read set pointer value");

    atom_int.destroy()!!;
}

fn void atom_reset_and_lock() {
    Atom{int}* atom_int = atom::new{int}()!!;

    atom_int.reset(5)!!;
    atom_int.with_lock(fn void(int* value, any ctx) {
        *value = *value + 2;
    })!!;

    assert(atom_int.try_get()!! == 7, "Atom reset + with_lock should update value");

    atom_int.destroy()!!;
}

fn void atom_subscribe_once() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;
    int* counter = mem::alloc(int);
    *counter = 0;

    atom_int.subscribe_once(fn void(int* new_value, any ctx) {
        int* count = (int*)ctx;
        *count = *count + 1;
    }, counter)!!;

    atom_int.set_value(2)!!;
    atom_int.set_value(3)!!;

    assert(*counter == 1, "subscribe_once should fire once");

    mem::free(counter);
    atom_int.destroy()!!;
}

fn void atom_subscribe_value_snapshot() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    int* hits = mem::alloc(int);
    int* last = mem::alloc(int);
    *hits = 0;
    *last = 0;

    ValueCtx* ctx = mem::new(ValueCtx, { .hits = hits, .last = last });

    atom_int.subscribe_value(fn void(int value, any ctx_any) {
        ValueCtx* ctx = (ValueCtx*)ctx_any;
        *ctx.hits = *ctx.hits + 1;
        *ctx.last = value;
    }, ctx)!!;

    atom_int.set_value(2)!!;
    assert(*hits == 1, "subscribe_value should fire on update");
    assert(*last == 2, "subscribe_value should receive snapshot value");

    atom_int.clear()!!;
    assert(*hits == 1, "subscribe_value should skip empty notifications");

    atom_int.set_value(3)!!;
    assert(*hits == 2, "subscribe_value should fire after value returns");
    assert(*last == 3, "subscribe_value should update snapshot value");

    mem::free(ctx);
    mem::free(hits);
    mem::free(last);
    atom_int.destroy()!!;
}

fn void atom_update_replaces_value() {
    Atom{int}* atom_int = atom::new_with_value{int}(5)!!;

    atom_int.update(fn int? (int* current, any ctx) {
        if (current == null) {
            return 10;
        }
        return *current + 10;
    })!!;

    assert(atom_int.try_get()!! == 15, "Atom update should replace value");

    atom_int.destroy()!!;
}

fn void atom_update_handles_empty() {
    Atom{int}* atom_int = atom::new{int}()!!;

    atom_int.update(fn int? (int* current, any ctx) {
        if (current == null) {
            return 10;
        }
        return *current + 10;
    })!!;

    assert(atom_int.try_get()!! == 10, "Atom update should initialize value when empty");

    atom_int.destroy()!!;
}

fn void atom_multiple_subscribers() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;
    int* counter = mem::alloc(int);
    *counter = 0;

    Subscription sub_a = atom_int.subscribe(fn void(int* new_value, any ctx) {
        int* count = (int*)ctx;
        *count = *count + 1;
        assert(*new_value == 9, "Subscriber A should see value 9");
    }, counter)!!;

    Subscription sub_b = atom_int.subscribe(fn void(int* new_value, any ctx) {
        int* count = (int*)ctx;
        *count = *count + 1;
        assert(*new_value == 9, "Subscriber B should see value 9");
    }, counter)!!;

    atom_int.set_value(9)!!;

    assert(*counter == 2, "Both subscribers should be called");

    sub_a.unsubscribe()!!;
    sub_b.unsubscribe()!!;

    mem::free(counter);
    atom_int.destroy()!!;
}

fn void atom_update_fault_releases_mutex() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    if (catch err = atom_int.update(fn int? (int* current, any ctx) {
        return UPDATE_FAIL~;
    })) {
        assert(err == UPDATE_FAIL, "Atom update should return UPDATE_FAIL");
    } else {
        unreachable("Atom update should fault");
    }

    atom_int.set_value(2)!!;

    assert(atom_int.try_get()!! == 2, "Atom should be usable after update fault");

    atom_int.destroy()!!;
}

fn void atom_unsubscribe_inside_callback() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    int* hits = mem::alloc(int);
    *hits = 0;

    SubCtx* ctx = mem::new(SubCtx, { .sub = null, .hits = hits });
    Subscription sub;
    ctx.sub = &sub;

    sub = atom_int.subscribe(fn void(int* new_value, any ctx_any) {
        SubCtx* ctx = (SubCtx*)ctx_any;
        *ctx.hits = *ctx.hits + 1;
        ctx.sub.unsubscribe()!!;
    }, ctx)!!;

    atom_int.set_value(2)!!;
    atom_int.set_value(3)!!;

    assert(*hits == 1, "Callback should run once after self-unsubscribe");

    mem::free(ctx);
    mem::free(hits);
    atom_int.destroy()!!;
}

fn void atom_unsubscribe_middle_keeps_others() {
    Atom{int}* atom_int = atom::new_with_value{int}(1)!!;

    int* hit_a = mem::alloc(int);
    int* hit_b = mem::alloc(int);
    int* hit_c = mem::alloc(int);
    *hit_a = 0;
    *hit_b = 0;
    *hit_c = 0;

    Subscription sub_a = atom_int.subscribe(fn void(int* new_value, any ctx) {
        int* hit = (int*)ctx;
        *hit = *hit + 1;
    }, hit_a)!!;

    Subscription sub_b = atom_int.subscribe(fn void(int* new_value, any ctx) {
        int* hit = (int*)ctx;
        *hit = *hit + 1;
    }, hit_b)!!;

    Subscription sub_c = atom_int.subscribe(fn void(int* new_value, any ctx) {
        int* hit = (int*)ctx;
        *hit = *hit + 1;
    }, hit_c)!!;

    sub_b.unsubscribe()!!;

    atom_int.set_value(2)!!;

    assert(*hit_a == 1, "Subscriber A should be called");
    assert(*hit_b == 0, "Subscriber B should not be called after unsubscribe");
    assert(*hit_c == 1, "Subscriber C should be called");

    sub_a.unsubscribe()!!;
    sub_c.unsubscribe()!!;

    mem::free(hit_a);
    mem::free(hit_b);
    mem::free(hit_c);
    atom_int.destroy()!!;
}
