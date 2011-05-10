[% PROCESS svc_util.t -%]
// [% pkg %]_requestprocessor.t.cpp   -*-C++-*-

#ifndef lint
static char RCSid_[% pkg %]_requestprocessor_t_cpp[] = [% -%]
[%- %]"\$Id: \$ \$CCId: \$  \$CSID:  \$  \$SCMId:  \$";
#endif

#include <[% pkg %]_requestprocessor.h>
#include <[% pkg %]_requestcontext.h>
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

#include <bcec_objectpool.h>
#include <bcem_aggregate.h>
#include <bcema_blob.h>
#include <bcema_pooledblobbufferfactory.h>
#include <bcema_testallocator.h>

#include <bdef_bind.h>
#include <bdef_placeholder.h>
#include <bdema_allocator.h>
#include <bdema_default.h>
#include <bdema_managedptr.h>
#include <bdesb_fixedmeminstreambuf.h>

// Schemas to resolve
#include <bdem_configschema.h>
#include <baexml_configschema.h>
#include <basapi_configschema.h>
#include <bascfg_configschema.h>

#include <cstdlib>
#include <iostream>
#include <sstream>
#include <strstream>

using std::cout;
using std::cerr;
using std::endl;
using std::flush;

using namespace BloombergLP;
using namespace BloombergLP::[% namespace %];

using bdef_PlaceHolders::_1;
using bdef_PlaceHolders::_2;

