
module atom::contracts;

interface Observer {
	fn void! update();
}

interface Subscription {
	fn void! unsubscribe();
}

interface Observable {
	fn Subscription! observe(Observer observer);
}

module atom::contracts::typed(<Type>);

import atom::contracts;

def SubscribeCallback = fn void(Type* new_value, any ctx = null);

interface Subscribable {
    fn Subscription! subscribe(SubscribeCallback callback, any ctx = null);
}

interface Readable : Subscribable {
    fn Type*! get();
    fn Type! try_get();   
}

def Updater = fn Type*!(Type* state, any ctx);

interface Writable {
    fn void! update(Updater(<Type>) updater, any ctx = null);
    fn void! set_value(Type new_value);
}