[% PROCESS svc_util.t -%]
// [% pkg %]_requestprocessor.h   -*-C++-*-
#ifndef INCLUDED_[% PKG %]_REQUESTPROCESSOR
#define INCLUDED_[% PKG %]_REQUESTPROCESSOR

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT_RCSID([% pkg %]_requestprocessor_h,"\$Id\$ \$CSID\$ \$CCId\$")
BDES_IDENT_PRAGMA_ONCE

//@PURPOSE: Provide a [% SERVICE %] service request processor.
//
//@CLASSES:
// [% namespace %]::RequestProcessor: a request processor for the [% SERVICE %] service
//
//@AUTHOR: [% svc.author %]
//
//@DESCRIPTION: Provide a $SERVICE service request processor.
[% formatComment(String.new("Individual application-level requests are handled in like-named 'processXXX' methods.  Responses (including application-level errors) are returned through the associated 'context'.  Both requests and contexts may be cached if asynchronous processing is required.  However, all cached request and response data must be released when the STOP event is received."), 0) %]

#ifndef INCLUDED_[% PKG %]_VERSION
#include <[% pkg %]_version.h>
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
#ifndef INCLUDED_BCEM_AGGREGATE
#include <bcem_aggregate.h>
#endif

#ifndef INCLUDED_BDEMA_MANAGEDPTR
#include <bdema_managedptr.h>
#endif

#ifndef INCLUDED_BSLALG_TYPETRAITS
#include <bslalg_typetraits.h>
#endif

#ifndef INCLUDED_BSLALG_TYPETRAITUSESBSLMAALLOCATOR
#include <bslalg_typetraitusesbslmaallocator.h>
#endif

#ifndef INCLUDED_BSL_STRING
#include <bsl_string.h>
#define INCLUDED_BSL_STRING
#endif

namespace BloombergLP {

class bslma_Allocator;

[% IF opts.noSchema -%]
class bcema_Blob;

[% END -%]
namespace bassvc { class RequestProcessorControlEvent; }

namespace [% namespace %] { class RequestContext; }
namespace [% namespace %] {

                           // ======================
                           // class RequestProcessor
                           // ======================

class RequestProcessor {
[% formatComment(String.new("This class provides a $svc.serviceName service request processor.  Individual application-level requests are handled in like-named 'processXXX' methods.  Responses (including application-level errors) are returned through the associated 'context'.  Both requests and contexts may be cached if asynchronous processing is required."), 4) %]

    // INSTANCE DATA
    bslma_Allocator *d_allocator_p;      // memory allocator (held)
    bcem_Aggregate   d_configuration;    // configuration object
    bsl::string      d_metricsCategory;  // metrics category name

  private:
    // NOT IMPLEMENTED
    RequestProcessor(const RequestProcessor&);
    RequestProcessor& operator=(const RequestProcessor&);

  public:
    // TRAITS
    BSLALG_DECLARE_NESTED_TRAITS(RequestProcessor,
                                 bslalg_TypeTraitUsesBslmaAllocator);

    // CREATORS
    explicit
    RequestProcessor(const bcem_Aggregate&  configuration,
                     bslma_Allocator       *basicAllocator = 0);
        // Create a request processor initialized with the specified
        // 'configuration'.  Optionally specify a 'basicAllocator' used to
        // supply memory.  If 'basicAllocator' is 0, the currently-installed
        // default allocator is used.

    RequestProcessor(const bsl::string&     serviceName,
                     const bcem_Aggregate&  configuration,
                     bslma_Allocator       *basicAllocator = 0);
        // Create a request processor initialized with the specified
        // 'serviceName' and 'configuration'.  Optionally specify a
        // 'basicAllocator' used to supply memory.  If 'basicAllocator' is 0,
        // the currently-installed default allocator is used.

    ~RequestProcessor();
        // Destroy this object.

    // MANIPULATORS
    // ---------- DO NOT EDIT BELOW THIS LINE EXCEPT TO ADD PARAMETERS --------
    // Control Events
    void processControlEvent(
            const bassvc::RequestProcessorControlEvent& event);
        // Process the specified 'event' in a synchronous fashion.  Any state
        // held by the request processor (e.g., requests and request contexts)
        // must be cleaned up when the STOP event is received.

    // Messages
[% IF opts.noSchema -%]
    void processRequest(
            bdema_ManagedPtr<bcema_Blob>&     request,
            bdema_ManagedPtr<RequestContext>& context);
        // Process the specified 'request'.  Return any responses via the
        // specified 'context'.
[% ELSIF 0 == svc.numRequests -%]
    void processRequest(
            bdema_ManagedPtr<[% MSGNS %][% RequestType %]>& request,
            bdema_ManagedPtr<RequestContext>& context);
        // Process the specified 'request'.  Return any responses via the
        // specified 'context'.
[% ELSE -%]
[% FOREACH request = svc.requests -%]
    void process[% request.name %](
[% IF request.noNamespaceFlag -%]
[% IF request.isPrimitiveFlag -%]
[% SET offlen = request.type.length -%]
[% SET offlen = 33 - offlen -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
            [% request.type %] [% offset %][% request.argumentName %],
[% ELSE -%]
            bdema_ManagedPtr<[% request.type %][% -%]
            [%- request.isVectorFlag ? ' ' : '' -%]
            [%- %]>& [% request.argumentName %],
[% END -%]
[% ELSE -%]
            bdema_ManagedPtr<[% MSGNS %][% request.type %]>& [% -%]
            [%- request.argumentName %],
[% END -%]
            bdema_ManagedPtr<RequestContext>& context);
[% END -%]
        // Process the specified 'request'.  Return any responses via the
        // specified 'context'.
[% END -%]
};

// ============================================================================
//                          INLINE FUNCTION DEFINITIONS
// ============================================================================

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
