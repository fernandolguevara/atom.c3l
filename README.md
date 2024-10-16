# atom.c3l

The **atom.c3l** is a lightweight, reactive state management system designed to handle mutable states efficiently. It uses **atoms** as fundamental units to store and manage data, enabling a declarative approach to building responsive, reactive applications. Atoms encapsulate values and allow you to react to their changes through subscriptions and derivations, making it ideal for modern reactive programming patterns.

# Examples

## Atom

```c++
import std::io, atom;

fn void! main(String[] args) {
    Atom(<int>)* counter = atom::new_with_value(<int>)(0)!;

    // Subscribe to the counter atom
    counter.subscribe(fn void(int* new_value, any ctx) {
        io::printfn("Counter updated to: %d" + *new_value);
    })!;

    // Set a new value for the counter
    counter.set_value(10)!;  // Output: "Counter updated to: 10"
}
```

### Derived

```c++
module app;
import std::io, atom;

fn void! main(String[] args) {
    Atom(<int>)* count = atom::new_with_value(<int>)(5)!;

    // Create a derived atom that doubles the value of `count`
    contracts::typed::Readable(<int>) double_count = atom::derived(<int>)(
        {count},  // source atom
        fn void!(int* writable, any[] sources, any ctx) {
            Atom(<int>)* count_atom = (Atom(<int>)*)sources[0];
            *writable = count_atom.try_get()! * 2;
        }
    )!;

    io::printfn("Double count: %d", double_count.try_get()!!);  // Output: "Double count: 10"

    // Change the value of `count`
    count.set_value(7)!;  // double_count now holds 14

    io::printfn("Double count: %d", double_count.try_get()!!);  // Output: "Double count: 14"
}
```

### Sync

```c++
module app;
import std::io, atom;

fn void! main(String[] args) {
    Atom(<float>)* celsius = atom::new_with_value(<float>)(25.0)!;
    Atom(<float>)* fahrenheit = atom::new_with_value(<float>)((25.0 * 9.0 / 5.0) + 32.0)!;

    // Synchronize atoms to keep Celsius and Fahrenheit in sync
    Observable sync_signal = sync::new(<float, float>)(
        celsius, 
        fahrenheit, 
        fn float! (float* c, any ctx) {
            return (*c * 9.0 / 5.0) + 32.0;
        },
        fn float! (float* f, any ctx) {
            return (*f - 32.0) * 5.0 / 9.0;
        }
    )!;


    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 25.00"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 77.00"

    celsius.set_value(30.0)!;   // fahrenheit is automatically updated to 86.0

    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 30.00"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 86.00"

    fahrenheit.set_value(100.0)!;  // celsius is automatically updated to 37.777...

    io::printfn("celsius: %.2f", celsius.try_get()!!); // Output: "celsius: 37.78"
    io::printfn("fahrenheit: %.2f", fahrenheit.try_get()!!); // Output: "fahrenheit: 100.00"
}
```