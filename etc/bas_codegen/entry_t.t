[% PROCESS svc_util.t -%]
// [% pkg %]_entry.t.cpp   -*-C++-*-

#ifndef lint
static char RCSid_[% pkg %]_entry_t_cpp[] = [% -%]
[%- %]"\$Id: \$ \$CCId: \$  \$CSID:  \$  \$SCMId:  \$";
#endif

#include <[% pkg %]_entry.h>
#include <[% pkg %]_configschema.h>
#include <[% pkg %]_requestrouter.h>

[% UNLESS opts.noBBEnv -%]
#include <a_basfs_serviceoffline.h>

[% END -%]
#include <bassvc_requestrouter.h>
#include <bassvc_servicemanifest.h>
#include <bassvc_serviceoffline.h>

#include <bcem_aggregate.h>
#include <bcema_testallocator.h>

#include <bdema_allocator.h>
#include <bdema_managedptr.h>
#include <bdesb_fixedmeminstreambuf.h>

#include <cstdlib>
#include <cstring>
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
// FREE FUNCTIONS
// [ 1] int createService(
//              bdem_ManagedPtr<bassvc::RequestRouter> *result,
//              const bcem_Aggregate&                   configuration,
//              bdema_Allocator                        *basicAllocator = 0);
// [ 1] void getServiceManifest(bassvc::ServiceManifest *result);
//
// EXTERN "C" INTERFACE
// [ 2] int [% pkg %]_Entry__createService(void *, void *, void *);
// [ 2] int [% pkg %]_Entry__getServiceManifest(void *);
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
typedef RequestRouter Obj;
[% IF opts.noSchema -%]
typedef bcema_Blob Req;
typedef bcema_Blob Rsp;
[% ELSE -%]
typedef [% MSGNS %][% RequestType %] Req;
typedef [% MSGNS %][% ResponseType %] Rsp;
[% END -%]

[% IF opts.noBBEnv -%]
typedef bassvc::ServiceOffline Offline;
[% ELSE -%]
typedef a_basfs::ServiceOffline Offline;
[% END -%]

static int verbose = 0;
static int veryVerbose = 0;
static int veryVeryVerbose = 0;
static int veryVeryVeryVerbose = 0;

// TBD: add to the default configuration if necessary.
static const char DEFAULT_CONFIGURATION[] =
"<?xml version='1.0' encoding='UTF-8' ?>\n"
"<Configuration xmlns='[% svc.targetNamespace %]'>\n"
"  <BasConfig>\n"
"    <ServiceInstance>\n"
"      <Name>[% SERVICE %]</Name>\n"
"      <ServiceId>21945</ServiceId>\n"
"      <Version>1.0.0</Version>\n"
"    </ServiceInstance>\n"
"\n"
"    <ServiceOfflineConfig>\n"
"      <OfflineConfig>\n"
"        <Name>[% service %]</Name>\n"
"        <LoggingConfig>\n"
"          <VerbosityLevel>2</VerbosityLevel>\n"
"        </LoggingConfig>\n"
"        <ThreadPoolConfig/>\n"
"      </OfflineConfig>\n"
"    </ServiceOfflineConfig> \n"
"  </BasConfig>\n"
"</Configuration>\n"
;

