module atom(<Type>);

import
    std::thread @norecurse, 
    std::thread::os @norecurse;

def Setter = fn Type*!(Type* old_value, Type* new_value);

fn Type*! default_setter(Type* old, Type* new) @private {
    return new;
}

struct Atom {    
    Type* v;
    Mutex mu;
}

fault AtomError {
    INITIALIZATION_FAILED,
    SUBSCRIBER_ALREADY_REGISTERED
}

fn Atom*! new(Type* initial_value = null) {
    Atom* atom = mem::new(Atom, {.v = initial_value});

    if (catch atom.mu.init()) {
        mem::free(atom);
        return AtomError.INITIALIZATION_FAILED?;
    }

    return atom;
}

fn Atom*! new_with_value(Type value) {
    Type* initial_value = mem::alloc(Type);
    
    *initial_value = value;

    return new(initial_value);
}

fn void! Atom.clear(&self) {
    self.set(&default_setter, null)!;
}

fn bool! Atom.is_empty(&self) {
    return null == self.get();
}

fn void! Atom.destroy(&self) {
    NativeMutex nmu = (NativeMutex)self.mu;
    if(!nmu.is_initialized()){
        return;
    }

    self.mu.lock()!;
    mem::free(self.v);
    self.mu.unlock()!;
    
    self.mu.destroy()!;

    AtomKey atom_key = self.key();
    if (global_subscriptions.has_key(atom_key)) {
        AtomEntry* entry = global_subscriptions.get(atom_key)!;
        entry.subscriptions.clear();
        mem::free(entry);
        global_subscriptions.remove(atom_key);
    }

    mem::free(self);
}

fn Type*! Atom.get(&self) {
    self.mu.lock()!;
    
    Type* value = self.v;    
    
    self.mu.unlock()!;

    return value;
} 

fn void! Atom.set(&self, Setter setter, Type* value) {
    self.mu.lock()!;
    
    Type* old_value = self.v;
    Type* new_value = setter(old_value, value)!;
    self.v = new_value;

    self.notify_subscribers(old_value, new_value)!;

    self.mu.unlock()!;
} 

fn void! Atom.set_value(&self, Type value) {  
    Type* next_value = mem::alloc(Type);
    *next_value = value;

    self.set(&default_setter, next_value)!;
}
