[% PROCESS svc_util.t -%]
// [% pkg %]_entry.cpp   -*-C++-*-

#include <bdes_ident.h>
BDES_IDENT_RCSID([% pkg %]_entry_cpp,"\$Id\$ \$CSID\$ \$CCId\$")

#include <[% pkg %]_entry.h>
#include <[% pkg %]_manifest.h>
#include <[% pkg %]_requestprocessor.h>
#include <[% pkg %]_requestrouter.h>

#include <bassvc_aggregaterequestrouter.h>
#include <bassvc_servicemanifest.h>

#ifndef BAS_AGGREGATE_ROUTER
#include <bassvc_requestrouteradapter.h>
#endif

#include <bael_log.h>

#include <bcem_aggregate.h>

#include <bdema_managedptr.h>
#include <bsls_assert.h>
#include <bslma_default.h>

#include <bsl_iostream.h>
#include <bsl_stdexcept.h>

namespace BloombergLP {
namespace [% namespace %] {

namespace {

int createServiceImpl(
        bcema_SharedPtr<RequestRouter> *requestRouter,
        bassvc::ServiceManifest        *manifest,
        const bsl::string              *serviceName,
        const bcem_Aggregate&           configuration,
        bslma_Allocator                *basicAllocator)
{
    BSLS_ASSERT(requestRouter);

    if (manifest) {
        manifest->reset();
        manifest->name()            = Manifest::name();
        manifest->description()     = Manifest::description();
        manifest->majorVersion()    = Manifest::majorVersion();
        manifest->minorVersion()    = Manifest::minorVersion();
        manifest->schemaNamespace() = Manifest::schemaNamespace();
        manifest->requestElement()  = Manifest::requestElement();
        manifest->responseElement() = Manifest::responseElement();
    }

    bslma_Allocator *allocator = bslma_Default::allocator(basicAllocator);

    if (0 != serviceName) {
        RequestProcessor *processor = new (*allocator)
                RequestProcessor(*serviceName, configuration, allocator);

        bdema_ManagedPtr<RequestProcessor>
                processor_mp(processor, allocator);

        requestRouter->load(
                new (*allocator)
                    RequestRouter(processor_mp,
                                  *serviceName,
                                  configuration,
                                  allocator),
                allocator);
    }
    else {
        RequestProcessor *processor = new (*allocator)
                RequestProcessor(configuration, allocator);

        bdema_ManagedPtr<RequestProcessor>
                processor_mp(processor, allocator);

        requestRouter->load(
                new (*allocator)
                    RequestRouter(processor_mp,
                                  configuration,
                                  allocator),
                allocator);
    }

    return 0;
}
}  // close unnamed namespace

                                // ------------
                                // struct Entry
                                // ------------

int Entry::createService(
        bcema_SharedPtr<RequestRouter> *requestRouter,
        bassvc::ServiceManifest        *manifest,
        const bsl::string&              serviceName,
        const bcem_Aggregate&           configuration,
        bslma_Allocator                *basicAllocator)
{
    return createServiceImpl(requestRouter,
                             manifest,
                             &serviceName,
                             configuration,
                             basicAllocator);
}

int Entry::createService(
        bcema_SharedPtr<BuildOpts::RequestRouter> *requestRouter,
        bassvc::ServiceManifest                   *manifest,
        const bcem_Aggregate&                      configuration,
        bslma_Allocator                           *basicAllocator)
{
    bcema_SharedPtr<RequestRouter> router_sp;
    int rc = createServiceImpl(&router_sp,
                               manifest,
                               0,
                               configuration,
                               basicAllocator);
    if (0 == rc) {
        *requestRouter = router_sp;
    }
    return rc;
}

}  // close namespace [% namespace %]

int [% pkg %]_Entry__createService(
        bcema_SharedPtr<bassvc::AggregateRequestRouter> *requestRouter,
        bassvc::ServiceManifest                         *manifest,
        const bcem_Aggregate&                            configuration,
        bslma_Allocator                                 *basicAllocator)
{
    BAEL_LOG_SET_CATEGORY("[% SERVICE %].ENTRY");
[% SET offlen = namespace.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]

    int rc = 0;

    try {
        bcema_SharedPtr<[% pkg %]::BuildOpts::RequestRouter> router_sp;
        rc = [% namespace %]::Entry::createService(&router_sp,
                                    [% offset %]manifest,
                                    [% offset %]configuration,
                                    [% offset %]basicAllocator);
        if (0 == rc) {
#ifndef BAS_AGGREGATE_ROUTER
            bcema_SharedPtr<bassvc::RequestRouterAdapter> adapter_sp;
            adapter_sp.createInplace(basicAllocator, router_sp);
            *requestRouter = adapter_sp;
#else
            *requestRouter = router_sp;
#endif
        }
    }
    catch(bsl::exception& e) {
        BAEL_LOG_ERROR << e.what() << BAEL_LOG_END;
        rc = 1;
    }
    catch(...) {
        BAEL_LOG_ERROR << "Unknown exception occurred" << BAEL_LOG_END;
        rc = 2;
    }

    return rc;
}

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
