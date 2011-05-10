[% PROCESS svc_util.t -%]
// [% pkg %].m.cpp   -*-C++-*-

#include <bdes_ident.h>
BDES_IDENT_RCSID([% service %]_m_cpp,"\$Id\$ \$CSID\$ \$CCId\$")

#include <[% pkg %]_buildopts.h>
[% IF opts.configSchema -%]
#include <[% pkg %]_configschema.h>
[% END -%]
#include <[% pkg %]_entry.h>
#include <[% pkg %]_requestrouter.h>
#include <[% pkg %]_version.h>

#ifndef BAS_NOBBENV
#ifndef INCLUDED_A_BASFS_SERVICEOFFLINE
#include <a_basfs_serviceoffline.h>
#endif
extern "C" {
    void f77override(int, const char**);
}
#else
#ifndef INCLUDED_BASSVC_SERVICEOFFLINE
#include <bassvc_serviceoffline.h>
#endif
#endif

#include <bassvc_servicemanifest.h>

#include <baea_commandline.h>
#include <bael_log.h>

#include <bcem_aggregate.h>
[% IF opts.noSchema -%]
#include <bcema_blob.h>
[% END -%]
#include <bcema_sharedptr.h>
#include <bcema_testallocator.h>

#include <bdesu_processutil.h>

#include <bslma_allocator.h>
#include <bslma_default.h>
#include <bslma_defaultallocatorguard.h>
#include <bsls_assert.h>
#include <bsls_platform.h>

#if defined(BDES_PLATFORM__OS_UNIX)
#include <signal.h>
#endif

#include <cstdlib>
#include <bsl_iostream.h>
#include <bsl_stdexcept.h>
#include <bsl_string.h>

using namespace BloombergLP;

[% UNLESS opts.configSchema -%]
[% PROCESS svc_util.t -%]
const char CONFIG_SCHEMA[] =
"<?xml version='1.0' encoding='UTF-8'?>"
"<schema xmlns='http://www.w3.org/2001/XMLSchema'"
"        xmlns:bdem='http://bloomberg.com/schemas/bdem'"
"        xmlns:tns='[% svc.targetNamespace %]'"
"        targetNamespace='[% svc.targetNamespace %]'"
"        bdem:configuration='true'"
"        elementFormDefault='qualified'>"
""
"  <include schemaLocation='bascfg.xsd' bdem:inline='0'/>"
""
"  <complexType name='Configuration'>"
"    <sequence>"
"      <element name='BasConfig' type='tns:BasConfig'/>"
""
"<!-- Specify additional application-level configuration elements here. -->"
""
"    </sequence>"
"  </complexType>"
""
"  <element name='Configuration' type='tns:Configuration'/>"
"</schema>"
;

[% END -%]
const char LOG_CATEGORY[] = "[% SERVICE %]";

#ifdef BAS_NOBBENV
typedef bassvc::ServiceOffline  ServiceOffline;
#else
typedef a_basfs::ServiceOffline ServiceOffline;
#endif

static
void ignoreSigpipe()
{
#ifdef BDES_PLATFORM__OS_UNIX
    // Ignore SIGPIPE on Unix platforms.
    struct sigaction sa;
    ::sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sa.sa_handler = SIG_IGN;
    if (0 != ::sigaction(SIGPIPE, &sa, NULL)) {
        bsl::cerr << "Failed to ignore SIGPIPE!"
                  << bsl::endl;
    }
#endif
}

static
void printBanner(const char *action, const char **argv)
{
    bsl::cout << action
              << " BAS SERVICE ["
              << bdesu_ProcessUtil::getProcessId()
              << "]: ";
    const char **arg = argv;
    while (*arg) {
        bsl::cout << *arg << ' ';
        ++arg;
    }
    bsl::cout << bsl::endl;
}

