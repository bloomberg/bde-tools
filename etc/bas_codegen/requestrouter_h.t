[% PROCESS svc_util.t -%]
// [% pkg %]_requestrouter.h   -*-C++-*-
#ifndef INCLUDED_[% PKG %]_REQUESTROUTER
#define INCLUDED_[% PKG %]_REQUESTROUTER

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT_RCSID([% pkg %]_requestrouter_h,"\$Id\$ \$CSID\$ \$CCId\$")
BDES_IDENT_PRAGMA_ONCE

//@PURPOSE: Provide a [% SERVICE %] service request router.
//
//@CLASSES:
// [% namespace %]::RequestRouter: a [% SERVICE %] service request router
//
//@SEE_ALSO: bassvc_requestrouter
//
//@AUTHOR: [% svc.author %]
//
//@DESCRIPTION: This class provides a concrete implementation of the
[% formatComment(String.new("'bassvc::RequestRouter' protocol to marshall and route $svc.serviceName service messages between the BAS framework and the application-level request processor."), 0) %]

#ifndef INCLUDED_[% PKG %]_VERSION
#include <[% pkg %]_version.h>
#endif

#ifndef INCLUDED_[% PKG %]_BUILDOPTS
#include <[% pkg %]_buildopts.h>
#endif

[% UNLESS opts.noSchema -%]
[% IF opts.msgExpand -%]
#ifndef INCLUDED_[% MSGPKG %]_[% requestType | UPPER_UPPER %]
#include <[% msgpkg %]_[% requesttype %].h>
#endif

#ifndef INCLUDED_[% MSGPKG %]_[% responseType | UPPER_UPPER %]
#include <[% msgpkg %]_[% responsetype %].h>
#endif
[% ELSE -%]
#ifndef INCLUDED_[% MSGPKG %]_[% opts.msgComponent | UPPER_UPPER %]
#include <[% msgpkg %]_[% opts.msgComponent %].h>
#endif
[% END -%]

[% END -%]
#ifndef INCLUDED_BSLALG_TYPETRAITS
#include <bslalg_typetraits.h>
#endif

#ifndef INCLUDED_BSLALG_TYPETRAITUSESBSLMAALLOCATOR
#include <bslalg_typetraitusesbslmaallocator.h>
#endif

#ifndef INCLUDED_BDEMA_MANAGEDPTR
#include <bdema_managedptr.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#define INCLUDED_BSL_STRING
#endif

namespace BloombergLP {

class bslma_Allocator;

class bcem_Aggregate;

namespace basapi { class CodecOptions; }

namespace [% namespace %] { class RequestContext; }
namespace [% namespace %] { class RequestProcessor; }
namespace [% namespace %] {

                            // ===================
                            // class RequestRouter
                            // ===================

class RequestRouter : public BuildOpts::RequestRouter {
[% formatComment(String.new("This class provides a concrete implementation of the 'bassvc::RequestRouter' protocol to marshall and route $svc.serviceName service messages between the BAS framework and the application-level request processor."), 4) %]

    // PRIVATE TYPES
    typedef BuildOpts::RequestRouterImp        RequestRouterImp;
    typedef bdema_ManagedPtr<RequestProcessor> RequestProcessorMptr;

    // INSTANCE DATA
    RequestRouterImp     *d_imp_p;                // implementation (owned)
    RequestProcessorMptr  d_requestProcessor_mp;  // request processor
    bsl::string           d_metricsCategory;      // metrics category name
    bslma_Allocator      *d_allocator_p;          // supply memory (held)

[% UNLESS opts.noSchema || 0 == svc.numRequests -%]
    // PRIVATE MANIPULATORS
    void dispatchRequest(
            bdema_ManagedPtr<[% MSGNS %][% RequestType %]>& request,
            bdema_ManagedPtr<RequestContext>& context);
        // Dispatch the specified 'request', accompanied by the specified
        // 'context', to the appropriate application-level processing routine.

[% END -%]
  private:
    // NOT IMPLEMENTED
    RequestRouter(const RequestRouter&);
    RequestRouter& operator=(const RequestRouter&);

  public:
    // TRAITS
    BSLALG_DECLARE_NESTED_TRAITS(RequestRouter,
                                 bslalg_TypeTraitUsesBslmaAllocator);

    // CREATORS
    RequestRouter(bdema_ManagedPtr<RequestProcessor>&  processor,
                  const bcem_Aggregate&                configuration,
                  bslma_Allocator                     *basicAllocator = 0);
        // Create a request route, configured from the specified
        // 'configuration', that routes requests to the specified 'processor'.
        // Optionally specify a 'basicAllocator' used to supply memory.  If
        // 'basicAllocator' is 0, the currently installed default allocator is
        // used.

    RequestRouter(bdema_ManagedPtr<RequestProcessor>&  processor,
                  const bsl::string&                   serviceName,
                  const bcem_Aggregate&                configuration,
                  bslma_Allocator                     *basicAllocator = 0);
        // Create a request route, configured from the specified 'serviceName'
        // and 'configuration', that routes requests to the specified
        // 'processor'.  Optionally specify a 'basicAllocator' used to supply
        // memory.  If 'basicAllocator' is 0, the currently installed default
        // allocator is used.

    ~RequestRouter();
        // Destroy this object.

    // MANIPULATORS
    virtual void processRequest(
            bdema_ManagedPtr<BuildOpts::RawRequest>&      rawRequest,
            bdema_ManagedPtr<BuildOpts::RequestContext>&  context);
        // Process the specified 'rawRequest' and deliver response(s) and/or
        // errors, if any, through the specified 'context'.  If no response
        // and/or errors are delivered through the context and the context
        // is destroyed, the framework will generate a non-reroutable error.

    virtual void processControlEvent(
            const bassvc::RequestProcessorControlEvent& event);
        // Process the specified 'event' in a synchronous fashion.

    RequestProcessor& processor();
        // Return a modifiable reference to the request processor managed by
        // this object.
};

// ============================================================================
//                          INLINE FUNCTION DEFINITIONS
// ============================================================================

// MANIPULATORS
inline
RequestProcessor& RequestRouter::processor()
{
    return *d_requestProcessor_mp;
}

}  // close namespace [% namespace %]
}  // close namespace BloombergLP
#endif

// GENERATED BY [% version %] [% timestamp %]
// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ------------------------------- END-OF-FILE --------------------------------
