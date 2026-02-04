# atom.c3l

The **atom.c3l** is a lightweight, reactive state management system designed to handle mutable states efficiently. It uses **atoms** as fundamental units to store and manage data, enabling a declarative approach to building responsive, reactive applications. Atoms encapsulate values and allow you to react to their changes through subscriptions and derivations, making it ideal for modern reactive programming patterns. Atom instances own their stored values and update by value to keep ownership simple. Call `destroy()` when you are done to release resources.

## Ownership, Lifetimes, and Threading

- `SyncAtoms` does not own `atom_a` or `atom_b`; callers are responsible for destroying those atoms.
- `Atom.get()` returns a pointer that may become invalid after concurrent updates, `clear()`, or `destroy()`; use `try_get()` or copy the value if you need a stable snapshot.
- Subscription callbacks receive a pointer to the atom value with the same lifetime caveat; copy the value if you need it beyond the callback.
- Prefer `subscribe_value()` when you want a snapshot copy; it skips notifications when the atom is empty.
- `subscriptions::notify()` invokes all observers even if one faults, and returns the first fault.
- `subscriptions::remove_all()` and `subscriptions::deinit()` wait for in-flight notifications to finish; observer callbacks should be non-blocking.

# Examples

## Atom

```c++
import std::io, atom;

fn void! main(String[] args) {
    Atom{int}* counter = atom::new_with_value{int}(0)!!;

    // Subscribe to the counter atom
    counter.subscribe(fn void(int* new_value, any ctx) {
        io::printfn("Counter updated to: %d", *new_value);
    })!!;

    // Subscribe once
    counter.subscribe_once(fn void(int* new_value, any ctx) {
        io::printfn("Counter updated once: %d", *new_value);
    })!!;

    // Set a new value for the counter
    counter.set_value(10)!!;  // Output: "Counter updated to: 10"

    counter.with_lock(fn void(int* value, any ctx) {
        *value = *value + 5;
    })!!;

    counter.reset(0)!!;

    counter.destroy()!!;
}
```

### Derived

```c++
module app;
import std::io, atom;
import atom::sync;

fn void! main(String[] args) {
    Atom{int}* count = atom::new_with_value{int}(5)!!;

    // Create a derived atom that doubles the value of `count`
    Derived{int}* double_count = atom::derived{int}(
        {count},  // source atom
        fn void?(int* writable, any[] sources, any ctx) {
            Atom{int}* count_atom = (Atom{int}*)sources[0];
            *writable = count_atom.try_get()!! * 2;
        }
    )!!;

    io::printfn("Double count: %d", double_count.try_get()!!);  // Output: "Double count: 10"

    // Change the value of `count`
    count.set_value(7)!!;  // double_count now holds 14

    io::printfn("Double count: %d", double_count.try_get()!!);  // Output: "Double count: 14"

    count.destroy()!!;
    double_count.destroy()!!;
}
```

### Derived With Signal-Only Updates

Use the `signal` parameter when you want a derived value to refresh only when a separate observable fires.

```c++
module app;
import std::io, atom;

fn void! main(String[] args) {
    Atom{int}* count = atom::new_with_value{int}(5)!!;
    Atom{int}* signal = atom::new_with_value{int}(0)!!;

    Derived{int}* double_count = atom::derived{int}(
        {count},
        fn void?(int* writable, any[] sources, any ctx) {
            Atom{int}* count_atom = (Atom{int}*)sources[0];
            *writable = count_atom.try_get()!! * 2;
        },
        null,
        (Observable)signal
    )!!;

    count.set_value(7)!!;
    io::printfn("Double count (unchanged): %d", double_count.try_get()!!);

    signal.set_value(1)!!; // triggers refresh
    io::printfn("Double count (updated): %d", double_count.try_get()!!);

    count.destroy()!!;
    signal.destroy()!!;
    double_count.destroy()!!;
}
```

### Reducer Faults

Reducers are allowed to fault. On fault, the derived value is not updated, and the fault propagates to the caller that triggered the update.

```c++
module app;
import std::io, atom;

faultdef REDUCER_FAIL;

fn void! main(String[] args) {
    Atom{int}* count = atom::new_with_value{int}(1)!!;

    Derived{int}* double_count = atom::derived{int}(
        {count},
        fn void?(int* writable, any[] sources, any ctx) {
            Atom{int}* count_atom = (Atom{int}*)sources[0];
            int value = count_atom.try_get()!!;
            if (value == 2) {
                return REDUCER_FAIL~;
            }
            *writable = value * 2;
        }
    )!!;

    if (catch err = count.set_value(2)) {
        io::printfn("Reducer fault: %s", err);
    }

    count.destroy()!!;
    double_count.destroy()!!;
}
```

### Sync

```c++
module app;
import std::io, atom;

fn void! main(String[] args) {
    Atom{float}* celsius = atom::new_with_value{float}(25.0)!!;
    Atom{float}* fahrenheit = atom::new_with_value{float}((25.0 * 9.0 / 5.0) + 32.0)!!;

    // Synchronize atoms to keep Celsius and Fahrenheit in sync
    SyncAtoms{float, float}* sync_signal = sync::new{float, float}(
        celsius, 
        fahrenheit, 
        fn float(float* c, any ctx) {
            return (*c * 9.0 / 5.0) + 32.0;
        },
        fn float(float* f, any ctx) {
            return (*f - 32.0) * 5.0 / 9.0;
        }
    )!!;

    // Optional: pass an error callback as the final argument to handle conversion faults.


    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 25.00"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 77.00"

    celsius.set_value(30.0)!!;   // fahrenheit is automatically updated to 86.0

    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 30.00"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 86.00"

    fahrenheit.set_value(100.0)!!;  // celsius is automatically updated to 37.777...

    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 37.78"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 100.00"

    // TWO_WAY initial sync is deterministic: A -> B on creation
    // destroy() waits for any in-flight conversion to finish

    sync::destroy(sync_signal)!!;
}
```
