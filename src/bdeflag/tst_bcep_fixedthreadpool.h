// bcep_fixedthreadpool.h                                             -*-C++-*-
#ifndef INCLUDED_BCEP_FIXEDTHREADPOOL
#define INCLUDED_BCEP_FIXEDTHREADPOOL

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT("$Id: $")

//@PURPOSE: Provide portable implementation for a fixed-size pool of threads.
//
//@CLASSES:
//   txtbcep_FixedThreadPool: portable fixed-size thread pool
//
//@SEE_ALSO: bcep_threadpool
//
//@AUTHOR: Ilougino Rocha (irocha), Vlad Kliatchko (vkliatch)
//
//@DESCRIPTION: This component defines a portable and efficient implementation
// of a thread pool, 'txtbcep_FixedThreadPool', that can be used to distribute
// various user-defined functions ("jobs") to a separate threads to execute
// the jobs concurrently.  Each thread pool object manages a fixed number of
// processing threads and can hold up to a fixed maximum number of pending
// jobs.
//
// 'txtbcep_FixedThreadPool' implements a queuing mechanism that distributes
// among the threads.  Jobs are queued for execution as they arrive, and each
// queued job is processed by the next available thread.  If each of the
// concurrent threads is busy processing a job, new jobs will remain enqueued
// until a thread becomes available.  If the queue capacity is reached,
// enqueuing jobs will block until threads consume more jobs from the queue,
// causing its length to drop below its capacity.  Both the queue's capacity
// and number of threads are specified at construction and cannot be changed.
//
// The thread pool provides two interfaces for specifying jobs: the commonly
// used "void function/void pointer" interface and the more versatile functor
// based interface.  The void function/void pointer interface allows callers to
// use a C-style function to be executed as a job.  The application need only
// specify the address of the function, and a single void pointer argument, to
// be passed to the function.  The specified function will be invoked with the
// specified argument by the processing thread.  The functor based interface
// allows for more flexible job execution such as the invocation of member
// functions or the passing of multiple user-defined arguments.  See the 'bdef'
// package-level documentation for more on functors and their usage.
//
// Unlike a 'txtbcep_ThreadPool', an application can not tune a
// 'txtbcep_FixedThreadPool' once it is created with a specified number of
// threads and queue capacity, hence the name "fixed" thread pool.  An
// application can, however, specify the attributes of the threads in the
// pool (e.g., thread priority or stack size), by providing a
// 'bcemt_Attribute' object with the desired values set.  See 'bcemt_thread'
// package documentation for a description of 'bcemt_Attribute'.
//
// Thread pools are ideal for developing multi-threaded server applications.
// A server need only package client requests to execute as jobs, and
// 'txtbcep_FixedThreadPool' will handle the queue management, thread manage,
// and request dispatching.  Thread pools are also well suited for
// parallelizing certain types of application logic.  Without any complex or
// redundant thread management code, an application can easily create a thread
// pool, enqueue a series of jobs to be executed, and wait until all the jobs
// have executed.
//
///Thread Safety
///-------------
// The 'txtbcep_FixedThreadPool' class is both *fully thread-safe* (i.e., all
// non-creator methods can correctly execute concurrently), and is
// *thread-enabled* (i.e., the classes does not function correctly in a
// non-multi-threading environment).  See 'bsldoc_glossary' for complete
// definitions of *fully thread-safe* and *thread-enabled*.
//
///Synchronous signals on unix
///---------------------------
// A thread pool ensures that, on unix platforms, all the threads in the pool
// block all asynchronous signals.  Specifically all the signals, except the
// following synchronous signals are blocked:
//..
// SIGBUS
// SIGFPE
// SIGILL
// SIGSEGV
// SIGSYS
// SIGABRT
// SIGTRAP
// SIGIOT
//..
//
///Usage
///-----
// This example demonstrates the use of a 'txtbcep_FixedThreadPool' to paralle
// a segment of program logic.  The example implements a multi-threaded file
// search utility.  The utility searches multiple files for a string, similar
// to the Unix command 'fgrep'; the use of a 'txtbcep_FixedThreadPool' allows
// utility to search multiple files concurrently.
//
// The example program will take as input a string and a list of files to
// search.  The program creates a 'txtbcep_FixedThreadPool', and then enqueu
// single "job" for each file to be searched.  Each thread in the pool will
// take a job from the queue, open the file, and search for the string.  If a
// match is found, the job adds the filename to an array of matching filenames.
// Because this array of filenames is shared across multiple jobs and across
// multiple threads, access to the array is controlled via a 'bcemt_Mutex'.
//
///Setting FixedThreadPool Attributes
///- - - - - - - - - - - - - - - - -
// To get started, we declare thread attributes, to be used in constructing the
// thread pool.  In this example, our choices for number of threads and queue
// capacity are arbitrary.
//..
//  #define SEARCH_THREADS         10
//  #define SEARCH_QUEUE_CAPACITY  50
//..
// Below is the structure that will be used to pass arguments to the file
// search function.  Since each job will be searching a separate file, a
// distinct instance of the structure will be used for each job.
//..
//   struct my_FastSearchJobInfo {
//       const bsl::string        *d_word;    // word to search for
//       const bsl::string        *d_path;    // path of the file to search
//       bcemt_Mutex              *d_mutex;   // mutex to control access to the
//                                            // result file list
//       bsl::vector<bsl::string> *d_outList; // list of matching files
//   };
//..
//
///The "void function/void pointer" Interface
///- - - - - - - - - - - - - - - - - - - - -
// 'myFastSearchJob' is the search function to be executed as a job by threads
// in the thread pool, matching the "void function/void pointer" interface.
// The single 'void *' argument is received and cast to point to a 'struct
// my_FastSearchJobInfo', which then points to the search string and a single
// file to be searched.  Note that different 'my_FastSearchInfo' structures for
// the same search request will differ only in the attribute 'd_path', which
// points to a specific filename among the set of files to be searched; other
// fields will be identical across all structures for a given Fast Search.
//
// See the following section for an illustration of the functor interface.
//..
//   static void myFastSearchJob(void *arg)
//   {
//       myFastSearchJobInfo *job =  (myFastSearchJobInfo*)arg;
//       FILE *file;
//
//       file = fopen(job->d_path->c_str(), "r");
//
//       if (file) {
//           char  buffer[1024];
//           size_t nread;
//           int wordLen = job->d_word->length();
//           const char *word = job->d_word->c_str();
//
//           nread = fread(buffer, 1, sizeof(buffer) - 1, file);
//           while(nread >= wordLen) {
//               buffer[nread] = 0;
//               if (strstr(buffer, word)) {
//..
// If we find a match, we add the file to the result list and return.  Since
// the result list is shared among multiple processing threads, we use a mutex
// lock to regulate access to the list.  We use a 'bcemt_LockGuard' to manage
// access to the mutex lock.  This template object acquires a mutex lock on
// 'job->d_mutex' at construction, releases that lock on destruction.  Thus,
// the mutex will be locked within the scope of the 'if' block, and released
// when the program exits that scope.
//
// See 'bcemt_thread' for information about the 'bcemt_Mutex' class, and
// component 'bcemt_lockguard' for information about the 'bcemt_LockGuard'
// template class.
//..
//                bcemt_LockGuard<bcemt_Mutex> lock(job->d_mutex);
//                job->d_outList->push_back(*job->d_path);
//                break;  // bcemt_LockGuard destructor unlocks mutex.
//            }
//            memcpy(buffer, &buffer[nread - wordLen - 1], wordLen - 1);
//            nread = fread(buffer + wordLen - 1, 1, sizeof(buffer) - wordLen,
//                          file);
//        }
//        fclose(file);
//       }
//   }
//..
// Routine 'myFastSearch' is the main driving routine, taking three
// arguments: a single string to search for ('word'), a list of files to
// search, and an output list of files.  When the function completes, the file
// list will contain the names of files where a match was found.
//..
//   void  myFastSearch(const bsl::string&              word,
//                      const bsl::vector<bsl::string>& fileList,
//                      bsl::vector<bsl::string>&       outFileList)
//   {
//       bcemt_Mutex     mutex;
//       bcemt_Attribute defaultAttributes;
//..
// We initialize the thread pool using default thread attributes.  We then
// start the pool so that the threads can begin while we prepare the jobs.
//..
//       txtbcep_FixedThreadPool pool(defaultAttributes,
//                                 SEARCH_THREADS,
//                                 SEARCH_QUEUE_CAPACITY);
//
//       if (0 != pool.start()) {
//           bsl::cerr << "Thread start() failed.  Thread quota exceeded?"
//                     << bsl::endl;
//           exit(1);
//       }
//..
// For each file to be searched, we create the job info structure that will be
// passed to the search function and add the job to the pool.
//
// As noted above, all jobs will share a single mutex to guard the output file
// list.  Function 'myFastSearchJob' uses a 'bcemt_LockGuard' on this mutex to
// serialize access to the list.
//..
//       int count = fileList.size();
//       my_FastSearchJobInfo *jobInfoArray = new my_FastSearchJobInfo[count];
//
//       for (int i = 0; i < count; ++i) {
//           my_FastSearchJobInfo &job = jobInfoArray[i];
//           job.d_word    = &word;
//           job.d_path    = &fileList[i];
//           job.d_mutex   = &mutex;
//           job.d_outList = &outFileList;
//           pool.enqueueJob(myFastSearchJob, &job);
//       }
//..
// Now we simply wait for all the jobs in the queue to complete.  Any matched
// files should have been added to the output file list.
//..
//       pool.drain();
//       delete[] jobInfoArray;
//   }
//..
//
///The Functor Interface
///- - - - - - - - - - -
// The "void function/void pointer" convention is idiomatic for C programs.
// The 'void' pointer argument provides a generic way of passing in user data,
// without regard to the data type.  Clients who prefer better or more explicit
// type safety may wish to use the Functor Interface instead.  This interface
// uses 'bdef_Function' to provide type-safe wrappers that can match argument
// number and type for a C++ free function or member function.
//
// To illustrate the Functor Interface, we will make two small changes to the
// usage example above.  First, we change the signature of the function that
// executes a single job, so that it uses a 'myFastSearchJobInfo' pointer
// rather than a 'void' pointer.  With this change, we can remove the first
// executable statement, which casts the 'void *' pointer to
// 'myFastSearchJobInfo *'.
//..
//   static void myFastFunctorSearchJob(myFastSearchJobInfo *job)
//   {
//       FILE *file;
//
//       file = fopen(job->d_path->c_str(), "r");
//       // the rest of the function is unchanged.
//..
// Next, we make a change to the loop that enqueues the jobs in 'myFastSearch'.
// We create a functor - a C++ object that acts as a function.  The thread pool
// will "execute" this functor (by calling its 'operator()' member function) on
// a thread when one becomes available.
//..
//       for (int i = 0; i < count; ++i) {
//           my_FastSearchJobInfo &job = jobInfoArray[i];
//           job.d_word    = &word;
//           job.d_path    = &fileList[i];
//           job.d_mutex   = &mutex;
//           job.d_outList = &outFileList;
//
//           bdef_Function<void (*)()> jobHandle =
//                          bdef_BindUtil::bind(&myFastFunctorSearchJob, &job);
//           pool.enqueueJob(jobHandle);
//       }
//..
// Use of 'bdef_Function' and 'bdef_BindUtil' is described in the 'bdef'
// package documentation.  For this example, it is important to note that
// 'jobHandle' is a functor object, and that 'bdef_BindUtil::bind' populates
// that functor object with a function pointer (to the 'void' function
// 'myFastFunctorSearchJob') and user data ('&job').  When the functor is
// executed via 'operator()', it will in turn execute the
// 'myFastFunctorSearchJob' function with the supplied data as its argument.
//
// Note also that the functor is created locally and handed to the thread pool.
// The thread pool copies the functor onto its internal queue, and takes
// responsibility for the copied functor until execution is complete.
//
// The function is completed exactly as it was in the previous example.
//..
//       pool.drain();
//       delete[] jobInfoArray;
//   }
//..