const char SCHEMA[] =
[% svc.text | c_str %]
;

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

    switch (test) { case 0:  // Zero is always the leading case.
      case 2: {
        // --------------------------------------------------------------------
        // BREATHING TEST: EXTERN "C" INTERFACE
        //
        // Concerns:
        //   Exercise the basic functionality of the 'Entry' class.  We want to
        //   ensure that request processor objects can be instantiated and
        //   destroyed.  We also want to exercise the primary manipulators and
        //   accessors.
        //
        // Plan:
        //   Instantiate a service offline, 'mX'.  Obtain the service manifest
        //   by calling the '[% pkg %]_Entry__getServiceManifest' method, and
        //   verify that is it correct.  Then, obtain a request router by
        //   calling the '[% pkg %]_Entry__createService' method, and
        //   register it with 'mX'.
        //
        // Testing:
        //   Exercise basic functionality.
        // --------------------------------------------------------------------

        if (verbose) {
            std::cout << "BREATHING TEST: extern \"C\" interface" << std::endl
                      << "====================================" << std::endl;
        }

        bcema_TestAllocator ta(veryVeryVeryVerbose);
        {
            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Initialization

            Offline mX(&ta);
            bdesb_FixedMemInStreamBuf buf(DEFAULT_CONFIGURATION,
                                          sizeof DEFAULT_CONFIGURATION -1);
            ASSERT(0 == mX.configure(buf, ConfigSchema::TEXT));

            bcem_Aggregate configuration = mX.configuration();

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            bassvc::ServiceManifest MANIFEST(&ta);
            MANIFEST.majorVersion() = 1;
            MANIFEST.minorVersion() = 0;
            MANIFEST.name().assign("[% SERVICE %]");
            MANIFEST.description().assign("TBD: provide service description");
            MANIFEST.schema().assign(SCHEMA);
            MANIFEST.requestElement().assign("[% svc.requestElement %]");
            MANIFEST.responseElement().assign("[% svc.responseElement %]");

            bassvc::ServiceManifest manifest(&ta);
            [% pkg %]_Entry__getServiceManifest(&manifest);
            ASSERT(MANIFEST == manifest);

            bdema_ManagedPtr<bassvc::RequestRouter> router_mp;
            ASSERT(0 == [% pkg %]_Entry__createService(
                                             &router_mp, &configuration, &ta));

            bcem_Aggregate services = configuration.field("BasConfig",
                                                          "ServiceInstance");
            ASSERT(1 == services.length());

            ASSERT(0 == mX.registerService("[% SERVICE %]",
                                           manifest,
                                           router_mp));
        }
        ASSERT(0 <  ta.numAllocation());
        ASSERT(0 == ta.numBytesInUse());
      }  break;
      case 1: {
        // --------------------------------------------------------------------
        // BREATHING TEST
        //
        // Concerns:
        //   Exercise the basic functionality of the 'Entry' class.  We want to
        //   ensure that request processor objects can be instantiated and
        //   destroyed.  We also want to exercise the primary manipulators and
        //   accessors.
        //
        // Plan:
        //   Instantiate a service offline, 'mX'.  Obtain the service manifest
        //   by calling the 'getServiceManifest' method, and verify that is it
        //   correct.  Then, obtain a request router by calling the
        //   'createService' method, and register it with 'mX'.
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

            Offline mX(&ta);
            bdesb_FixedMemInStreamBuf buf(DEFAULT_CONFIGURATION,
                                          sizeof DEFAULT_CONFIGURATION -1);
            ASSERT(0 == mX.configure(buf, ConfigSchema::TEXT));

            bcem_Aggregate configuration = mX.configuration();

            // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
            // Test Execution

            bassvc::ServiceManifest MANIFEST(&ta);
            MANIFEST.majorVersion() = 1;
            MANIFEST.minorVersion() = 0;
            MANIFEST.name().assign("[% SERVICE %]");
            MANIFEST.description().assign("TBD: provide service description");
            MANIFEST.schema().assign(SCHEMA);
            MANIFEST.requestElement().assign("[% svc.requestElement %]");
            MANIFEST.responseElement().assign("[% svc.responseElement %]");

            bassvc::ServiceManifest manifest(&ta);
            Entry::getServiceManifest(&manifest);
            ASSERT(MANIFEST == manifest);

            bdema_ManagedPtr<bassvc::RequestRouter> router_mp;
            ASSERT(0 == Entry::createService(&router_mp, configuration, &ta));

            bcem_Aggregate services = configuration.field("BasConfig",
                                                          "ServiceInstance");
            ASSERT(1 == services.length());

            ASSERT(0 == mX.registerService("[% SERVICE %]",
                                           manifest,
                                           router_mp));
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
