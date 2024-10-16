module atom(<Type>);

import std::thread, atom::subscriptions;

fault AtomError {
    EMPTY,
    INITIALIZATION_FAILED,
    SUBSCRIBER_ALREADY_REGISTERED
}

struct Atom (Observable, contracts::typed::Readable(<Type>), contracts::typed::Writable(<Type>), contracts::typed::Subscribable(<Type>)) {
    Mutex mu;
	Type* v;
}

struct AtomObserverWithCallback (Observer) {
	Atom(<Type>)* atom;
	SubscribeCallback(<Type>) callback;
	any ctx;
}

fn void! AtomObserverWithCallback.update(&self) @dynamic {
	self.callback(self.atom.get()!, self.ctx);
}

fn Observer observe(Atom(<Type>)* atom, SubscribeCallback(<Type>) callback, any ctx = null) {
	AtomObserverWithCallback* observer = mem::new(AtomObserverWithCallback, {
		.atom = atom,
		.callback = callback,
		.ctx = ctx,
	});
	return  observer;
}

fn Atom*! new(Type* initial_value = null) {
    Atom* atom = mem::new(Atom, { .v = initial_value });

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

fn Subscription! Atom.subscribe(&self, SubscribeCallback(<Type>) callback, any ctx = null) @dynamic {
	Observer observer = observe(self, callback, ctx);

	return self.observe(observer);
}

fn Subscription! Atom.observe(&self, Observer observer) @dynamic {
	return subscriptions::new(self, observer);
}

fn Type! Atom.try_get(&self) @dynamic {
    self.mu.lock()!;
    
    Type* value = self.v;    
    
    self.mu.unlock()!;

    if(null == value){
        return AtomError.EMPTY?;
    }

    return *value;
} 

fn Type*! Atom.get(&self) @dynamic {
    self.mu.lock()!;
    
    Type* value = self.v;    
    
    self.mu.unlock()!;

    return value;
}

fn void! Atom.set(&self, Type* new_value)  @dynamic {
    self.mu.lock()!;
    
    Type* old_value = self.v;
    self.v = new_value;
    
    self.mu.unlock()!;
    
    subscriptions::notify(self)!;
} 

fn void! Atom.set_value(&self, Type value) @dynamic {  
    Type* next_value = mem::alloc(Type);
    *next_value = value;

    self.set(next_value)!;
}

fn void! Atom.update(&self, typed::Updater(<Type>) updater, any ctx = null)  @dynamic {
    self.mu.lock()!;
    
    Type* state = self.v;
    Type* new_state = updater(state, ctx)!;
    self.v = new_state;
    
    self.mu.unlock()!;

    subscriptions::notify(self)!;
}

fn void! Atom.clear(&self) {
    self.set(null)!;
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

    subscriptions::remove(self)!;

    mem::free(self);
}
 