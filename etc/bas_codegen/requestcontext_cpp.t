[% PROCESS svc_util.t -%]
// [% pkg %]_requestcontext.cpp   -*-C++-*-

#include <bdes_ident.h>
BDES_IDENT_RCSID([% pkg %]_requestcontext_cpp,"\$Id\$ \$CSID\$ \$CCId\$")

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

#include <bael_scopedattribute.h>

#include <bslma_allocator.h>
#include <bslma_default.h>
#include <bsls_assert.h>

namespace BloombergLP {
namespace [% namespace %] {

namespace {

const char LOG_CATEGORY[] = "[% SERVICE %].REQUESTCONTEXT";

}  // close unnamed namespace

                            // --------------------
                            // class RequestContext
                            // --------------------

// CREATORS

RequestContext::RequestContext(
        bdema_ManagedPtr<BuildOpts::RequestContext>&  context,
        bslma_Allocator                              *basicAllocator)
: d_imp_mp(context)
{
    BSLS_ASSERT(d_imp_mp);
}

RequestContext::~RequestContext()
{
}

// MANIPULATORS

[% IF opts.noSchema -%]
int RequestContext::deliverResponse(
        const bcema_Blob& response,
        bool              isFinal)
{
    return d_imp_mp->deliverResponse(response, isFinal);
}

[% ELSE -%]
[% FOREACH response = svc.responses -%]
[% SET offlen = -4 + response.type.length -%]
int RequestContext::deliver[% response.name | MixedMixed %](
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
        bool [% offset %]isFinal)
{
    [% MSGNS %][% ResponseType %] rsp;
    rsp.make[% response.memberName | MixedMixed %](response);
    return d_imp_mp->deliverResponse(rsp, isFinal);
}

[% END -%]
[% SET offlen = ResponseType.length + MSGNS.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
int RequestContext::deliverResponse(
        const [% MSGNS %][% ResponseType %]& response,
        bool  [% offset %]  isFinal)
{
[% IF 0 < svc.numResponses -%]
    bael_ScopedAttribute attribute("response", response.selectionName());

[% END -%]
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
    BAEL_LOG_DEBUG << "Delivering response: "
                      "userInfo = " << userIdentification() << ", "
                      "isFinal = "  << isFinal              << ", "
                      "response = " << response
                   << BAEL_LOG_END;

    int rc = d_imp_mp->deliverResponse(response, isFinal);
    if (0 != rc) {
        BAEL_LOG_ERROR << "Failed to deliver response: "
                          "rc = "       << rc << ", "
                          "userInfo = " << userIdentification()
                       << BAEL_LOG_END;
    }

    return rc;
}

[% END -%]
int RequestContext::deliverAcknowledgment()
{
    bael_ScopedAttribute attribute("response", "ACK");

    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
    BAEL_LOG_DEBUG << "Delivering acknowledgment: "
                      "userInfo = " << userIdentification()
                   << BAEL_LOG_END;

    return d_imp_mp->deliverAcknowledgment();
}

int RequestContext::deliverError(
        const bsct::ErrorInfo& errorInfo,
        bool                   reroutableFlag)
{
    bael_ScopedAttribute attribute("response", "ERROR");

    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
    BAEL_LOG_DEBUG << "Delivering error: "
                      "userInfo = "       << userIdentification() << ", "
                      "reroutableFlag = " << reroutableFlag       << ", "
                      "errorInfo = "      << errorInfo
                   << BAEL_LOG_END;

    return d_imp_mp->deliverError(errorInfo, reroutableFlag);
}

int RequestContext::deliverError(
        const bsct::ErrorInfo&        errorInfo,
        const bsct::RouteDescription& routeOverride)
{
    return d_imp_mp->deliverError(errorInfo, routeOverride);
}

bslma_Allocator *RequestContext::sessionAllocator() const
{
    return d_imp_mp->sessionAllocator();
}

bool RequestContext::setMimeSettings(const bsct::MimeSettings& settings)
{
    return d_imp_mp->setMimeSettings(settings);
}

// ACCESSORS

bsct::EncodingType::Value RequestContext::requestEncoding() const
{
    return d_imp_mp->requestEncoding();
}

bool RequestContext::getMimeSettings(bsct::MimeSettings *result) const
{
    return d_imp_mp->getMimeSettings(result);
}

bool RequestContext::isOneWayRequest() const
{
    return d_imp_mp->isOneWayRequest();
}

bool RequestContext::isAckRequested() const
{
    return d_imp_mp->isAckRequested();
}

const bsct::UserIdentification& RequestContext::userIdentification() const
{
    return d_imp_mp->userIdentification();
}

}  // close namespace [% namespace %]
}  // close namespace BloombergLP

// GENERATED BY [% version %] [% timestamp %]
// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ------------------------------ END-OF-FILE ---------------------------------
