
module atom(<Type>);

import atom::contracts::typed;

def Reducer = fn void!(Type* writable, any[] source_atoms, any ctx = null);

struct Derived (contracts::typed::Readable(<Type>), Observer) {
    Atom* atom;
    Observable signal;
    any[] source_atoms;
    Reducer reducer;
    any ctx;
}

fn contracts::typed::Readable(<Type>)! derived(any[] source_atoms, Reducer reducer, Type* initial_value = null, Observable signal = null, any ctx = null) {
    if(initial_value == null) {
        initial_value = mem::new(Type);
        reducer(initial_value, source_atoms, ctx)!;
    }

    Atom* atom = atom::new(<Type>)(initial_value)!;

    Derived* derived = mem::new(Derived, { 
        .atom = atom,
        .reducer = reducer,
        .source_atoms = source_atoms,
        .signal = signal,
        .ctx = ctx,
    });
    
    derived.init()!;

    return derived;
}

fn void! Derived.update(&self) @dynamic => self.refresh()!;

fn Type! Derived.try_get(&self) @dynamic => self.atom.try_get()!;
fn Type*! Derived.get(&self) @dynamic => self.atom.get()!;

fn Subscription! Derived.subscribe(&self, SubscribeCallback(<Type>) callback, any ctx = null) @dynamic => self.atom.subscribe(callback, ctx);
fn Subscription! Derived.observe(&self, Observer observer) @dynamic => self.atom.observe(observer);

fn void! Derived.init(&self) @private {
    if(self.signal) {
        self.signal.observe(self)!;
    } else {
        foreach(source_atom: self.source_atoms) {     
            Observable observable = (Observable)source_atom;
            observable.observe(self)!;
        }        
    }
}

fn void! Derived.refresh(&self) @private {
    Type* writable = mem::new(Type);
    self.reducer(writable, self.source_atoms, ctx: self.ctx)!;
    self.atom.set(writable)!;
}