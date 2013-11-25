// bcec_queue.h              -*-C++-*-
#ifndef INCLUDED_BCEC_QUEUE
#define INCLUDED_BCEC_QUEUE

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT("$Id: $")

//@PURPOSE: Provide a thread-enabled queue of items of parameterized 'TYPE'.
//
//@CLASSES:
//   bcec_Queue: thread-enabled 'bdec_Queue' wrapper
//
//@AUTHOR: Ilougino Rocha (irocha)
//
//@SEE_ALSO: bdec_queue
//
//@DESCRIPTION: This component provides a thread-enabled implementation of an
// efficient, in-place, indexable, double-ended queue of parameterized 'TYPE'
// values, namely the 'bcec_Queue<TYPE>' container.  'bcec_Queue' is
// effectively a thread-enabled handle for 'bdec_Queue', whose interface is
// also made available through 'bcec_Queue'.
//
///Thread-Enabled Idioms in the 'bcec_Queue' Interface
///---------------------------------------------------
// The thread-enabled 'bcec_Queue' is similar to 'bdec_Queue' in many regards,
// but there are several differences in method behavior and signature that
// arise due to the thread-enabled nature of the queue and its anticipated
// usage pattern.  Most notably, the 'popFront' and 'popBack' methods return a
// 'TYPE' object *by* *value*, rather than returning 'void', as 'bdec_Queue'
// does.  Moreover, if a queue object is empty, 'popFront' and 'popBack' will
// block indefinitely until an item is added to the queue.
//
// As a corollary to this behavior choice, 'bcec_Queue' also provides
// 'timedPopFront' and 'timedPopBack' methods.  These methods wait until a
// specified timeout expires if the queue is empty, returning an item if
// one becomes available before the specified timeout; otherwise, they return a
// non-zero value to indicate that the specified timeout expired before an
// item was available.  Note that *all* timeouts are expressed as values of
// type 'bdet_TimeInterval' that represent !ABSOLUTE! times from 00:00:00 UTC,
// January 1, 1970.
//
// The behavior of the 'push' methods differs in a similar manner.
// 'bcec_Queue' supports the notion of a suggested maximum queue size, called
// the "high-water mark", a value supplied at construction.  The 'pushFront'
// and 'pushBack' methods will block indefinitely if the queue contains (at
// least) the high-water mark number of items, until the number of items
// falls below the high-water mark.  The 'timedPushFront' and 'timedPushBack'
// are provided to limit the duration of blocking; note, however, that these
// methods can fail to add an item to the queue.  For this reason,
// 'bcec_Queue' also provides a 'forcePushFront' method that will override the
// high-water mark, if needed, in order to succeed without blocking.  Note that
// this design decision makes the high-water mark concept a suggestion and not
// an invariant.
//
///Use of the 'bdec_Queue' Interface
///---------------------------------
// Class 'bcec_Queue' provides access to an underlying 'bdec_Queue', so clients
// of 'bcec_Queue' have full access to the interface behavior of 'bdec_Queue'
// to inspect and modify the 'bcec_Queue'.
//
// Member function 'bcec_Queue::queue()' provides *direct* modifiable access to
// the 'bdec_Queue' object used in the implementation.  Member functions
// 'bcec_Queue::mutex()', 'bcec_Queue::notEmptyCondition()', and
// 'bcec_Queue::notFullCondition()' correspondingly provide *direct* modifiable
// access to the underlying 'bcemt_Mutex' and 'bcemt_Condition' objects
// respectively.  These underlying objects are used within 'bcec_Queue' to
// manage concurrent access to the queue.  Clients may use these member
// variables together if needed.
//
// Whenever accessing the 'bdec' queue directly, clients must be sure to lock
// and unlock the mutex or to signal or broadcast on the condition variable as
// appropriate.  For example, a client might use the underlying queue and mutex
// as follows:
//..
//     bcec_Queue<myData>  myWorkQueue;
//     bdec_Queue<myData>& rawQueue = myWorkQueue.queue();
//     bcemt_Mutex&        queueMutex = myWorkQueue.mutex();
//         // other code omitted...
//
//     myData  data1;
//     myData  data2;
//     bool pairFoundFlag = 0;
//     // Take two items from the queue atomically, if available.
//
//     queueMutex.lock();
//     if (rawQueue.length() >= 2) {
//         data1 = rawQueue.front();
//         rawQueue.popFront();
//         data2 = rawQueue.front();
//         rawQueue.popFront();
//         pairFound = 1;
//     }
//     queueMutex.unlock();
//
//     if (pairFoundFlag) {
//         // Process the pair
//     }
//..
// Note that a future version of this component will provide access to a
// thread-safe "smart pointer" that will manage the 'bdec_Queue' with respect
// to locking and signaling.  At that time, direct access to the 'bdec_Queue'
// will be deprecated.  In the meanwhile, the user should be careful to use the
// 'bdec_Queue' and the synchronization objects properly.
//
///Usage
///-----
///Example 1: Simple Thread Pool
///- - - - - - - - - - - - - - -
// The following example demonstrates a typical usage of a 'bcec_Queue'.
//
// This 'bcec_Queue' is used to communicate between a single "producer" thread
// and multiple "consumer" threads.  The "producer" will push work requests
// onto the queue, and each "consumer" will iteratively take a work request
// from the queue and service the request.  This example shows a partial,
// simplified implementation of the 'bcep_ThreadPool' class.  See component
// 'bcep_threadpool' for more information.
//
// We begin our example with some utility classes that define a simple "work
// item":
//..
// enum {
//     MAX_CONSUMER_THREADS = 10
// };
//
// struct my_WorkData {
//     // Work data...
// };
//
// struct my_WorkRequest {
//     enum RequestType {
//           WORK = 1
//         , STOP = 2
//     };
//
//     RequestType d_type;
//     my_WorkData d_data;
//     // Work data...
// };
//..
// Next, we provide a simple function to service an individual work item.
// The details are unimportant for this example.
//..
// void myDoWork(my_WorkData& data)
// {
//     // do some stuff...
// }
//..
// The 'myConsumer' function will pop items off the queue and process them.
// As discussed above, note that the call to 'queue->popFront()' will block
// until there is an item available on the queue.  This function will be
// executed in multiple threads, so that each thread waits in
// 'queue->popFront()', and 'bcec_Queue' guarantees that each thread gets a
// unique item from the queue.
//..
// void myConsumer(bcec_Queue<my_WorkRequest> *queue)
// {
//     while (1) {
//         // 'popFront()' will wait for a 'my_WorkRequest' until available.
//         my_WorkRequest item = queue->popFront();
//         if (item.d_type == my_WorkRequest::STOP) break;
//         myDoWork(item.d_data);
//     }
// }
//..
// The function below is a callback for 'bcemt_ThreadUtil', which requires a
// "C" signature.  'bcemt_ThreadUtil::create()' expects a pointer to this
// function, and provides that function pointer to the newly created thread.
// The new thread then executes this function.
//
// Since 'bcemt_ThreadUtil::create()' uses the familiar "C" convention of
// passing a 'void' pointer, our function simply casts that pointer to our
// required type ('bcec_Queue<my_WorkRequest*> *'), and then delegates to
// the queue-specific function 'myConsumer', above.
//..
// extern "C" void *myConsumerThread(void *queuePtr)
// {
//     myConsumer ((bcec_Queue<my_WorkRequest *>*) queuePtr);
//     return queuePtr;
// }
//..
// In this simple example, the 'myProducer' function serves multiple roles: it
// creates the 'bcec_Queue', starts out the consumer threads, and then produces
// and queues work items.  When work requests are exhausted, this function
// queues one 'STOP' item for each consumer queue.
//
// When each Consumer thread reads a 'STOP', it terminates its thread-handling
// function.  Note that, although the producer cannot control which thread
// 'pop's a particular work item, it can rely on the knowledge that each
// Consumer thread will read a single 'STOP' item and then terminate.
//
// Finally, the 'myProducer' function "joins" each Consumer thread, which
// ensures that the thread itself will terminate correctly; see the
// 'bcemt_thread' component for details.
//..
// void myProducer(int numThreads)
// {
//     myWorkRequest item;
//     my_WorkData workData;
//
//     bcec_Queue<my_WorkRequest *> queue;
//
//     assert(numThreads > 0 && numThreads <= MAX_CONSUMER_THREADS);
//     bcemt_ThreadUtil::Handle consumerHandles[MAX_CONSUMER_THREADS];
//
//     for (int i = 0; i < numThreads; ++i) {
//         bcemt_ThreadUtil::create(&consumerHandles[i],
//                                  myConsumerThread,
//                                  &queue);
//     }
//
//     while (!getWorkData(&workData)) {
//         item.d_type = my_WorkRequest::WORK;
//         item.d_data = workData;
//         queue.pushBack(item);
//     }
//
//     for (int i = 0; i < numThreads; ++i) {
//         item.d_type = my_WorkRequest::STOP;
//         queue.pushBack(item);
//     }
//
//     for (int i = 0; i < numThreads; ++i) {
//         bcemt_ThreadUtil::join(consumerHandles[i]);
//     }
// }
//..
///Example 2: Multi-Threaded Observer
/// - - - - - - - - - - - - - - - - -
// The previous example shows a simple mechanism for distributing work requests
// over multiple threads.  This approach works well for large tasks that can be
// decomposed into discrete, independent tasks that can benefit from parallel
// execution.  Note also that the various threads are synchronized only at the
// end of execution, when the Producer "joins" the various consumer threads.
//
// The simple strategy used in the first example works well for tasks that
// share no state, and are completely independent of one another.  For
// instance, a web server might use a similar strategy to distribute http
// requests across multiple worker threads.
//
// In more complicated examples, it is often necessary or desirable to
// synchronize the separate tasks during execution.  The second example below
// shows a single "Observer" mechanism that receives event notification from
// the various worker threads.
//
// We first create a simple 'my_Event' data type.  Worker threads will use this
// data type to report information about their work.  In our example, we will
// report the "worker Id", the event number, and some arbitrary text.
//
// As with the previous example, class 'my_Event' also contains an 'EventType',
// which is an enumeration which that indicates whether the worker has
// completed all work.  The "Observer" will use this enumerated value to note
// when a Worker thread has completed its work.
//..
// enum {
//     MAX_EVENT_TEXT = 80
// };
//
// struct my_Event {
//     enum EventType {
//         IN_PROGRESS   = 1
//       , TASK_COMPLETE = 2
//     };
//
//     EventType d_type;
//     int       d_workerId;
//     int       d_eventNumber;
//     char      d_eventText[MAX_EVENT_TEXT];
// };
//..
// As noted in the previous example, 'bcemt_ThreadUtil::create()' spawns
// a new thread, which invokes a simple "C" function taking a 'void' pointer.
// In the previous example, we simply converted that 'void' pointer into a
// pointer to the parameterized 'bcec_Queue<TYPE>' object.
//
// In this example, we want to pass an additional data item.  Each worker
// thread is initialized with a unique integer value ("worker Id") that
// identifies that thread.  We create a simple data structure that contains
// both of these values:
//..
// struct my_WorkerData {
//     int d_workerId;
//     bcec_Queue<my_Event> *d_queue;
// };
//..
// Function 'myWorker' simulates a working thread by enqueuing multiple
// 'my_Event' events during execution.  In a normal application, each
// 'my_Event' structure would likely contain different textual information;
// for the sake of simplicity, our loop uses a constant value for the text
// field.
//..
// void myWorker(int workerId, bcec_Queue<my_Event> *queue)
// {
//     const int NEVENTS = 5;
//     int evnum;
//
//     for (evnum = 0; evnum < NEVENTS; ++evnum) {
//         my_Event ev = {
//             my_Event::IN_PROGRESS,
//             workerId,
//             evnum,
//             "In-Progress Event"
//         };
//         queue->pushBack(ev);
//     }
//     my_Event ev = {
//         my_Event::TASK_COMPLETE,
//         workerId,
//         evnum,
//         "Task Complete"
//     };
//     queue->pushBack(ev);
// }
//..
// The callback function invoked by 'bcemt_ThreadUtil::create()' takes the
// traditional 'void' pointer.  The expected data is the composite structure
// 'my_WorkerData'.  The callback function casts the 'void' pointer to the
// application-specific data type and then uses the referenced object to
// construct a call to the 'myWorker' function.
//..
// extern "C" void *myWorkerThread(void *vWorkedPtr)
// {
//     my_WorkerData *workerPtr = (my_WorkerData *) workerPtr;
//     myWorker(workerPtr->d_workerId, workerPtr->d_queue);
//     return vWorkerPtr;
// }
//..
// For the sake of simplicity, we will implement the Observer behavior in the
// main thread.  The 'void' function 'myObserver' starts out multiple threads
// running the 'myWorker' function, reads 'my_Event's from the queue, and
// logs all messages in the order of arrival.
//
// As each 'myWorker' thread terminates, it sends a 'TASK_COMPLETE' event.
// Upon receiving this event, the 'myObserver' function uses the 'd_workerId'
// to find the relevant thread, and then "joins" that thread.
//
// The 'myObserver' function determines when all tasks have completed simply by
// counting the number of 'TASK_COMPLETE' messages received.
//..
// void myObserver()
// {
//     const int NTHREADS = 10;
//     bcec_Queue<my_Event> queue;
//
//     assert(NTHREADS > 0 && NTHREADS <= MAX_CONSUMER_THREADS);
//     bcemt_ThreadUtil::Handle workerHandles[MAX_CONSUMER_THREADS];
//
//     my_WorkerData workerData;
//     workerData.d_queue = &queue;
//     for (int i = 0; i < NTHREADS; ++i) {
//         workerData.d_workerId = i;
//         bcemt_ThreadUtil::create(&workerHandles[i],
//                                  myWorkerThread,
//                                  &workerData);
//     }
//     int nStop = 0;
//     while (nStop < NTHREADS) {
//         my_Event ev = queue.popFront();
//         bsl::cout << "[" << ev.d_workerId    << "] "
//                          << ev.d_eventNumber << ". "
//                          << ev.d_eventText   << bsl::endl;
//         if (my_Event::TASK_COMPLETE == ev.d_type) {
//             ++n_Stop;
//             bcemt_ThreadUtil::join(workerHandles[ev.d_workerId]);
//         }
//     }
// }
//..