#ifndef INCLUDED_BCESCM_VERSION
#include <bcescm_version.h>
#endif

#ifndef INCLUDED_BCEC_FIXEDQUEUE
#include <bcec_fixedqueue.h>
#endif

#ifndef INCLUDED_BCEMT_SEMAPHORE
#include <bcemt_semaphore.h>
#endif

#ifndef INCLUDED_BCEMT_THREAD
#include <bcemt_thread.h>
#endif

#ifndef INCLUDED_BCEMT_THREADGROUP
#include <bcemt_threadgroup.h>
#endif

#ifndef INCLUDED_BCES_ATOMICTYPES
#include <bces_atomictypes.h>
#endif

#ifndef INCLUDED_BDEF_BIND
#include <bdef_bind.h>
#endif

#ifndef INCLUDED_BDEF_FUNCTION
#include <bdef_function.h>
#endif

#if defined(BSLS_PLATFORM__OS_UNIX)
#ifndef INCLUDED_BSL_C_SIGNAL
#include <bsl_c_signal.h>              // sigset_t
#endif
#endif

namespace BloombergLP {

class bslma_Allocator;

extern "C" {
    typedef void (*txtbcep_FixedThreadPoolJobFunc)(void *);
        // This type declares the prototype for functions that are suitable
        // to be specified 'txtbcep_FixedThreadPool::enqueueJob'.
}

