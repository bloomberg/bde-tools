[% PROCESS svc_util.t -%]
// [% pkg %]_requestrouter.t.cpp   -*-C++-*-

#ifndef lint
static char RCSid_[% pkg %]_requestrouter_t_cpp[] = [% -%]
[%- %]"\$Id: \$ \$CCId: \$  \$CSID:  \$  \$SCMId:  \$";
#endif

#include <[% pkg %]_requestrouter.h>
#include <[% pkg %]_requestprocessor.h>
[% UNLESS opts.noSchema -%]
[% IF pkg != msgpkg -%]

[% END -%]
[% IF opts.msgExpand -%]
#include <[% msgpkg %]_[% requesttype %].h>
#include <[% msgpkg %]_[% responsetype %].h>
[% ELSE -%]
#include <[% msgpkg %]_[% opts.msgComponent %].h>
[% END -%]

[% END -%]
#include <basapi_codecutil.h>
#include <basapi_codecoptions.h>
#include <bassvc_requestprocessor.h>
#include <bassvc_testrequestcontextimp.h>

#include <bsct_encodingtype.h>
#include <bsct_useridentification.h>

[% UNLESS opts.noBBEnv -%]
#include <bapipc_pekludgeutil.h>

[% END -%]
#include <a_xercesc_reader.h>

#include <bael_defaultobserver.h>
#include <bael_loggermanager.h>
#include <bael_loggermanagerconfiguration.h>
#include <bael_severity.h>
#include <baexml_datautil.h>
#include <baexml_errorinfo.h>

#include <bcem_aggregate.h>
#include <bcema_blob.h>
#include <bcema_pooledblobbufferfactory.h>
#include <bcema_testallocator.h>

#include <bdema_allocator.h>
#include <bdema_default.h>
#include <bdema_managedptr.h>
#include <bdesb_fixedmeminstreambuf.h>

#include <cstdlib>
#include <iostream>
#include <sstream>

using std::cout;
using std::cerr;
using std::endl;
using std::flush;

using namespace BloombergLP;
using namespace BloombergLP::[% namespace %];

//=============================================================================
//                                 TEST PLAN
//-----------------------------------------------------------------------------
//                                 Overview
//                                 --------
//-----------------------------------------------------------------------------
// CREATORS
// [ 1] RequestRouter(
//              bdema_ManagedPtr<RequestProcessor>&  processor,
//              bdema_Allocator                     *basicAllocator = 0);
// [ 1] RequestRouter(
//              bdema_ManagedPtr<RequestProcessor>&  processor,
//              const bcem_Aggregate&                configuration,
//              const std::string&                   serviceName,
//              bdema_Allocator                     *basicAllocator = 0);
// [ 1] ~RequestRouter();
//
// MANIPULATORS
// [  ] void processRequest(
//              bdema_ManagedPtr<bcema_Blob>&             request,
//              bdema_ManagedPtr<bassvc::RequestContext>& context);
// [  ] void processControlEvent(
//              const bassvc::RequestProcessorControlEvent& event);
//-----------------------------------------------------------------------------
// [ 1] BREATHING TEST
//-----------------------------------------------------------------------------

//=============================================================================
//                      STANDARD BDE ASSERT TEST MACRO
//-----------------------------------------------------------------------------
static int testStatus = 0;

static void aSsErT(int c, const char *s, int i)
{
    if (c) {
        std::cout << "Error " << __FILE__ << "(" << i << "): " << s
                  << "    (failed)" << std::endl;
        if (0 <= testStatus && testStatus <= 100) ++testStatus;
    }
}

#define ASSERT(X) { aSsErT(!(X), #X, __LINE__); }

