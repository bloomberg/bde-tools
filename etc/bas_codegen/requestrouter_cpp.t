[% PROCESS svc_util.t -%]
// [% pkg %]_requestrouter.cpp   -*-C++-*-

#include <bdes_ident.h>
BDES_IDENT_RCSID([% pkg %]_requestrouter_cpp,"\$Id\$ \$CSID\$ \$CCId\$")

#include <[% pkg %]_requestrouter.h>
#include <[% pkg %]_requestcontext.h>
#include <[% pkg %]_requestprocessor.h>

#include <bascfg_configutil.h>
#include <basm_metrics.h>

#include <bsct_errorinfo.h>

#include <bael_log.h>
#include <bael_scopedattribute.h>
#include <baem_metrics.h>
#include <baem_publicationtype.h>

#include <bcem_aggregate.h>

#include <bslalg_scalarprimitives.h>
#include <bslma_allocator.h>
#include <bslma_default.h>
#include <bsls_assert.h>
#include <bsls_stopwatch.h>

#include <bsl_sstream.h>

namespace BloombergLP {
namespace [% namespace %] {

namespace {

const char LOG_CATEGORY[] = "[% SERVICE %].REQUESTROUTER";

}  // close unnamed namespace

                            // -------------------
                            // class RequestRouter
                            // -------------------

[% UNLESS opts.noSchema || 0 == svc.numRequests -%]
// PRIVATE MANIPULATORS

inline
void RequestRouter::dispatchRequest(
        bdema_ManagedPtr<[% MSGNS %][% RequestType %]>& request,
        bdema_ManagedPtr<RequestContext>& context)
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    // ---------- CHANGE ONLY ARGUMENTS TO METHOD CALLS IN CODE BELOW ---------
    typedef [% MSGNS %][% RequestType %] Msg;

    bael_ScopedAttribute attribute("request", request->selectionName());

    BAEL_LOG_DEBUG << "Received request: "
                      "userInfo = " << context->userIdentification() << ", "
                      "request = "  << *request
                   << BAEL_LOG_END;

    bsls_Stopwatch timer;

    BAEM_METRICS_IF_CATEGORY_ENABLED(d_metricsCategory.c_str()) {
        timer.start(true);
    }
    switch (request->selectionId()) {
[% FOREACH request = svc.requests -%]
      case Msg::SELECTION_ID_[% request.memberName | UPPER_UPPER %]: {
[% IF request.noNamespaceFlag -%]
[% IF request.isPrimitiveFlag -%]
        [% request.type %] requestValue =
                request->[% request.memberName | mixedMixed %]();
        d_requestProcessor_mp->process[% request.name %](requestValue, [% -%]
                                                   [%- %]context);
[% ELSE -%]
        bdema_ManagedPtr<[% request.type %][% -%]
        [%- request.isVectorFlag ? ' ' : '' -%]
        [%- %]>
            request_mp(request, &request->[% request.memberName | mixedMixed %]());
        d_requestProcessor_mp->process[% request.name %](request_mp, [% -%]
                                                   [%- %]context);
[% END -%]
[% ELSE -%]
        bdema_ManagedPtr<[% MSGNS %][% request.type %]>
            request_mp(request, &request->[% request.memberName | mixedMixed %]());
        d_requestProcessor_mp->process[% request.name %](request_mp, [% -%]
                                                   [%- %]context);
[% END -%]
        BASM_METRICS_COLLECT_REQUEST_TIMING(d_metricsCategory.c_str(),
                                            "[% request.memberName %]",
                                            timer);
      }  break;
[% END -%]
      default: {
        bsl::ostringstream oss;
        oss << "Could not process request: Unknown request: id = "
            << request->selectionId();
        BAEL_LOG_WARN << context->userIdentification()
                      << oss.str()
                      << BAEL_LOG_END;
        bsct::ErrorInfo errorInfo;
        errorInfo.description() = oss.str();
        context->deliverError(errorInfo);
        return;                                                       // RETURN
      }
    }