                         // ==========================
                         // class txtbcep_FixedThreadPool
                         // ==========================

class txtbcep_FixedThreadPool {
    // This class implements a thread pool used for concurrently executing
    // multiple user-defined functions ("jobs").

  public:
    // TYPES
    typedef bdef_Function<void(*)()> Job;
    typedef bcec_FixedQueue<Job>     Queue;

    enum {
        BCEP_STOP
      , BCEP_RUN
      , BCEP_SUSPEND
      , BCEP_DRAIN
#if !defined(BSL_LEGACY) || 1 == BSL_LEGACY
      , TP_STOP    = BCEP_STOP
      , TP_RUN     = BCEP_RUN
      , TP_SUSPEND = BCEP_SUSPEND
      , TP_DRAIN   = BCEP_DRAIN
#endif
    };

  private:
    // DATA
    Queue             d_queue;             // underlying queue

    bcemt_Semaphore   d_queueSemaphore;    // used to implemented blocking
                                           // popping on the queue

    bces_AtomicInt    d_numThreadsWaiting; // number of idle thread in the pool

    bcemt_Mutex       d_metaMutex;         // mutex to ensure that there is
                                           // only one controlling thread at
                                           // any time

    bces_AtomicInt    d_control;           // controls which action is to be
                                           // performed by the worker threads
                                           // (i.e., BCEP_RUN, BCEP_DRAIN,
                                           // BCEP_STOP)

