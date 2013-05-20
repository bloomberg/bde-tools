#include <tst_test2.h>

void woof()
{
    bcemt_LockGuard<bcemt_Mutex>  guard;
    bcemt::LockGuard<bcemt_Mutex> guard;

    bcemt_LockGuard<bcemt_Mutex>();    // 8
    bcemt::LockGuard<bcemt_Mutex>();   // 9

    bcemt_LockGuard  guard;
    bcemt::LockGuard guard;

    bcemt_LockGuard();    // 14
    bcemt::LockGuard();   // 15

    bcemt_LockGuard&  guard;
    bcemt::LockGuard& guard;

    if (arf) {
        bcemt_LockGuard<bcemt_Mutex>  guard;
        bcemt::LockGuard<bcemt_Mutex> guard;

        bcemt_LockGuard<bcemt_Mutex>();    // 24
        bcemt::LockGuard<bcemt_Mutex>();   // 25

        bcemt_LockGuard  guard;
        bcemt::LockGuard guard;

        bcemt_LockGuard();    // 30
        bcemt::LockGuard();   // 31

        bcemt_LockGuard&  guard;
        bcemt::LockGuard& guard;

        bdema_ManagedPtr<Woof> woofPtr(&w);
        bdema::ManagedPtr<Woof> woofPtr(&w);

        bdema_ManagedPtr<Woof>();    // 39
        bdema::ManagedPtr<Woof>();   // 40

        bdema_ManagedPtr<Woof>  guard;
        bdema::ManagedPtr<Woof> guard;

        bdema_ManagedPtr();    // 45
        bdema::ManagedPtr();   // 46

        bcema_SharedPtr<Woof>  woofPtr(&w);
        bcema::SharedPtr<Woof> woofPtr(&w);

        bcema_SharedPtr<Woof>(&w);    // 51
        bcema::SharedPtr<Woof>(&w);   // 52

        bcema_SharedPtr<Woof>  woofPtr;
        bcema::SharedPtr<Woof> woofPtr;

        bcema_SharedPtr();    // 57
        bcema::SharedPtr();   // 58
    }
}
