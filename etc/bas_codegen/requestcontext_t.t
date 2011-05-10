[% PROCESS svc_util.t -%]
// [% pkg %]_requestcontext.t.cpp   -*-C++-*-

#ifndef lint
static char RCSid_[% pkg %]_requestcontext_t_cpp[] = [% -%]
[%- %]"\$Id: \$ \$CCId: \$  \$CSID:  \$  \$SCMId:  \$";
#endif

#include <[% pkg %]_requestcontext.h>
[% UNLESS opts.noSchema -%]
[% IF pkg != msgpkg -%]

[% END -%]
[% IF opts.msgExpand -%]
#include <[% msgpkg %]_[% responsetype %].h>
[% ELSE -%]
#include <[% msgpkg %]_[% opts.msgComponent %].h>
[% END -%]

[% END -%]
#include <basapi_codecoptions.h>
#include <bassvc_requestcontext.h>
#include <bassvc_testrequestcontextimp.h>

#include <bsct_encodingtype.h>
#include <bsct_mimesettings.h>
#include <bsct_useridentification.h>

#include <bael_defaultobserver.h>
#include <bael_loggermanager.h>
#include <bael_loggermanagerconfiguration.h>
#include <bael_severity.h>

#include <bcec_objectpool.h>
#include <bcema_blob.h>
#include <bcema_pooledblobbufferfactory.h>
#include <bcema_testallocator.h>

#include <bdealg_scalarprimitives.h>
#include <bdef_bind.h>
#include <bdef_placeholder.h>
#include <bdema_managedptr.h>

#include <cstdlib>
#include <iostream>
#include <sstream>

using namespace BloombergLP;

using std::cout;
using std::cerr;
using std::endl;
using std::flush;

using bdef_PlaceHolders::_1;
using bdef_PlaceHolders::_2;

using namespace BloombergLP::[% namespace %];