    int               d_gateCount;         // count incremented every time
                                           // worker threads are allowed to
                                           // proceed through the gate

    int               d_numThreadsReady;   // number of worker threads
                                           // ready to go through the gate

    bcemt_Mutex       d_gateMutex;         // mutex used to protect the gate
                                           // count

    bcemt_Condition   d_threadsReadyCond;  // condition signaled when a worker
                                           // thread is ready at the gate

    bcemt_Condition   d_gateCond;
                                           // condition signaled when the
                                           // gate count is incremented

    bcemt_ThreadGroup d_threadGroup;       // threads used by this pool

    bcemt_Attribute   d_threadAttributes;  // thread attributes to be used when
                                           // constructing processing threads

    const int         d_numThreads;        // number of configured processing
                                           // threads.

#if defined(BSLS_PLATFORM__OS_UNIX)
    sigset_t          d_blockSet;          // set of signals to be blocked
                                           // in managed threads
#endif

    // PRIVATE MANIPULATORS
    void processJobs();
        // Repeatedly retrieves the next job off of the queue and processes
        // it or blocks until one is available.  This function terminates
        // when it detects a change in the control state.

    void drainQueue();
        // Repeatedly retrieves the next job off of the queue and processes
        // it until the queue is empty.

    void workerThread();
        // The main function executed by each worker thread.

