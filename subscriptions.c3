module atom(<Type>) @private;

import
    std::thread @norecurse,
    std::collections::list @norecurse,
    std::collections::map @norecurse
;

def Subscriber = fn void!(void* ctx, Type* old_value, Type* new_value);
def Subscriptions = HashMap(<void*, void*>);

struct AtomEntry { 
    Subscriptions subscriptions;
    Mutex mu;
}

def AtomKey = void*;
def AtomSubscriptions = HashMap(<AtomKey, AtomEntry*>);

AtomSubscriptions global_subscriptions @noinit;

fn void init() @init {
    global_subscriptions.new_init();
}

fn void! Atom.notify_subscribers(&self, Type* old_value, Type* new_value) {
    AtomKey atom_key = self.key();

    if (!global_subscriptions.has_key(atom_key)) {
        return;
    }

    AtomEntry* entry = global_subscriptions.get(atom_key)!;

    if(entry.subscriptions.is_empty()) {
        return;
    }

    entry.mu.lock()!;

    entry.subscriptions.@each(;Subscriber subscriber, void* ctx) {
        subscriber(ctx, old_value, new_value)!;
    };

    entry.mu.unlock()!; 
}

fn AtomKey Atom.key(&self) {
    void* ptr = self;
    return ptr;
}

module atom(<Type>);

import std::thread;

fn void! Atom.subscribe(&self, Subscriber subscriber, void* ctx = null) {
    AtomKey atom_key = self.key();

    AtomEntry* entry;
    if(!global_subscriptions.has_key(atom_key)) {   
        entry = mem::new(AtomEntry);
        if(catch err = entry.mu.init()){
            mem::free(entry);
            return err?;
        }
        entry.subscriptions.new_init();
        global_subscriptions[atom_key] = entry;
    } else {
        entry = global_subscriptions.get(atom_key)!;
    }
  
    if (entry.subscriptions.has_key(subscriber)) {
        return AtomError.SUBSCRIBER_ALREADY_REGISTERED?;
    }
    
    entry.mu.lock()!;

    entry.subscriptions[subscriber] = ctx;
    
    entry.mu.unlock()!;
}

fn void! Atom.unsubscribe(&self, Subscriber subscriber) {
    AtomKey atom_key = self.key();

    if (!global_subscriptions.has_key(atom_key)) {
        return;
    }

    AtomEntry* entry = global_subscriptions.get(atom_key)!;

    if(entry.subscriptions.is_empty()) {
        return;
    }

    entry.mu.lock()!; 

    entry.subscriptions.remove(subscriber);

    entry.mu.unlock()!;
}