#ifndef INCLUDED_BCESCM_VERSION
#include <bcescm_version.h>
#endif

#ifndef INCLUDED_BCEMT_LOCKGUARD
#include <bcemt_lockguard.h>
#endif

#ifndef INCLUDED_BCEMT_THREAD
#include <bcemt_thread.h>
#endif

#ifndef INCLUDED_BDEC_QUEUE
#include <bdec_queue.h>
#endif

#ifndef INCLUDED_BDET_TIMEINTERVAL
#include <bdet_timeinterval.h>
#endif

#ifndef INCLUDED_BSLALG_TYPETRAITS
#include <bslalg_typetraits.h>
#endif

#ifndef INCLUDED_BSLMA_ALLOCATOR
#include <bslma_allocator.h>
#endif

#ifndef INCLUDED_BSL_VECTOR
#include <bsl_vector.h>
#endif

namespace BloombergLP {

                             // ================
                             // class bcec_Deque
                             // ================

template <class TYPE>
class bcec_Deque {
    // This class provides a thread-enabled implementation of an efficient,
    // in-place, indexable, double-ended queue of parameterized 'TYPE' values.
    // Very efficient access to the underlying 'bdec_Queue' object is provided,
    // as well as to a 'bcemt_Mutex' and a 'bcemt_Condition' variable, to
    // facilitate thread-safe use of the 'bdec_Queue'.  Note that 'bcec_Queue'
    // is not a value-semantic type, but the underlying 'bdec_Queue' is.  In
    // this regard, 'bdec_Queue' is a thread-enabled handle for a 'bdec_Queue'.

