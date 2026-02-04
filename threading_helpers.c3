module atom::threading;

import std::thread;
import std::atomic;
import std::collections;

import atom;

struct NotifyArgs {
    Atom{int}* atom;
    int iterations;
    Atomic{bool}* stop;
}

struct ChurnArgs {
    Atom{int}* atom;
    int iterations;
    Atomic{int}* hits;
}

struct DestroyNotifyCtx {
    Atomic{bool}* in_callback;
    Atomic{bool}* allow_exit;
}

struct DestroyNotifyArgs {
    Atom{int}* atom;
}

struct DestroyArgs {
    Atom{int}* atom;
    Atomic{bool}* done;
}

struct DestroyReleaseArgs {
    Atomic{bool}* in_callback;
    Atomic{bool}* allow_exit;
    Atomic{bool}* destroy_finished;
    Atomic{bool}* destroy_returned_early;
}

struct SyncBlockCtx {
    Atomic{bool}* in_conversion;
    Atomic{bool}* allow_exit;
}


fn int notify_loop(void* arg) {
    NotifyArgs* args = (NotifyArgs*)arg;
    for (int i = 0; i < args.iterations; i++) {
        if (args.stop != null && args.stop.load(RELAXED)) {
            break;
        }
        args.atom.set_value(i)!!;
    }
    return 0;
}

fn int subscribe_unsubscribe_loop(void* arg) {
    ChurnArgs* args = (ChurnArgs*)arg;
    for (int i = 0; i < args.iterations; i++) {
        Subscription sub = args.atom.subscribe(fn void(int* new_value, any ctx) {
            Atomic{int}* hits = (Atomic{int}*)ctx;
            hits.add(1, RELAXED);
        }, args.hits)!!;
        sub.unsubscribe()!!;
    }
    return 0;
}

fn int observer_churn_loop(void* arg) {
    ChurnArgs* args = (ChurnArgs*)arg;
    List{Subscription} subs;
    subs.init(mem);

    for (int i = 0; i < args.iterations; i++) {
        Subscription sub = args.atom.subscribe(fn void(int* new_value, any ctx) {
            Atomic{int}* hits = (Atomic{int}*)ctx;
            hits.add(1, RELAXED);
        }, args.hits)!!;
        subs.push(sub);

        if ((i % 4) == 0) {
            thread::yield();
        }
    }

    foreach (subscription : subs) {
        subscription.unsubscribe()!!;
    }
    subs.free();
    return 0;
}

fn int notify_blocking(void* arg) {
    DestroyNotifyArgs* args = (DestroyNotifyArgs*)arg;
    args.atom.set_value(1)!!;
    return 0;
}

fn int destroy_atom(void* arg) {
    DestroyArgs* args = (DestroyArgs*)arg;
    args.atom.destroy()!!;
    args.done.store(true, RELAXED);
    return 0;
}

fn int release_after_callback(void* arg) {
    DestroyReleaseArgs* args = (DestroyReleaseArgs*)arg;
    while (!args.in_callback.load(RELAXED)) {
        thread::yield();
    }

    for (int i = 0; i < 2000; i++) {
        if (args.destroy_finished.load(RELAXED)) {
            args.destroy_returned_early.store(true, RELAXED);
            break;
        }
        thread::yield();
    }

    args.allow_exit.store(true, RELAXED);
    return 0;
}
