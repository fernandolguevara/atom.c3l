module atom::subscriptions::test @test;

import std::thread;
import std::atomic;

import atom::contracts;
import atom::subscriptions;
import atom::test_helpers;

faultdef OBSERVER_FAIL;

struct TestObserver (Observer) {
    int* hits;
    bool fail;
}

struct SelfUnsubObserver (Observer) {
    Subscription* sub;
    int* hits;
}

fn void? TestObserver.update(&self) @dynamic {
    *self.hits = *self.hits + 1;
    if (self.fail) {
        return OBSERVER_FAIL~;
    }
}

fn void? SelfUnsubObserver.update(&self) @dynamic {
    *self.hits = *self.hits + 1;
    self.sub.unsubscribe()!!;
}

fn void notify_fault_does_not_skip_other_observers() {
    SubscriptionState state;
    subscriptions::init(&state)!!;

    int* hits_a = mem::alloc(int);
    int* hits_b = mem::alloc(int);
    *hits_a = 0;
    *hits_b = 0;

    TestObserver* observer_a = mem::new(TestObserver, { .hits = hits_a, .fail = true });
    TestObserver* observer_b = mem::new(TestObserver, { .hits = hits_b, .fail = false });

    subscriptions::add(&state, observer_a, fn void(void* observer) { mem::free(observer); })!!;
    subscriptions::add(&state, observer_b, fn void(void* observer) { mem::free(observer); })!!;

    if (catch err = subscriptions::notify(&state)) {
        assert(err == OBSERVER_FAIL, "Notify should surface observer fault");
    } else {
        unreachable("Notify should have faulted");
    }

    assert(*hits_a == 1, "Failing observer should be invoked");
    assert(*hits_b == 1, "Other observers should still run");

    observer_a.fail = false;
    subscriptions::notify(&state)!!;

    assert(*hits_a == 2, "Observer should run after fault clears");
    assert(*hits_b == 2, "Other observer should continue running");

    subscriptions::deinit(&state)!!;
    mem::free(hits_a);
    mem::free(hits_b);
}

fn void notify_no_observers_is_noop() {
    SubscriptionState state;
    subscriptions::init(&state)!!;

    subscriptions::notify(&state)!!;

    subscriptions::deinit(&state)!!;
}

fn void once_unsubscribe_before_notify() {
    SubscriptionState state;
    subscriptions::init(&state)!!;

    int* hits = mem::alloc(int);
    *hits = 0;

    TestObserver* observer = mem::new(TestObserver, { .hits = hits, .fail = false });
    Subscription sub = subscriptions::once(&state, observer, fn void(void* obs) { mem::free(obs); })!!;

    sub.unsubscribe()!!;
    subscriptions::notify(&state)!!;

    assert(*hits == 0, "Observer should not be called after unsubscribe");

    subscriptions::deinit(&state)!!;
    mem::free(hits);
}

fn void unsubscribe_inside_notify() {
    SubscriptionState state;
    subscriptions::init(&state)!!;

    int* hits_a = mem::alloc(int);
    int* hits_b = mem::alloc(int);
    *hits_a = 0;
    *hits_b = 0;

    SelfUnsubObserver* observer_a = mem::new(SelfUnsubObserver, { .sub = null, .hits = hits_a });
    Subscription sub_a = subscriptions::add(&state, observer_a, fn void(void* obs) { mem::free(obs); })!!;
    observer_a.sub = &sub_a;

    TestObserver* observer_b = mem::new(TestObserver, { .hits = hits_b, .fail = false });
    subscriptions::add(&state, observer_b, fn void(void* obs) { mem::free(obs); })!!;

    subscriptions::notify(&state)!!;

    assert(*hits_a == 1, "Self-unsubscribing observer should run once");
    assert(*hits_b == 1, "Other observer should still run");

    subscriptions::notify(&state)!!;

    assert(*hits_a == 1, "Self-unsubscribed observer should not run again");
    assert(*hits_b == 2, "Remaining observer should keep running");

    subscriptions::deinit(&state)!!;
    mem::free(hits_a);
    mem::free(hits_b);
}

fn void notify_and_churn_concurrently() {
    SubscriptionState state;
    subscriptions::init(&state)!!;

    Atomic{int} hits;
    hits.store(0, RELAXED);

    test_helpers::AtomicObserver* observer = mem::new(test_helpers::AtomicObserver, { .hits = &hits });
    subscriptions::add(&state, observer, fn void(void* obs) { mem::free(obs); })!!;

    Atomic{bool} stop;
    stop.store(false, RELAXED);

    test_helpers::SubNotifyArgs notify_args = { .state = &state, .iterations = 2000, .stop = &stop };
    test_helpers::SubChurnArgs churn_args = { .state = &state, .iterations = 1000, .hits = &hits };

    Thread notifier;
    Thread churner;
    notifier.create(&test_helpers::subscriptions_notify_loop, &notify_args)!!;
    churner.create(&test_helpers::subscriptions_churn_loop, &churn_args)!!;

    notifier.join()!!;
    churner.join()!!;

    assert(hits.load(RELAXED) >= 0, "Hits should be non-negative");

    subscriptions::deinit(&state)!!;
}