  public:

    // DATA
    bcemt_Mutex      d_mutex;             // mutex object used to synchronize
                                          // access to this queue

    bcemt_Condition  d_notEmptyCondition; // condition variable used to signal
                                          // that new data is available in the
                                          // queue

    bcemt_Condition  d_notFullCondition;  // condition variable used to signal
                                          // when there is room available to
                                          // add new data to the queue

    bsl::deque<TYPE> d_deque;             // the underlying deque, with
                                          // allocator as last data member

    int              d_highWaterMark;     // positive maximum number of items
                                          // that can be queued before
                                          // insertions will be blocked, or
                                          // -1 if unlimited

  public:
    // TRAITS
    BSLALG_DECLARE_NESTED_TRAITS(bcec_Deque,
                                 bslalg::TypeTraitUsesBslmaAllocator);

    // PUBLIC TYPES
    typedef typename bsl::deque<TYPE>  Deque;
    typedef typename Deque::size_type> size_type;

    // TYPES
    struct InitialCapacity {
        // Enable uniform use of an optional integral constructor argument to
        // specify the initial internal capacity (in items).  For example,
        //..
        //   const bcec_Queue<int>::InitialCapacity NUM_ITEMS(8));
        //   bcec_Queue<int> x(NUM_ITEMS);
        //..
        // defines an instance 'x' with an initial capacity of 8 items, but
        // with a logical length of 0 items.