    int startNewThread();
        // Internal method to spawn a new processing thread and increment the
        // current count.  Note that this method must be called with
        // 'd_metaMutex' locked.

    void waitWorkerThreads();
        // Waits for worker threads to be ready at the gate.

    void releaseWorkerThreads();
        // Allows worker threads to proceed through the gate.

    void interruptWorkerThreads();
        // Awaken any waiting worker threads by signaling the queue semaphore.

    // NOT IMPLEMENTED
    txtbcep_FixedThreadPool(const txtbcep_FixedThreadPool&);
    txtbcep_FixedThreadPool& operator=(const txtbcep_FixedThreadPool&);

  public:
    // CREATORS
    txtbcep_FixedThreadPool(int                    numThreads,
                         int                    maxNumPendingJobs,
                         bslma_Allocator       *basicAllocator = 0);
        // Construct a thread pool with the specified 'numThread' number of
        // threads and a job queue of capacity sufficient to enqueue the
        // specified 'maxNumPendingJobs' without blocking.  Optionally specify
        // a 'basicAllocator' used to supply memory.  If 'basicAllocator' is 0,
        // the currently installed default allocator is used.  The behavior is
        // undefined unless '1 <= numThreads' and
        // '1 <= maxPendingJobs <= 0x01FFFFFF'.

    txtbcep_FixedThreadPool(const bcemt_Attribute& threadAttributes,
                         int                    numThreads,
                         int                    maxNumPendingJobs,
                         bslma_Allocator       *basicAllocator = 0);
        // Construct a thread pool with the specified 'threadAttributes',
        // 'numThread' number of threads, and a job queue with capacity
        // sufficient to enqueue the specified 'maxNumPendingJobs' without
        // blocking.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.  The behavior is undefined unless
        // '1 <= numThreads' and '1 <= maxPendingJobs <= 0x01FFFFFF'.

    ~txtbcep_FixedThreadPool();
        // Remove all pending jobs from the queue without executing them,
        // block until all currently running jobs complete, and then
        // destroy this thread pool.

    // MANIPULATORS
    void disable();
        // Disable queuing into this pool.  Subsequent calls to enqueueJob()
        // or tryEnqueueJob() will immediately fail.  Note that this method
        // has no effect on jobs currently in the pool.

    void enable();
        // Enable queuing into this pool.

    int enqueueJob(const Job& functor);
        // Enqueue the specified 'functor' to be executed by the next available
        // thread.  Return 0 if enqueued successfully, and a non-zero value if
        // queuing is currently disabled.  Note that this function can block
        // if the underlying fixed queue has reached full capacity; use
        // 'tryEnqueueJob' instead for non-blocking.  The behavior is undefined
        // unless 'functor' is not "unset".  See 'bdef_function' for more
        // information on functors.

    int enqueueJob(txtbcep_FixedThreadPoolJobFunc function, void *userData);
        // Enqueue the specified 'function' to be executed by the next
        // available thread.  The specified 'userData' pointer will be passed
        // to the function by the processing thread.  Return 0 if enqueued
        // successfully, and a non-zero value if queuing is currently
        // disabled.

    int tryEnqueueJob(const Job& functor);
        // Attempt to enqueue the specified 'functor' to be executed by the
        // next available thread.  Return 0 if enqueued successfully, and a
        // nonzero value if queuing is currently disabled or the queue is
        // full.  The behavior is undefined unless 'functor' is not "unset".