//=============================================================================
//                                 TEST PLAN
//-----------------------------------------------------------------------------
//                                 Overview
//                                 --------
// The component under test defines a message request processor for the
// [% SERVICE %] service.  Each test case calls the request processor's
// "process" method with a request object, and an instance of a
// 'RequestContext', instantiated with an instance of
// 'bassvc::TestRequestContextImp'.  The test request context implementation
// maintains a copy of the last response returned from the request processor
// under test.  The test code can retrieve the latest response from the test
// request context implementation object for inspection.
//-----------------------------------------------------------------------------
// CREATORS
// [ 1] RequestProcessor(bdema_Allocator *basicAllocator = 0);
// [ 1] RequestProcessor(const bcem_Aggregate&  configuration,
//                       bdema_Allocator       *basicAllocator = 0);
// [ 1] ~RequestProcessor();
//
// MANIPULATORS
// [  ] void processControlEvent(
//              const bassvc::RequestProcessorControlEvent& event);
[% IF !opts.noSchema -%]
[% SET iteration = 1 + svc.requests.size() -%]
[% FOREACH request = svc.requests -%]
[% SET iter = String.new(text => iteration).right(2) -%]
[% SET offlen = request.type.length + MSGNS.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
// [[% iter %]] int process[% request.name | MixedMixed %](
[% IF request.noNamespaceFlag -%]
[% IF request.isPrimitiveFlag -%]
[% SET offlen = request.type.length -%]
[% SET offlen = 33 - offlen -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
//              [% request.type %] [% offset %]request,
[% ELSE -%]
//              bdema_ManagedPtr<[% request.type %][% -%]
                [%- request.isVectorFlag ? ' ' : '' -%]
                [%- %]>& request,
[% END -%]
[% ELSE -%]
//              bdema_ManagedPtr<[% MSGNS %][% request.type %]>& request,
[% END -%]
//              bdema_ManagedPtr<RequestContext>& context);
[% SET iteration = iteration - 1 -%]
[% END -%]
[% ELSE -%]
// [ 2] void processRequest(
//              bdema_ManagedPtr<bcema_Blob>&     request,
//              bdema_ManagedPtr<RequestContext>& context);
[% END -%]
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
#define T_() std::cout << '\t' << std::flush; // Print tab w/o newline.

//=============================================================================
//                  GLOBAL TYPEDEFS/CONSTANTS FOR TESTING
//-----------------------------------------------------------------------------
typedef RequestProcessor Obj;
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
namespace {

void createBlob(
        void                    *arena,
        bdema_Allocator         *basicAllocator,
        bcema_BlobBufferFactory *factory)
{
    // Create a 'bcema_Blob' in the specified 'arena'.

    new (arena) bcema_Blob(factory, basicAllocator);
}


}  // close unnamed namespace

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
[% IF !opts.noSchema -%]
[% SET iteration = 1 + svc.requests.size() -%]
[% FOREACH request = svc.requests -%]
[% SET RequestName = request.name | MixedMixed -%]
      case [% iteration %]: {
        // --------------------------------------------------------------------
        // TESTING FUNCTION 'process[% RequestName %]'
        //
        // Concerns:
        //   That the 'process$RequestName' function delivers a valid response
        //   object, and that the delivered response contains the expected
        //   values given a specified request as input.
        //
        // Plan:
        //   Instantiate a request processor, 'mX', and a request, named
        //   'request', using the default constructor.  Then, adjust 'request'
        //   accordingly.  Instantiate a 'ResponseContext', 'context',
        //   and call the 'process$RequestName' method on 'mX' with 'request',
        //   and 'context'.  Verify that the response, obtained from the
        //   'context', is the appropriate type, and that it represents the
        //   correct result given the specified request.
        //
        // Testing:
        //   void process[% RequestName %](
[% IF request.noNamespaceFlag -%]
[% IF request.isPrimitiveFlag -%]
[% SET offlen = request.type.length -%]
[% SET offlen = 33 - offlen -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        //           [% request.type %] [% offset %]request,
[% ELSE -%]
        //           bdema_ManagedPtr<[% request.type %][% -%]
                     [%- request.isVectorFlag ? ' ' : '' -%]
                     [%- %]>& request,
[% END -%]
[% ELSE -%]
        //           bdema_ManagedPtr<[% MSGNS %][% request.type %]>& request,
[% END -%]
        //           bdema_ManagedPtr<RequestContext>& context);
        // --------------------------------------------------------------------

        if (verbose) {
            [%- SET bar = String.new("=").repeat(RequestName.length()) %]
            std::cout << "Testing 'process[% RequestName %]'" << std::endl
                      << "=================[% bar %]" << std::endl;
        }

        bcema_TestAllocator ta(veryVeryVeryVerbose);
        {
            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Initialization

            enum { BUFFER_SIZE = 1024 };    // blob buffer size

            bassvc::TestRequestContextImp<Rsp> *imp = new (ta)
                    bassvc::TestRequestContextImp<Rsp>(
                        bsct::UserIdentification(),
                        bsct::EncodingType::XML);
            bdema_ManagedPtr<bassvc::RequestContextImp> imp_mp(imp, &ta);

            bcema_PooledBlobBufferFactory bbf(BUFFER_SIZE, &ta);

            bcec_ObjectPool<bcema_Blob> bp(bdef_BindUtil::bind(&createBlob,
                                                               _1, _2, &bbf),
                                           -1, &ta);

            bassvc::RequestContext *impContext = new (ta)
                   bassvc::RequestContext(imp_mp, &bp, &bbf,
                                          basapi::CodecOptions());
            bdema_ManagedPtr<bassvc::RequestContext>
                  impContext_mp(impContext, &ta);

            RequestContext *context = new (ta)
                    RequestContext(impContext_mp, &ta);
            bdema_ManagedPtr<RequestContext> context_mp(context, &ta);

            bcem_Aggregate configuration;    // empty

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(configuration, &ta);

[% IF request.noNamespaceFlag -%]
[% IF request.isPrimitiveFlag -%]
            [% request.type %] request;
[% SET requestVar = 'request' -%]
[% ELSE -%]
            [% request.type %] *request =
                    reinterpret_cast<[% request.type %] *>(
                        ta.allocate(sizeof([% request.type %])));
            bdealg_ScalarPrimitives::defaultConstruct(request, &ta);

            bdema_ManagedPtr<[% request.type %][% -%]
            [%- request.isVectorFlag ? ' ' : '' -%]
            [%- %]>
                    request_mp(request, &ta);
[% SET requestVar = 'request_mp' -%]
[% END -%]
[% ELSE -%]
            [% MSGNS %][% request.type %] *request =
                    reinterpret_cast<[% MSGNS %][% request.type %] *>(
                        ta.allocate(sizeof([% MSGNS %][% request.type %])));
            bdealg_ScalarPrimitives::defaultConstruct(request, &ta);

            bdema_ManagedPtr<[% MSGNS %][% request.type %]>
                    request_mp(request, &ta);
[% SET requestVar = 'request_mp' -%]
[% END -%]

            // TBD: Add additional test implementation here.

            mX.process[% RequestName %]([% requestVar %], context_mp);

            const Rsp& response = imp->theResponse();

            // TBD: Add additional test implementation here.
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      }  break;
[% SET iteration = iteration - 1 -%]
[% END -%]
[% ELSE -%]
      case 2: {
        // --------------------------------------------------------------------
        // TESTING FUNCTION 'processRequest'
        //
        // Concerns:
        //   That the 'processRequest' function delivers a valid response
        //   object, and that the delivered response contains the expected
        //   values given a specified request as input.
        //
        // Plan:
        //   Instantiate a request processor, 'mX', and a 'bcema_Blob', named
        //   'request'.  Then, adjust 'request' accordingly.  Instantiate a
        //   'ResponseContext', 'context', and call the 'processRequest' method
        //   on 'mX' with 'request', and 'context'.  Verify that the response,
        //   obtained from the 'context', is the appropriate type, and that it
        //   represents the correct result given the specified request.
        //
        // Testing:
        //   void processRequest(
        //           bdema_ManagedPtr<bcema_Blob>&     request,
        //           bdema_ManagedPtr<RequestContext>& context);
        // --------------------------------------------------------------------

        if (verbose) {
            std::cout << "Testing 'processRequest'" << std::endl
                      << "========================" << std::endl;
        }

        bcema_TestAllocator ta(veryVeryVeryVerbose);
        {
            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Initialization

            enum { BUFFER_SIZE = 1024 };    // blob buffer size

            bassvc::TestRequestContextImp<Req> *imp = new (ta)
                    bassvc::TestRequestContextImp<Req>(
                        bsct::UserIdentification(),
                        bsct::EncodingType::XML);
            bdema_ManagedPtr<bassvc::RequestContextImp> imp_mp(imp, &ta);

            bcema_PooledBlobBufferFactory bbf(BUFFER_SIZE, &ta);

            bcec_ObjectPool<bcema_Blob> bp(bdef_BindUtil::bind(&createBlob,
                                                               _1, _2, &bbf),
                                           -1, &ta);

            bassvc::RequestContext *impContext = new (ta)
                   bassvc::RequestContext(imp_mp, &bp, &bbf,
                                          basapi::CodecOptions());
            bdema_ManagedPtr<bassvc::RequestContext>
                  impContext_mp(impContext, &ta);

            RequestContext *context = new (ta)
                    RequestContext(impContext_mp, &ta);
            bdema_ManagedPtr<RequestContext> context_mp(context, &ta);

            bcem_Aggregate configuration;    // empty

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(configuration, &ta);

            Req *request = new (ta) Req(&bbf, &ta);
            bdema_ManagedPtr<Req> request_mp(request, &ta);

            // TBD: Add additional test implementation here.

            mX.processRequest(request_mp, context_mp);

            const bcema_Blob& response = imp->theResponse();

            // TBD: Add additional test implementation here.
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      }  break;
[% END -%]
      case 1: {
        // --------------------------------------------------------------------
        // BREATHING TEST
        //
        // Concerns:
        //   Exercise the basic functionality of the 'RequestProcessor'
        //   class.  We want to ensure that request processor objects can be
        //   instantiated and destroyed.  We also want to exercise the primary
        //   manipulators and accessors.
        //
        // Plan:
        //   Instantiate a request processor, 'mX'.  Verify that 'mX' is
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
            enum { BUFFER_SIZE = 1024 };    // blob buffer size

            bassvc::TestRequestContextImp<Rsp> *imp = new (ta)
                    bassvc::TestRequestContextImp<Rsp>(
                        bsct::UserIdentification(),
                        bsct::EncodingType::XML);
            bdema_ManagedPtr<bassvc::RequestContextImp> imp_mp(imp, &ta);

            bcema_PooledBlobBufferFactory bbf(BUFFER_SIZE, &ta);

            bcec_ObjectPool<bcema_Blob> bp(bdef_BindUtil::bind(&createBlob,
                                                               _1, _2, &bbf),
                                           -1, &ta);

            bassvc::RequestContext *impContext = new (ta)
                   bassvc::RequestContext(imp_mp, &bp, &bbf,
                                          basapi::CodecOptions());
            bdema_ManagedPtr<bassvc::RequestContext>
                  impContext_mp(impContext, &ta);

            RequestContext *context = new (ta)
                    RequestContext(impContext_mp, &ta);
            bdema_ManagedPtr<RequestContext> context_mp(context, &ta);

            bcem_Aggregate configuration;    // empty

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(configuration, &ta);

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