        // DATA
        unsigned int d_i;

        // CREATORS
        explicit InitialCapacity(int i) : d_i(i) { }
        ~InitialCapacity() { }
    };

    class Proctor;
    class ConstProctor;

    // CREATORS
    explicit
    bcec_Deque(bslma::Allocator *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE'.  Optionally
        // specify a 'basicAllocator' used to supply memory.  If
        // 'basicAllocator' is 0, the currently installed default allocator is
        // used.

    explicit
    bcec_Deque(int               highWaterMark,
               bslma::Allocator *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE' having either the
        // specified 'highWaterMark' suggested maximum length if
        // 'highWaterMark' is positive, or no maximum length if 'highWaterMark'
        // is negative.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.  The behavior is undefined unless
        // 'highWaterMark != 0'.

    explicit
    bcec_Deque(const InitialCapacity&  numItems,
               bslma::Allocator       *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE' with sufficient
        // initial capacity to accommodate up to the specified 'numItems'
        // values without subsequent reallocation.  Optionally specify a
        // 'basicAllocator' used to supply memory.  If 'basicAllocator' is 0,
        // the currently installed default allocator is used.

    bcec_Deque(const InitialCapacity&  numItems,
               int                     highWaterMark,
               bslma::Allocator       *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE' with sufficient
        // initial capacity to accommodate up to the specified 'numItems'
        // values without subsequent reallocation and having either the
        // specified 'highWaterMark' suggested maximum length if
        // 'highWaterMark' is positive, or no maximum length if 'highWaterMark'
        // is negative.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.  The behavior is undefined unless
        // 'highWaterMark != 0'.

    explicit
    bcec_Deque(const Deque&      srcQueue,
               bslma::Allocator *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE' containing the
        // sequence of 'TYPE' values from the specified 'srcQueue'.  Optionally
        // specify a 'basicAllocator' used to supply memory.  If
        // 'basicAllocator' is 0, the currently installed default allocator is
        // used.

    bcec_Deque(const Deque&      srcQueue,
               int               highWaterMark,
               bslma::Allocator *basicAllocator = 0);
        // Create a queue of objects of parameterized 'TYPE' containing the
        // sequence of 'TYPE' values from the specified 'srcQueue' and having
        // either the specified 'highWaterMark' suggested maximum length if
        // 'highWaterMark' is positive, or no maximum length if 'highWaterMark'
        // is negative.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.  The behavior is undefined unless
        // 'highWaterMark != 0'.

    bcec_Deque(const bcec_Deque<TYPE>&  original,
               bslma::Allocator        *basicAllocator = 0);
        // Create an in-place queue initialized to the value of the specified
        // 'original' 'bcec_Deque'.  Optionally specify the 'basicAllocator'
        // used to supply memory.  If 'basicAllocator' is 0, the currently
        // installed default allocator is used.

    ~bcec_Deque();
        // Destroy this queue.

    // MANIPULATORS
    bcec_Deque& operator=(const bcec_Deque<TYPE>& rhs);
        // Assign to this 'bcec_Deque' the value of the specified 'rhs' queue
        // and return a reference to this modifiable queue.

    void popBack(TYPE *buffer);
        // Remove the last item in this queue and load that item into the
        // specified 'buffer'.  If this queue is empty, block until an item
        // is available.

    TYPE popBack();
        // Remove the last item in this queue and return that item value.  If
        // this queue is empty, block until an item is available.

    int timedPopBack(TYPE *buffer, const bdet_TimeInterval& timeout);
        // Remove the last item in this queue and load that item value into
        // the specified 'buffer'.  If this queue is empty, block until an
        // item is available or until the specified 'timeout' (expressed as
        // the !ABSOLUTE! time from 00:00:00 UTC, January 1, 1970) expires.
        // Return 0 on success, and a non-zero value if the call timed
        // out before an item was available.

    void popFront(TYPE *buffer);
        // Remove the first item in this queue and load that item into
        // the specified 'buffer'.  If the queue is empty, block until
        // an item is available.

    TYPE popFront();
        // Remove the first item in this queue and return that item value.  If
        // the queue is empty, block until an item is available.

    int timedPopFront(TYPE *buffer, const bdet_TimeInterval& timeout);
        // Remove the first item in this queue and load that item value into
        // the specified 'buffer'.  If this queue is empty, block until an
        // item is available or until the specified 'timeout' (expressed as
        // the !ABSOLUTE! time from 00:00:00 UTC, January 1, 1970) expires.
        // Return 0 on success, and a non-zero value if the call timed
        // out before an item was available.

    void pushBack(const TYPE& item);
        // Append the specified 'item' to the back of this queue.  If the
        // high-water mark is non-negative and the number of items in this
        // queue is greater than or equal to the high-water mark, then block
        // until the number of items in this queue is less than the high-water
        // mark.

    void pushFront(const TYPE& item);
        // Append the specified 'item' to the front of this queue.  If the
        // high-water mark is non-negative and the number of items in this
        // queue is greater than or equal to the high-water mark, then block
        // until the number of items in this queue is less than the high-water
        // mark.

    int timedPushBack(const TYPE& item, const bdet_TimeInterval& timeout);
        // Append the specified 'item' to the back of this queue.  If the
        // high-water mark is non-negative and the number of items in this
        // queue is greater than or equal to the high-water mark, then block
        // until the number of items in this queue is less than the high-water
        // mark or until the specified 'timeout' (expressed as the !ABSOLUTE!
        // time from 00:00:00 UTC, January 1, 1970) expires.   Return 0 on
        // success, and a non-zero value if the call timed out before the
        // number of items in this queue fell below the high-water mark.

    int timedPushFront(const TYPE& item,  const bdet_TimeInterval& timeout);
        // Append the specified 'item' to the front of this queue.  If the high
        // water mark is non-negative and the number of items in this queue is
        // greater than or equal to the high-water mark, then block until the
        // number of items in this queue is less than the high-water mark or
        // until the specified 'timeout' (expressed as the !ABSOLUTE! time from
        // 00:00:00 UTC, January 1, 1970) expires.  Return 0 on success, and a
        // non-zero value if the call timed out before the number of items in
        // this queue fell below the high-water mark.

    void forcePushBack(const TYPE& item);
        // Append the specified 'item' to the back of this queue without
        // regard for the high-water mark.  Note that this method is provided
        // to allow high priority items to be inserted when the queue is full
        // (i.e., has a number of items greater than or equal to its
        // high-water mark); 'pushFront' and 'pushBack' should be used for
        // general use.

    void forcePushFront(const TYPE& item);
        // Append the specified 'item' to the front of this queue without
        // regard for the high-water mark.  Note that this method is provided
        // to allow high priority items to be inserted when the queue is full
        // (i.e., has a number of items greater than or equal to its
        // high-water mark); 'pushFront' and 'pushBack' should be used for
        // general use.

    void removeAll(bsl::vector<TYPE> *buffer = 0);
        // Remove all the items in this queue.  If the optionally specified
        // 'buffer' is not 0, load into 'buffer' a copy of the items removed
        // in front to back order of the queue prior to 'removeAll'.

    int tryPopFront(TYPE *buffer);
        // If this queue is non-empty, remove the first item, load that item
        // into the specified 'buffer', and return 0 indicating success.  If
        // this queue is empty, return a non-zero value with no effect on
        // 'buffer' or the state of this queue.  This method never blocks.

    void tryPopFront(int maxNumItems, bsl::vector<TYPE> *buffer = 0);
        // Remove up to the specified 'maxNumItems' from the front of this
        // queue.  Optionally specify a 'buffer' into which the items removed
        // from the queue are loaded.  If 'buffer' is non-null, the removed
        // items are appended to it as if by repeated application of
        // 'buffer->push_back(popFront())' while the queue is not empty and
        // 'maxNumItems' have not yet been removed.  The behavior is undefined
        // unless 'maxNumItems >= 0'.  This method never blocks.

    int tryPopBack(TYPE *buffer);
        // If this queue is non-empty, remove the last item, load that item
        // into the specified 'buffer', and return 0 indicating success.  If
        // this queue is empty, return a non-zero value with no effect on
        // 'buffer' or the state of this queue.  This method never blocks.

    void tryPopBack(int maxNumItems, bsl::vector<TYPE> *buffer = 0);
        // Remove up to the specified 'maxNumItems' from the back of this
        // queue.  Optionally specify a 'buffer' into which the items removed
        // from the queue are loaded.  If 'buffer' is non-null, the removed
        // items are appended to it as if by repeated application of
        // 'buffer->push_back(popBack())' while the queue is not empty and
        // 'maxNumItems' have not yet been removed.  This method never blocks.
        // The behavior is undefined unless 'maxNumItems >= 0'.  Note that the
        // ordering of the items in '*buffer' after the call is the reverse of
        // the ordering they had in the queue.

    // ACCESSORS
    int highWaterMark() const;
        // Return the high-water mark value for this queue.  Note that a
        // negative value indicates no suggested-maximum capacity, and is not
        // necessarily the same negative value that was passed to the
        // constructor.

    int length() const;
        // Return the number of elements contained in this container.  Note
        // that this temporarily acquires the mutex, and the value returned is
        // potentially obsolete before it is returned if any other threads are
        // simultaneously modifying this container.
};

                          // =========================
                          // class bcec_Deque::Proctor
                          // =========================

template <typename TYPE>
class bcec_Deque<TYPE>::Proctor {
    // This class defines a proctor type which provides direct access to the
    // underlying 'bsl::deque' contained in a 'bcec_Queue'.

    // DATA
    bcemt_LockGuard<bcemt_Mutex>  d_lock;
    bcec_Deque<TYPE>             *d_container_p;
    size_type                     d_startLength;

  private:
    // NOT IMPLEMENTED
    Proctor(const Proctor&);
    Proctor& operator=(const Proctor&);

  public:
    // CREATORS
    explicit
    Proctor(bcec_Deque<TYPE> *container);
        // Create a 'Proctor' object to provide access to the underlying
        // 'bsl::deque' contained in the specified container, locking
        // 'container's mutex.

    ~Proctor();
        // Release the lock on the mutex of the 'bdec_Deque' that was provided
        // at contstuction and destroy this 'Proctor' object.

    // MANIPULATORS
    TYPE& operator[](Deque::size_type index);
        // Return a reference to the element of the 'bsl::deque' managed by
        // this 'Proctor' object corresponding to the specified 'index'.

    Deque& operator.();
        // Apply the given '.' operation to the 'bsl::deque' managed by this
        // 'Proctor' object'.

    Deque *operator&();
        // Return a pointer to the 'bsl::dequeu' managed by this 'Proctor'
        // object.

    // ACCESSORS
    const TYPE& operator[](Deque::size_type index) const;
        // Return a const reference to the element of the 'bsl::deque' managed
        // by this 'Proctor' object corresponding to the specified 'index'.

    const Deque& operator.() const;
        // Apply the given '.' operation to the 'bsl::deque' managed by this
        // 'Proctor' object', providing 'const' access only.

    const Deque *operator&() const;
        // Return a const pointer to the 'bsl::dequeu' managed by this
        // 'Proctor' object.
};

                        // ==============================
                        // class bcec_Deque::ConstProctor
                        // ==============================

template <typename TYPE>
class bcec_Deque<TYPE>::ConstProctor {
    // This class defines a proctor type which provides direct const access to
    // the underlying 'bsl::deque' contained in a 'bcec_Queue'.

    // DATA
    bcemt_LockGuard<bcemt_Mutex>  d_lock;
    const Deque                  *d_constDeque_p;
    size_type                     d_startLength;

  private:
    // NOT IMPLEMENTED
    ConstProctor(const ConstProctor&);
    ConstProctor& operator=(const ConstProctor&);

  public:
    // CREATORS
    explicit
    ConstProctor(const bcec_Deque<TYPE> *container);

    ~ConstProctor();

    // ACCESSORS
    const TYPE& operator[](Deque::size_type index) const;
        // Return a const reference to the element of the 'bsl::deque' managed
        // by this 'ConstProctor' object corresponding to the specified
        // 'index'.

    const Deque& operator.() const;
        // Apply the given '.' operation to the 'bsl::deque' managed by this
        // 'ConstProctor' object', providing 'const' access only.

    const Deque *operator&() const;
        // Return a const pointer to the 'bsl::dequeu' managed by this
        // 'ConstProctor' object.
};

                            // -------------------
                            // bcec_Deque::Proctor
                            // -------------------

// CREATORS
template <typename TYPE>
bcec_Deque<TYPE>::Proctor::Proctor(const bcec_Deque *container)
: d_lock(      &container->d_mutex)
, d_container_p(container)
, d_startLength(container->d_dequeu.size())
{}

template <typename TYPE>
bcec_Deque<TYPE>::Proctor::~Proctor()
{
    // Note that it is guaranteed that one or both loops will execute 0 times.

    size_type sz = d_container_p->d_deque.size();
    size_type ii = d_startLength;
    for (; ii < sz; ++ii) {
        d_container_p->d_notEmptyContdition.signal();
    }
    ii = bsl::min(ii, (size_type) d_container_p->d_highWaterMark);
    for (; ii > sz; --ii) {
        d_container_p->d_notFullCondition.signal();
    }
}

// MANIPULATORS
template <typename TYPE>
TYPE& bcec_Deque<TYPE>::Proctor::operator[](Deque::size_type index)
{
    return (d_constainer_p->d_deque)[index];
}

template <typename TYPE>
bsl::deeue<TYPE>& bcec_Deque<TYPE>::Proctor::operator.()
{
    return d_container_p->d_deque;
}

template <typename TYPE>
bsl::deque<TYPE> *operator&()
{
    return &d_container_p->d_deque;
}

// ACCESSORS
template <typename TYPE>
const TYPE& bcec_Deque<TYPE>::Proctor::operator[](Deque::size_type index) const
{
    return (d_constainer_p->d_deque)[index];
}

template <typename TYPE>
const bcec_Deque<TYPE>::Deque& bcec_Deque<TYPE>::Proctor::operator.() const
{
    return d_container_p->d_deque;
}

template <typename TYPE>
const Deque *bcec_Deque<TYPE>::Proctor::operator&() const
{
    return &d_container_p->d_deque;
}

                        // ------------------------
                        // bcec_Deque::ConstProctor
                        // ------------------------

// CREATORS
template <typename TYPE>
bcec_Deque<TYPE>::ConstProctor::ConstProctor(const bcec_Deque<TYPE> *container)
: d_lock(       &container->d_mutex)
, d_constDeque_p(container->d_deque)
, d_startLength( container->d_dequeu.size())
{}

template <typename TYPE>
bcec_Deque<TYPE>::ConstProctor::~ConstProctor()
{
    // It is impotant that nobody did a const_cast and modified the underlying
    // 'bsls:deque' since we don't signal the appropriate condtions in the
    // 'bcec_Deque'.  If they wanted to modify the 'bsl::deque' they should
    // have used a 'Proctor' instead of a 'ConstProctor'.

    BSLS_ASSERT_OPT(d_constDeque_p->size() == d_startLength &&
                     "Underlying 'bsl::deque' modified through ConstProcter.");
}

// ACCESSORS
template <typename TYPE>
const TYPE& bcec_Deque<TYPE>::ConstProctor::operator[](
                                                  Deque::size_type index) const
{
    return (*d_constDeque_p)[index];
}

template <typename TYPE>
const bsl::deque<TYPE>& bcec_Deque<TYPE>::ConstProctor::operator.() const
{
    return *d_constDeque_p;
}

template <typename TYPE>
const bsl::deque<TYPE> *bcec_Deque<TYPE>::ConstProctoroperator&() const
{
    return d_constDeque_p;
}

}  // close namespace BloombergLP

#endif

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2013
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