    int tryEnqueueJob(txtbcep_FixedThreadPoolJobFunc function, void *userData);
        // Attempt to enqueue the specified 'function' to be executed by the
        // next available thread.  The specified 'userData' pointer will be
        // passed to the function by the processing thread.  Return 0 if
        // enqueued successfully, and a nonzero value if queuing is currently
        // disabled or the queue is full.

    void drain();
        // Wait until all pending jobs complete.  Note that if any jobs are
        // submitted concurrently with this method, this method may or may not
        // wait until they have also completed.

    void shutdown();
        // Disable queuing on this thread pool, cancel all queued jobs, and
        // after all actives jobs have completed, join all processing threads.

    int start();
        // Spawn 'numThreads()' processing threads.  On success, enable
        // enqueuing and return  0.  Return a nonzero value otherwise.  If
        // 'numThreads()' threads were not successfully started, all threads
        // are stopped.

    void stop();
        // Disable queuing on this thread pool and wait until all pending jobs
        // complete, then shut down all processing threads.

    // ACCESSORS
    bool isEnabled() const;
        // Return 'true' if queuing is enabled on this thread pool, and
        // 'false' otherwise.

    bool isStarted() const;
        // Return 'true' if 'numThreads()' are started on this threadpool()
        // and 'false' otherwise (indicating that 0 threads are started on
        // this thread pool.)

    int numActiveThreads() const;
        // Return a snapshot of the the number of threads that are currently
        // processing a job for this threadpool.

    int numPendingJobs() const;
        // Return a snapshot of the number of threads currently enqueued to be
        // processed by thread pool.

    int numThreads() const;
        // Return the number of threads passed to this thread pool at
        // construction.

    int numThreadsStarted() const;
        // Return a snapshot of the number of threads currently started by this
        // thread pool.

    int queueCapacity() const;
        // Return the capacity of the queue used to enqueue jobs by this
        // thread pool.
};

// ===========================================================================
//                        INLINE FUNCTION DEFINITIONS
// ===========================================================================

                         // --------------------------
                         // class txtbcep_FixedThreadPool
                         // --------------------------

// MANIPULATORS
inline
void txtbcep_FixedThreadPool::disable()
{
    d_queue.disable();
}

inline
void txtbcep_FixedThreadPool::enable()
{
    d_queue.enable();
}

inline
int txtbcep_FixedThreadPool::enqueueJob(txtbcep_FixedThreadPoolJobFunc  func,
                                     void                        *userData)
{
    return enqueueJob(bdef_BindUtil::bindR<void>(function, userData));
}

inline
int txtbcep_FixedThreadPool::tryEnqueueJob(txtbcep_FixedThreadPoolJobFunc  fun,
                                        void                        *userData)
{
    return tryEnqueueJob(bdef_BindUtil::bindR<void>(function, userData));
}

// ACCESSORS
inline
bool txtbcep_FixedThreadPool::isEnabled() const
{
    return d_queue.isEnabled();
}

inline
bool txtbcep_FixedThreadPool::isStarted() const
{
    return d_numThreads == d_threadGroup.numThreads();
}

inline
int txtbcep_FixedThreadPool::numActiveThreads() const
{
    int numStarted = d_threadGroup.numThreads();
    return d_numThreads == numStarted
         ? numStarted - d_numThreadsWaiting.relaxedLoad()
         : 0;
}

inline
int txtbcep_FixedThreadPool::numPendingJobs() const
{
    return d_queue.length();
}

inline
int txtbcep_FixedThreadPool::numThreads() const
{
    return d_numThreads;
}

inline
int txtbcep_FixedThreadPool::numThreadsStarted() const
{
    return d_threadGroup.numThreads();
}

inline
int txtbcep_FixedThreadPool::queueCapacity() const
{
    return d_queue.size();
}

}  // close namespace BloombergLP

#endif

// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., 2009
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
