module atom::test_helpers;

import std::thread;
import std::atomic;

import atom::contracts;
import atom::subscriptions;
import atom::sync;

struct AtomicObserver (Observer) {
    Atomic{int}* hits;
}

fn void? AtomicObserver.update(&self) @dynamic {
    self.hits.add(1, RELAXED);
}

struct SubNotifyArgs {
    SubscriptionState* state;
    int iterations;
    Atomic{bool}* stop;
}

struct SubChurnArgs {
    SubscriptionState* state;
    int iterations;
    Atomic{int}* hits;
}

fn int subscriptions_notify_loop(void* arg) {
    SubNotifyArgs* args = (SubNotifyArgs*)arg;
    for (int i = 0; i < args.iterations; i++) {
        if (args.stop != null && args.stop.load(RELAXED)) {
            break;
        }
        subscriptions::notify(args.state)!!;
    }
    return 0;
}

fn int subscriptions_churn_loop(void* arg) {
    SubChurnArgs* args = (SubChurnArgs*)arg;
    for (int i = 0; i < args.iterations; i++) {
        AtomicObserver* observer = mem::new(AtomicObserver, { .hits = args.hits });
        Subscription sub = subscriptions::add(args.state, observer, fn void(void* obs) { mem::free(obs); })!!;
        sub.unsubscribe()!!;
        if ((i % 4) == 0) {
            thread::yield();
        }
    }
    return 0;
}

struct SyncLockReleaseArgs {
    Atomic{bool}* lock;
    Atomic{bool}* cleared;
}

fn int sync_release_lock_after_delay(void* arg) {
    SyncLockReleaseArgs* args = (SyncLockReleaseArgs*)arg;
    for (int i = 0; i < 2000; i++) {
        thread::yield();
    }
    args.lock.clear(RELEASE);
    args.cleared.store(true, RELAXED);
    return 0;
}
