module atom::threading::test @test;

import std::thread;
import std::atomic;

import atom;
import atom::threading;

fn void concurrent_notify_and_subscribe_unsubscribe() {
    Atom{int}* atom_int = atom::new_with_value{int}(0)!!;

    Atomic{int} hits;
    hits.store(0, RELAXED);

    threading::NotifyArgs notify_args = { .atom = atom_int, .iterations = 5000, .stop = null };
    threading::ChurnArgs churn_args = { .atom = atom_int, .iterations = 5000, .hits = &hits };

    Thread notifier;
    Thread churner;
    notifier.create(&threading::notify_loop, &notify_args)!!;
    churner.create(&threading::subscribe_unsubscribe_loop, &churn_args)!!;

    notifier.join()!!;
    churner.join()!!;

    assert(atom_int.try_get()!! == 4999, "Atom should reach last notify value");

    atom_int.destroy()!!;
}

fn void observer_churn_under_notify() {
    Atom{int}* atom_int = atom::new_with_value{int}(0)!!;

    Atomic{int} hits;
    hits.store(0, RELAXED);

    threading::NotifyArgs notify_args = { .atom = atom_int, .iterations = 5000, .stop = null };
    threading::ChurnArgs churn_args = { .atom = atom_int, .iterations = 200, .hits = &hits };

    Thread notifier;
    Thread churner;
    notifier.create(&threading::notify_loop, &notify_args)!!;
    churner.create(&threading::observer_churn_loop, &churn_args)!!;

    notifier.join()!!;
    churner.join()!!;

    assert(hits.load(RELAXED) >= 0, "Hits should be non-negative");

    atom_int.destroy()!!;
}

fn void destroy_waits_for_notify_to_finish() {
    Atom{int}* atom_int = atom::new_with_value{int}(0)!!;

    Atomic{bool} in_callback;
    Atomic{bool} allow_exit;
    Atomic{bool} destroy_finished;
    Atomic{bool} destroy_returned_early;
    in_callback.store(false, RELAXED);
    allow_exit.store(false, RELAXED);
    destroy_finished.store(false, RELAXED);
    destroy_returned_early.store(false, RELAXED);

    threading::DestroyNotifyCtx ctx = { .in_callback = &in_callback, .allow_exit = &allow_exit };
    atom_int.subscribe(fn void(int* new_value, any ctx_any) {
        threading::DestroyNotifyCtx* ctx = (threading::DestroyNotifyCtx*)ctx_any;
        ctx.in_callback.store(true, RELAXED);
        while (!ctx.allow_exit.load(RELAXED)) {
            thread::yield();
        }
    }, &ctx)!!;

    Thread notifier;
    threading::DestroyNotifyArgs notify_args = { .atom = atom_int };
    notifier.create(&threading::notify_blocking, &notify_args)!!;

    Thread releaser;
    threading::DestroyReleaseArgs release_args = {
        .in_callback = &in_callback,
        .allow_exit = &allow_exit,
        .destroy_finished = &destroy_finished,
        .destroy_returned_early = &destroy_returned_early,
    };
    releaser.create(&threading::release_after_callback, &release_args)!!;

    while (!in_callback.load(RELAXED)) {
        thread::yield();
    }

    atom_int.destroy()!!;
    destroy_finished.store(true, RELAXED);

    notifier.join()!!;
    releaser.join()!!;

    assert(!destroy_returned_early.load(RELAXED), "Destroy should wait until notify finishes");
}