    // ---------- CHANGE ONLY ARGUMENTS TO METHOD CALLS IN CODE ABOVE ---------
}

[% END -%]
// CREATORS

RequestRouter::RequestRouter(
        bdema_ManagedPtr<RequestProcessor>&  processor,
        const bcem_Aggregate&                configuration,
        bslma_Allocator                     *basicAllocator)
: d_requestProcessor_mp(processor)
, d_metricsCategory(basicAllocator)
, d_allocator_p(bslma_Default::allocator(basicAllocator))
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    BSLS_ASSERT(d_requestProcessor_mp);

    d_imp_p = reinterpret_cast<RequestRouterImp*>(
                  d_allocator_p->allocate(sizeof *d_imp_p));
    bslalg_ScalarPrimitives::defaultConstruct(d_imp_p, d_allocator_p);

    bcem_Aggregate serviceId =
            bascfg::ConfigUtil::findServiceId(configuration);
    d_metricsCategory.assign(serviceId.asString()).append("-CORE");
    BSLS_ASSERT(!serviceId.isError());

    // The 'configuration' may be used to further configure this object.
}

RequestRouter::RequestRouter(
        bdema_ManagedPtr<RequestProcessor>&  processor,
        const bsl::string&                   serviceName,
        const bcem_Aggregate&                configuration,
        bslma_Allocator                     *basicAllocator)
: d_requestProcessor_mp(processor)
, d_metricsCategory(basicAllocator)
, d_allocator_p(bslma_Default::allocator(basicAllocator))
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    BSLS_ASSERT(d_requestProcessor_mp);

    d_imp_p = reinterpret_cast<RequestRouterImp*>(
                  d_allocator_p->allocate(sizeof *d_imp_p));
    bslalg_ScalarPrimitives::defaultConstruct(d_imp_p, d_allocator_p);

    bcem_Aggregate serviceId =
            bascfg::ConfigUtil::findServiceId(configuration, serviceName);
    d_metricsCategory.assign(serviceId.asString()).append("-CORE");
    BSLS_ASSERT(!serviceId.isError());

    // The 'configuration' may be used to further configure this object.
}

RequestRouter::~RequestRouter()
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    // Explicitly destroy request processor in case it is holding objects
    // allocated by the router imp
    d_requestProcessor_mp.clear();

    bslalg_ScalarPrimitives::destruct(d_imp_p, d_allocator_p);
    d_allocator_p->deallocate(d_imp_p);
}

// MANIPULATORS

void RequestRouter::processRequest(
        bdema_ManagedPtr<BuildOpts::RawRequest>&      rawRequest,
        bdema_ManagedPtr<BuildOpts::RequestContext>&  context)
{
[% IF opts.noSchema -%]
    bdema_ManagedPtr<RequestContext> context_mp;
    d_imp_p->createRequestContext(&context_mp, context);

    d_requestProcessor_mp->processRequest(rawRequest, context_mp);
[% ELSE -%]
    typedef [% MSGNS %][% RequestType %] Request;

    bdema_ManagedPtr<Request> request_mp;
    d_imp_p->createRequest(&request_mp);

    int rc = d_imp_p->decodeRequest(request_mp.ptr(), rawRequest, context);
    if (0 != rc) {
        return;
    }

    bdema_ManagedPtr<RequestContext> context_mp;
    d_imp_p->createRequestContext(&context_mp, context);

[% IF 0 == svc.numRequests -%]
    d_requestProcessor_mp->processRequest(request_mp, context_mp);
[% ELSE -%]
    dispatchRequest(request_mp, context_mp);
[% END -%]
[% END -%]
}

void RequestRouter::processControlEvent(
        const bassvc::RequestProcessorControlEvent& event)
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    d_requestProcessor_mp->processControlEvent(event);
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
// ------------------------------- END-OF-FILE --------------------------------
