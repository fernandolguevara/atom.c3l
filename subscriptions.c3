module atom::subscriptions;

import std::thread, std::collections::map, std::collections::list, atom::contracts;

fn SubscriptionKey Observable.key(&self) {
    return self.ptr.hash();
}

struct ObserverEntry (Subscription) {
	SubscriptionKey subscription_key;
	Observer observer;
}

fn void! ObserverEntry.unsubscribe(&self) @dynamic {
	if(!subscription_registry.has_key(self.subscription_key)) {
		return;
	}

	SubscriptionEntry* entry = subscription_registry[self.subscription_key]!;

    if(entry.observers.is_empty()) {
        return;
    }
    
	entry.mu.lock()!;

	for(int i = (int)entry.observers.len() - 1; i >= 0; --i) {		
		if(entry.observers[i].observer.ptr == self.observer.ptr) {
			entry.observers.remove_at(i);
		}	
	}

    entry.mu.unlock()!;

	if(entry.observers.is_empty()) {
		subscription_registry.remove(self.subscription_key);
    	entry.mu.destroy()!;
		mem::free(entry);
		*entry = {};
    }

	mem::free(self);
	*self = {};
}

def Observers = List(<ObserverEntry*>);

def SubscriptionKey = uint;

struct SubscriptionEntry  {
	SubscriptionKey key;
	Observers observers;
	Mutex mu;
}

HashMap(<SubscriptionKey, SubscriptionEntry*>) subscription_registry;

fn void init_atom_subscriptions() @init {
    subscription_registry.new_init();
}

fn Subscription! new(Observable observable, Observer observer) {
	SubscriptionKey subscription_key = observable.key();

	SubscriptionEntry* entry;
	
	if(!subscription_registry.has_key(subscription_key)) {
 		entry = mem::new(SubscriptionEntry);
        if(catch err = entry.mu.init()){
            mem::free(entry);
            return err?;
        }
        entry.observers.new_init();
        subscription_registry[subscription_key] = entry;
	} else {
		entry = subscription_registry[subscription_key]!;
	}

	ObserverEntry* observer_entry = mem::new(ObserverEntry, {
		.subscription_key = subscription_key,
		.observer = observer,
	});

	entry.observers.push(observer_entry);

	return observer_entry;
}

fn void! notify(Observable observable) {
	SubscriptionKey subscription_key = observable.key();

	if(!subscription_registry.has_key(subscription_key)) {
		return;
	}

	SubscriptionEntry* entry = subscription_registry[subscription_key]!;

	if(entry.observers.is_empty()) {
        return;
    }

    entry.mu.lock()!;

    foreach (observer_entry : entry.observers) {
		observer_entry.observer.update()!;
    };

    entry.mu.unlock()!; 
}

fn void! remove(Observable observable) {
	SubscriptionKey subscription_key = observable.key();
    
    if (subscription_registry.has_key(subscription_key)) {
        SubscriptionEntry* entry = subscription_registry[subscription_key]!;
        entry.observers.clear();
        mem::free(entry);
        subscription_registry.remove(subscription_key);
    }    
}