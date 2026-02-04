
module atom::contracts;

interface Observer {
    fn void? update();
}

interface Subscription {
    fn void? unsubscribe();
}

interface Observable {
    fn Subscription? observe(Observer observer);
    fn void? destroy();
}

module atom::contracts::typed<Type>;

import atom::contracts;

alias SubscribeCallback = fn void(Type* new_value, any ctx = null);
alias SubscribeValueCallback = fn void(Type new_value, any ctx = null);

interface Subscribable {
    fn Subscription? subscribe(SubscribeCallback callback, any ctx = null);

    // Atom provides subscribe_value/try_copy as concrete helpers.

    fn void? destroy();
}

interface Readable : Subscribable {
    fn Type*? get();
    fn Type? try_get();
}

alias Updater = fn Type?(Type* state, any ctx);

alias Locker = fn void(Type* state, any ctx = null);

interface Writable {
    fn void? update(Updater{Type} updater, any ctx = null);
    fn void? set_value(Type new_value);
    fn void? reset(Type new_value);
    fn void? with_lock(Locker{Type} locker, any ctx = null);
}