//=============================================================================
//                                 TEST PLAN
//-----------------------------------------------------------------------------
//                                 Overview
//                                 --------
//-----------------------------------------------------------------------------
// CREATORS
// [ 1] RequestContext(
//          bdema_ManagedPtr<bassvc::RequestContext>&  context)
//          bdema_Allocator                           *basicAllocator = 0);
// [ 1] ~RequestContext();
//
// MANIPULATORS
[% IF !opts.noSchema -%]
[% SET iteration = 2 + svc.responses.size() -%]
[% FOREACH response = svc.responses -%]
[% SET iter = String.new(text => iteration).right(2) -%]
// [[% iter %]] int deliver[% response.name | MixedMixed %](
[% SET offlen = -4 + response.type.length -%]
[% IF response.noNamespaceFlag -%]
[% IF response.isPrimitiveFlag -%]
//          [% response.type %] response,
[% ELSE -%]
//          const [% response.type %]& response,
[% SET offlen = offlen + 7 -%]
[% END -%]
[% ELSE -%]
//          const [% MSGNS %][% response.type %]& response,
[% SET offlen = offlen + 7 + MSGNS.length -%]
[% END -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
//          bool [% offset %]isFinal = true) const;
[% SET iteration = iteration - 1 -%]
[% END -%]
[% SET iter = String.new(text => iteration).right(2) -%]
[% ELSE -%]
[% SET iter = 2 -%]
[% END -%]
[% SET offlen = ResponseType.length + MSGNS.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
// [[% iter %]] int deliverResponse(
//          const [% MSGNS %][% ResponseType %]& response,
//          bool  [% offset %]  isFinal = true);
// [ 1] int deliverAcknowledgment();
// [ 1] int deliverError(const bsct::ErrorInfo& errorMessage,
//                       bool                   reroutableFlag = false);
// [ 1] bool setMimeSettings(const bsct::MimeSettings& settings);
// [ 1] bcema_BlobBufferFactory *bufferFactory();
//
// ACCESSORS
// [ 1] bsct::EncodingType::Value requestEncoding() const;
// [ 1] bool getMimeSettings(bsct::MimeSettings *result) const;
// [ 1] bool isOneWayRequest() const;
// [ 1] bool isAckRequested() const;
// [ 1] const bsct::UserIdentification& userIdentification() const;
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
typedef [% namespace %]::RequestContext Obj;
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
        bdema_Allocator         *allocator,
        bcema_BlobBufferFactory *factory)
{
    // Create a 'bcema_Blob' in the specified 'arena' having the specified
    // 'factory' and the specified 'allocator'.

    new (arena) bcema_Blob(factory, allocator);
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

    switch (test) { case 0:  // Zero is always the leading case.
[% IF !opts.noSchema -%]
[% SET iteration = 2 + svc.responses.size() -%]
[% FOREACH response = svc.responses -%]
[% SET ResponseName = response.name | MixedMixed -%]
      case [% iteration %]: {
        // --------------------------------------------------------------------
        // TESTING FUNCTION 'deliver[% ResponseName %]'
        //
        // Concerns:
        //   That the 'deliver$ResponseName' function delivers a valid
        //   response object, and that the delivered response contains the
        //   expected values given a specified response as input.
        //
        // Plan:
        //   Instantiate a 'bassvc::RequestContext', 'context', using a
        //   'bassvc::TestRequestContextImp', 'imp'.  Instantiate a
        //   'RequestContext', 'mX', using 'context', and a '[% ResponseName %]'
        //   response, named 'response'.  Call the 'deliver$ResponseName'
        //   method on 'mX' with 'response'.  Verify that the response,
        //   obtained from 'imp', is equal to the specified 'response'.
        //
        // Testing:
        //   void deliver[% ResponseName %](
[% SET offlen = -4 + response.type.length -%]
[% IF response.noNamespaceFlag -%]
[% IF response.isPrimitiveFlag -%]
        //       [% response.type %] response,
[% ELSE -%]
        //       const [% response.type %]& response,
[% SET offlen = offlen + 7 -%]
[% END -%]
[% ELSE -%]
        //       const [% MSGNS %][% response.type %]& response,
[% SET offlen = offlen + 7 + MSGNS.length -%]
[% END -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        //       bool [% offset %]isFinal = true) const;
        // --------------------------------------------------------------------

        if (verbose) {
            [%- SET bar = String.new("=").repeat(ResponseName.length()) %]
            std::cout << "Testing 'deliver[% ResponseName %]'" << std::endl
                      << "================[% bar %]" << std::endl;
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

            bcec_ObjectPool<bcema_Blob> pool(bdef_BindUtil::bind(&createBlob,
                                                                 _1, _2, &bbf),
                                             -1, &ta);

            basapi::CodecOptions codecOptions(&ta);
            std::string xmlNamespace("[% svc.targetNamespace %]");
            std::string responseElement("[% svc.responseElement %]");
            codecOptions.xmlEncoderOptions().setObjectNamespace(xmlNamespace);
            codecOptions.xmlEncoderOptions().setTag(responseElement);

            bassvc::RequestContext *context = new (ta)
                    bassvc::RequestContext(imp_mp, &pool, &bbf, codecOptions);
            bdema_ManagedPtr<bassvc::RequestContext> context_mp(context, &ta);

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(context_mp, &ta);

[% IF response.noNamespaceFlag -%]
[% IF response.isPrimitiveFlag -%]
            [% response.type %] response;
[% SET responseVar = 'response' -%]
[% ELSE -%]
[% SET isVectorFlag = response.type.search("std::vector") -%]
            [% response.type %] *response =
                    reinterpret_cast<[% response.type %] *>(
                        ta.allocate(sizeof([% response.type %])));
            bdealg_ScalarPrimitives::defaultConstruct(response, &ta);
[% SET responseVar = '*response' -%]
[% END -%]
[% ELSE -%]
            [% MSGNS %][% response.type %] *response =
                    reinterpret_cast<[% MSGNS %][% response.type %] *>(
                        ta.allocate(sizeof([% MSGNS %][% response.type %])));
            bdealg_ScalarPrimitives::defaultConstruct(response, &ta);
[% SET responseVar = '*response' -%]
[% END -%]

            // TBD: Call 'makeXXX' for each choice-type in the response.

            mX.deliver[% ResponseName %]([% responseVar %], true);

            const Rsp& RESPONSE = imp->theResponse();
            ASSERT(RESPONSE.is[% ResponseName %]Value());

            Rsp rsp;
            rsp.make[% ResponseName %]([% responseVar %]);
            ASSERT(RESPONSE == rsp);
[% UNLESS response.isPrimitiveFlag -%]

            bdealg_ScalarPrimitives::destruct(response, &ta);
            ta.deallocate(response);
[% END -%]
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      }  break;
[% SET iteration = iteration - 1 -%]
[% END %]
[% ELSE -%]
[% SET iteration = 2 -%]
[% END -%]
      case [% iteration %]: {
        // --------------------------------------------------------------------
        // TESTING FUNCTION 'deliverResponse'
        //
        // Concerns:
        //   That the 'deliverResponse' function delivers a valid response
        //   object, and that the delivered response contains the expected
        //   values given a specified response as input.
        //
        // Plan:
        //   Instantiate a 'bassvc::RequestContext', 'context', using a
        //   'bassvc::TestRequestContextImp', 'imp'.  Instantiate a
        //   'RequestContext', 'mX', using 'context', and a
        //   '[% ResponseType %]' response, named 'response'.  Call the
        //   'deliverResponse' method on 'mX' with 'response'.  Verify that the
        //   response, obtained from 'imp', is equal to the specified
        //   'response'.
        //
        // Testing:
        //   void deliverResponse(
        //       const [% MSGNS %][% ResponseType %]>& request,
        //       bdema_ManagedPtr<bsct::RequestContext>& context);
        // --------------------------------------------------------------------

        if (verbose) {
            std::cout << "Testing 'deliverResponse'" << std::endl
                      << "=========================" << std::endl;
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

            bcec_ObjectPool<bcema_Blob> pool(bdef_BindUtil::bind(&createBlob,
                                                                 _1, _2, &bbf),
                                             -1, &ta);

            basapi::CodecOptions codecOptions(&ta);
[% UNLESS opts.noSchema -%]
            std::string xmlNamespace("[% svc.targetNamespace %]");
            std::string responseElement("[% svc.responseElement %]");
            codecOptions.xmlEncoderOptions().setObjectNamespace(xmlNamespace);
            codecOptions.xmlEncoderOptions().setTag(responseElement);
[% END -%]

            bassvc::RequestContext *context = new (ta)
                    bassvc::RequestContext(imp_mp, &pool, &bbf, codecOptions);
            bdema_ManagedPtr<bassvc::RequestContext> context_mp(context, &ta);

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(context_mp, &ta);

[% IF opts.noSchema -%]
            bcema_Blob *response = new (ta) bcema_Blob(&bbf, &ta);

            // TBD: adjust 'response' as necessary

            mX.deliverResponse(*response, true);

            const Rsp& RESPONSE = imp->theResponse();
            ASSERT(RESPONSE == *response);

            ta.deleteObject(response);
[% ELSE -%]
[% SET response = svc.responses.0 -%]
            [% MSGNS %][% ResponseType %] *response =
                    reinterpret_cast<[% MSGNS %][% ResponseType %] *>(
                        ta.allocate(sizeof([% MSGNS %][% ResponseType %])));
            bdealg_ScalarPrimitives::defaultConstruct(response, &ta);

            // TBD: Call 'makeXXX' for each choice-type in the response.
            response->make[% response.name | MixedMixed %]();

            mX.deliverResponse(*response, true);

            const Rsp& RESPONSE = imp->theResponse();
            ASSERT(RESPONSE.is[% response.name | MixedMixed %]Value());
            ASSERT(RESPONSE == *response);

            bdealg_ScalarPrimitives::destruct(response, &ta);
            ta.deallocate(response);
[% END -%]
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      }  break;
      case 1: {
        // --------------------------------------------------------------------
        // BREATHING TEST
        //
        // Concerns:
        //   Exercise the basic functionality of the 'RequestContext' class.
        //   We want to ensure that request processor objects can be
        //   instantiated and destroyed.  We also want to exercise the primary
        //   manipulators and accessors.
        //
        // Plan:
        //   Instantiate a 'bassvc::RequestContext', 'context', using a
        //   'bassvc::TestRequestContextImp', 'imp'.  Instantiate a
        //   'RequestContext', 'mX', using 'context'.  Call the primary
        //   manipulators and accessors, and verify that the responses,
        //   obtained from 'imp', are equal to the specified inputs.
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
            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Initialization

            enum { BUFFER_SIZE = 1024 };    // blob buffer size

            bsct::UserIdentification userInfo;
            userInfo.setUuid(2620982);
            userInfo.setSid(772311);
            userInfo.setPindex(3210);
            userInfo.setLuw(2367);
            userInfo.setMachineNumber(415);
            userInfo.setTerminalSerialNumber(231648);
            userInfo.setSource(bsct::UserIdentification::SOURCE_BIG);

            bassvc::TestRequestContextImp<Rsp> *imp = new (ta)
                    bassvc::TestRequestContextImp<Rsp>(
                        userInfo, bsct::EncodingType::XML);
            bdema_ManagedPtr<bassvc::RequestContextImp> imp_mp(imp, &ta);

            bcema_PooledBlobBufferFactory bbf(BUFFER_SIZE, &ta);

            bcec_ObjectPool<bcema_Blob> pool(bdef_BindUtil::bind(&createBlob,
                                                                 _1, _2, &bbf),
                                             -1, &ta);

            bassvc::RequestContext *context = new (ta)
                    bassvc::RequestContext(imp_mp, &pool, &bbf,
                                           basapi::CodecOptions(&ta));
            bdema_ManagedPtr<bassvc::RequestContext> context_mp(context, &ta);

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            Obj mX(context_mp, &ta);

            ASSERT(false == mX.isOneWayRequest());
            ASSERT(false == mX.isAckRequested());
            ASSERT(&bbf == mX.bufferFactory());
            ASSERT(userInfo == mX.userIdentification());
            ASSERT(bsct::EncodingType::XML == mX.requestEncoding());

            bsct::MimeSettings mimeSettings(&ta);
            ASSERT(true == mX.getMimeSettings(&mimeSettings));
            ASSERT(mimeSettings == bsct::MimeSettings());
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
// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ------------------------------ END-OF-FILE ---------------------------------
