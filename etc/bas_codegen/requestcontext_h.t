[% PROCESS svc_util.t -%]
// [% pkg %]_requestcontext.h   -*-C++-*-
#ifndef INCLUDED_[% PKG %]_REQUESTCONTEXT
#define INCLUDED_[% PKG %]_REQUESTCONTEXT

#ifndef INCLUDED_BDES_IDENT
#include <bdes_ident.h>
#endif
BDES_IDENT_RCSID([% pkg %]_requestcontext_h,"\$Id\$ \$CSID\$ \$CCId\$")
BDES_IDENT_PRAGMA_ONCE

//@PURPOSE: Provide a context for processing [% SERVICE %] service requests.
//
//@CLASSES:
// [% namespace %]::RequestContext: a context for processing [% SERVICE %] service requests
//
//@SEE_ALSO: bassvc_aggregaterequestcontext, bassvc_requestcontext
//
//@AUTHOR: [% svc.author %]
//
///Usage Examples
///--------------
// TBD
//..
//..

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
#ifndef INCLUDED_BSCT_ENCODINGTYPE
#include <bsct_encodingtype.h>
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

namespace BloombergLP {

class bslma_Allocator;

namespace bsct { class ErrorInfo; }
namespace bsct { class MimeSettings; }
namespace bsct { class RouteDescription; }
namespace bsct { class UserIdentification; }

namespace [% namespace %] {

                            // ====================
                            // class RequestContext
                            // ====================

class RequestContext {
[% formatComment("This class defines a context for processing requests.  It contains information about the request originator, available through the 'userInformation' method, as well as information about the request itself, such as the request encoding type, the type of response expected, and so on.  The class also provides various \"delivery\" methods, which are used to deliver a particular type of response.  Each delivery method takes an optional 'isFinal' argument, which, if set to 'false', allows the request processor to deliver multiple responses (the last of which must be sent with 'isFinal' set to 'true').", 4) %]

    // INSTANCE DATA
    bdema_ManagedPtr<BuildOpts::RequestContext> d_imp_mp;  // implementation

  private:
    // NOT IMPLEMENTED
    RequestContext(const RequestContext& original);
    RequestContext& operator=(const RequestContext& rhs);

  public:
    // TRAITS
    BSLALG_DECLARE_NESTED_TRAITS(RequestContext,
                                 bslalg_TypeTraitUsesBslmaAllocator);

    // CREATORS
    explicit
    RequestContext(
            bdema_ManagedPtr<BuildOpts::RequestContext>&  context,
            bslma_Allocator                              *basicAllocator = 0);
        // Create a request context implemented with the specified 'context'.
        // Optionally specify a 'basicAllocator', used to supply memory.  If
        // 'basicAllocator' is 0, the currently installed default allocator is
        // used.

    ~RequestContext();
        // Destroy this object.

    // MANIPULATORS [% -%]
[%- IF opts.noSchema %]
    int deliverResponse(const bcema_Blob& response,
                        bool              isFinal = true);
[%- ELSE %]
[%- FOREACH response = svc.responses %]
[% SET offlen = -4 + response.type.length -%]
    int deliver[% response.name | MixedMixed %](
[% IF response.noNamespaceFlag -%]
[% IF response.isPrimitiveFlag -%]
            [% response.type %] response,
[% ELSE -%]
            const [% response.type %]& response,
[% SET offlen = offlen + 7 -%]
[% END -%]
[% ELSE -%]
            const [% MSGNS %][% response.type %]& response,
[% SET offlen = offlen + 7 + MSGNS.length -%]
[% END -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
            bool [% offset %]isFinal = true);
[% END %]
[% SET offlen = ResponseType.length + MSGNS.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
    int deliverResponse(
            const [% MSGNS %][% ResponseType %]& response,
            bool  [% offset %]  isFinal = true);
[%- END %]
        // Translate the specified 'response' into an abstraction understood by
        // the underlying I/O layer (e.g., 'bcema_Blob'), and deliver it to the
        // underlying raw data handler.  Optionally specify 'isFinal', used to
        // identify whether this response is the final response to the request
        // associated with this context.  Return 0 on success, and a non-zero
        // value otherwise.  If 'isFinal' is 'false', then the specified
        // 'payload' is considered to be the part of a response, and this
        // object can be used in the future to send another response to the
        // described request.  Otherwise, a user cannot call any flavor of
        // 'deliverResponse' if this call is sucessful.

    int deliverAcknowledgment();
       // Deliver to the client an acknowledgment that the request was
       // processed.  Return 0 on success, and a non-zero value otherwise.
       // Note that this method will fail unless the client requested an
       // acknowledgment.

    int deliverError(const bsct::ErrorInfo& errorInfo,
                     bool                   reroutableFlag = false);
        // Deliver the specified 'errorInfo' error message to the client with
        // the optionally specified 'reroutableFlag' value.  Return 0 on
        // success, and a non-zero value otherwise.

    int deliverError(const bsct::ErrorInfo&        errorInfo,
                     const bsct::RouteDescription& routeOverride);
        // Deliver the specified 'errorInfo' error message to the client and
        // include the specified 'routeOverride' in the message, to be used
        // by the client to control the rerouting.  The reroutable flag will be
        // set to 'true'.  Return 0 on success, and a non-zero value otherwise.

    bslma_Allocator *sessionAllocator() const;
        // Return the allocator used to allocate this object.  The allocator
        // returned by this method is guaranteed to remain valid for the
        // lifetime of this object.  In particular, the returned allocator may
        // be used to allocate storage for this request context object, which
        // may then be associated with a callback method provided to an
        // asynchronous API.

    bool setMimeSettings(const bsct::MimeSettings& settings);
        // Set the MIME related information associated with the current
        // request to 'settings'.  Return 'true' on success, or 'false'
        // otherwise.  On failure, the context's MIME settings are undefined.

    // ACCESSORS
    bsct::EncodingType::Value requestEncoding() const;
        // Return the encoding of the request described this context.

    bool getMimeSettings(bsct::MimeSettings *result) const;
        // Load into the specified 'result' the MIME related information
        // associated with the current request.  Return 'true' on success, or
        // 'false', with no effect on 'result', if the request has no MIME
        // information.

    bool isOneWayRequest() const;
        // Return 'true' if the request described by this context is a one way
        // request, or 'false' otherwise.

    bool isAckRequested() const;
        // Returns true if and only if the request is a one-way request, and
        // the client has requested that an acknowledgment be sent.

    const bsct::UserIdentification& userIdentification() const;
        // Return a reference to the non-modifiable information about the
        // originator of the request.
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
// ------------------------------ END-OF-FILE ---------------------------------