//=============================================================================
//                  STANDARD BDE LOOP-ASSERT TEST MACROS
//-----------------------------------------------------------------------------
#define LOOP_ASSERT(I,X) { \
    if (!(X)) { std::cout << #I << ": " << I << "\n"; \
                aSsErT(1, #X, __LINE__); }}

#define LOOP2_ASSERT(I,J,X) { \
    if (!(X)) { std::cout << #I << ": " << I << "\t"  \
                          << #J << ": " << J << "\n"; \
                aSsErT(1, #X, __LINE__); } }

#define LOOP3_ASSERT(I,J,K,X) { \
   if (!(X)) { std::cout << #I << ": " << I << "\t" \
                         << #J << ": " << J << "\t" \
                         << #K << ": " << K << "\n";\
               aSsErT(1, #X, __LINE__); } }


//=============================================================================
//                  SEMI-STANDARD TEST OUTPUT MACROS
//-----------------------------------------------------------------------------
#define P(X) std::cout << #X " = " << (X) << std::endl;
                                              // Print identifier and value.
#define Q(X) std::cout << "<| " #X " |>" << std::endl;
                                              // Quote identifier literally.
#define P_(X) std::cout << #X " = " << (X) << ", " << std::flush;
                                              // P(X) without '\n'
#define L_ __LINE__                           // current Line number
#define NL "\n"
#define T_() std::cout << '\t' << sttd:flush; // Print tab w/o newline.

//=============================================================================
//                  GLOBAL TYPEDEFS/CONSTANTS FOR TESTING
//-----------------------------------------------------------------------------
typedef RequestRouter Obj;
[% IF opts.noSchema -%]
typedef bcema_Blob Req;
typedef bcema_Blob Rsp;
[% ELSE -%]
typedef [% MSGNS %][% RequestType %] Req;
typedef [% MSGNS %][% ResponseType %] Rsp;
[% END -%]

static int verbose = 0;
static int veryVerbose = 0;
static int veryVeryVerbose = 0;
static int veryVeryVeryVerbose = 0;

//=============================================================================
//                        HELPER FUNCTIONS AND CLASSES
//-----------------------------------------------------------------------------

//=============================================================================
//                              MAIN PROGRAM
//-----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    int test = argc > 1 ? std::atoi(argv[1]) : 0;
    verbose = (argc > 2);
    veryVerbose = (argc > 3);
    veryVeryVerbose = (argc > 4);
    veryVeryVeryVerbose = (argc > 5);
    int verbosity = 1 + verbose + veryVerbose
                  + veryVeryVerbose + veryVeryVeryVerbose;

    std::cout << "TEST " << __FILE__ << " CASE " << test << std::endl;;

    bael_DefaultObserver               observer(&std::cout);
    bael_LoggerManagerConfiguration    configuration;
    bael_LoggerManager::initSingleton(&observer, configuration);

    bael_Severity::Level passthrough = bael_Severity::OFF;

    if (verbose) passthrough         = bael_Severity::WARN;
    if (veryVerbose) passthrough     = bael_Severity::INFO;
    if (veryVeryVerbose) passthrough = bael_Severity::TRACE;

    bael_LoggerManager::singleton().setDefaultThresholdLevels(
                                       bael_Severity::OFF,
                                       passthrough,
                                       bael_Severity::OFF,
                                       bael_Severity::OFF);

[% UNLESS opts.noBBEnv -%]
    bapipc_PekludgeEnvironment::initialize();

[% END -%]
    switch (test) { case 0:  // Zero is always the leading case.
      case 1: {
        // --------------------------------------------------------------------
        // BREATHING TEST
        //
        // Concerns:
        //   Exercise the basic functionality of the 'RequestRouter'
        //   class.  We want to ensure that request processor objects can be
        //   instantiated and destroyed.  We also want to exercise the primary
        //   manipulators and accessors.
        //
        // Plan:
        //   Instantiate a request router, 'mX'.  Verify that 'mX' is
        //   instantiated correctly.
        //
        // Testing:
        //   Exercise basic functionality.
        // --------------------------------------------------------------------

        if (verbose) {
            std::cout << "BREATHING TEST" << std::endl
                      << "==============" << std::endl;
        }

        bcema_TestAllocator ta(veryVeryVeryVerbose);
        {
            bcem_Aggregate configuration;    // empty

            RequestProcessor *requestProcessor = new (ta)
                    RequestProcessor(configuration, &ta);

            bdema_ManagedPtr<RequestProcessor>
                    requestProcessor_mp(requestProcessor, &ta);

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(requestProcessor_mp, configuration, &ta);

            // TBD: Add additional test implementation here.
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      } break;
      default: {
        std::cerr << "WARNING: CASE `" << test << "' NOT FOUND." << std::endl;
        testStatus = -1;
      }
    }

    if (testStatus > 0) {
        std::cerr << "Error, non-zero test status = " << testStatus << "."
                  << std::endl;
    }
    return testStatus;
}

// GENERATED BY [% version %] [% timestamp %]
// ---------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ----------------------------- END-OF-FILE ---------------------------------
