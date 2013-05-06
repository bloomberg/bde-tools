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
    }
}
