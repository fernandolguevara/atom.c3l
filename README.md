# atom for c3 

based on clojure atom

## Example
```c++
import atom;
import std::io;

def AtomInt = Atom(<int>);

fn void on_atom_change(int* old_value, int* new_value) {
    io::printfn("on_change old_value: %s, new_value: %s", *old_value, new_value != null ? string::tformat("%s", (*new_value)) : "null");
}

fn void! main(String[] args) {
    AtomInt* atom = atom::new_with_value(<int>)(1)!; 

    atom.subscribe(&on_atom_change)!;

    assert(@catch(atom.subscribe(&on_atom_change)), "Atom 2nd subscribe should fail");

    int* v = atom.get()!;

    io::printfn("atom_value: %s, atom_is_empty: %s", *v, atom.is_empty()!);

    atom.set_value(2)!;

    v = atom.get()!;

    io::printfn("atom_value: %s, atom_is_empty: %s", *v, atom.is_empty()!);

    atom.clear()!;

    v = atom.get()!;

    io::printfn("atom_is_empty: %s", atom.is_empty()!);   

    atom.unsubscribe(&on_atom_change)!;

    atom.unsubscribe(&on_atom_change)!;

    atom.set_value(11)!;

    v = atom.get()!;

    io::printfn("atom_value: %s, atom_is_empty: %s", *v, atom.is_empty()!);

  /*
  OUTPUT:
    atom_value: 1, atom_is_empty: false
    on_change old_value: 1, new_value: 2
    atom_value: 2, atom_is_empty: false
    on_change old_value: 2, new_value: null
    atom_is_empty: true
    atom_value: 11, atom_is_empty: false
  */
}
```