int main(int argc, const char *argv[]) {
    ignoreSigpipe();
    printBanner("STARTING", argv);
#ifndef BAS_NOBBENV
    f77override(argc, argv);
#endif

    try {
        bsl::string taskname;
        bsl::string logFilename;
        bsl::string configFilename;
        int         verbosity;
        bool        debug       = false;
        bool        debugMemory = false;
        baea_CommandLineOptionInfo specTable[] = {
            {
                "l|logfile",
                "logfile",
                "logging file name",
                baea_CommandLineTypeInfo(&logFilename)
            },
            {
                "t|taskname",
                "taskname",
                "BENV taskname to accept M traps",
                baea_CommandLineTypeInfo(&taskname),
            },
            {
                "v|verbosity",
                "verbosity",
                "initial verbosity for the logger",
                baea_CommandLineTypeInfo(&verbosity),
            },
            {
                "M|debugMemory",
                "debugMemory",
                "use test allocator to detect memory leaks",
                baea_CommandLineTypeInfo(&debugMemory),
            },
            {
                "d|debug",
                "debug",
                "set [% SERVICE %] logging categories to DEBUG",
                baea_CommandLineTypeInfo(&debug),
            },
            {
                "i|routingInstance",
                "routingInstance",
                "instance number",
                baea_CommandLineTypeInfo(baea_CommandLineOptionType::BAEA_INT),
            },
            {
                "",
                "filename",
                "configuration file name",
                baea_CommandLineTypeInfo(&configFilename),
                baea_CommandLineOccurrenceInfo::REQUIRED,
            },
        };

[% SET ret = 1 -%]
        baea_CommandLine  commandLine(specTable);
        if (commandLine.parse(argc, argv)) {
            commandLine.printUsage();
            return [% ret %];
[% ret = ret + 1 -%]
        }

        bcema_TestAllocator  sa("[% service %].allocator", 0);
        bcema_TestAllocator  da("default.allocator", 0);
        bslma_Allocator     *serviceAllocator = (debugMemory)
                                          ? &sa
                                          : bslma_Default::defaultAllocator();
        bslma_Allocator     *defaultAllocator = (debugMemory)
                                          ? &da
                                          : bslma_Default::defaultAllocator();
        bslma_DefaultAllocatorGuard allocatorGuard(defaultAllocator);

        ServiceOffline serviceOffline(serviceAllocator);

        if (serviceOffline.configure(configFilename.c_str(),
[% IF opts.configSchema -%]
                                     [% namespace %]::ConfigSchema::TEXT,
[% ELSE -%]
                                     CONFIG_SCHEMA,
[% END -%]
                                     commandLine))
        {
            return [% ret %];
[% ret = ret + 1 -%]
        }
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

        if (debug) {
            serviceOffline.offline().loggerManager().setStdoutThreshold(4);
            serviceOffline.offline()
                          .setCategoryVerbosityLevel("[% SERVICE %]", 4);
        }

        bcem_Aggregate configuration = serviceOffline.configuration();

        bcem_Aggregate services = configuration.field("BasConfig",
                                                      "ServiceInstance");
        for (int i = 0; i < services.length(); ++i) {
            bcem_Aggregate service = services[i];

            const bsl::string SERVICE_NAME = service.field("Name").asString();

[% SET offset = String.new(' ').repeat(namespace.length) -%]
            bcema_SharedPtr<[% namespace %]::RequestRouter> router_sp;
            bassvc::ServiceManifest          [% offset %]manifest;
            int rc = [% namespace %]::Entry::createService(&router_sp,
                                            [% offset %]&manifest,
                                            [% offset %]SERVICE_NAME,
                                            [% offset %]configuration,
                                            [% offset %]serviceAllocator);
            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to create service "
                                  "'"       << SERVICE_NAME << "'"
                                  ": rc = " << rc
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            rc = serviceOffline.registerService(SERVICE_NAME,
                                                manifest,
                                                router_sp);
            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to register service "
                                  "'"       << SERVICE_NAME << "'"
                                  ": rc = " << rc
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }
        }

        int rc = serviceOffline.run();
        if (0 != rc) {
            BAEL_LOG_ERROR << "Failed to start service: "
                           << "rc = " << rc
                           << BAEL_LOG_END;
            return [% ret %];
[% ret = ret + 1 -%]
        }
    }
    catch (bsl::exception& e) {
        bsl::cerr << "Exception occurred: " << e.what() << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }
    catch (...) {
        bsl::cerr << "Unknown exception occurred" << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }
    printBanner("STOPPING", argv);
    return 0;
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
