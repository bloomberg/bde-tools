[% PROCESS svc_util.t -%]
// test[% service %].m.cpp   -*-C++-*-

#include <bdes_ident.h>
BDES_IDENT_RCSID(test[% service %]_m_cpp,"\$Id\$ \$CSID\$ \$CCId\$")

[% UNLESS opts.noSchema -%]
[% IF opts.msgExpand -%]
#include <[% msgpkg %]_[% requesttype %].h>
#include <[% msgpkg %]_[% responsetype %].h>

[% ELSE -%]
#include <[% msgpkg %]_[% opts.msgComponent %].h>

[% END -%]
[% END -%]
#ifndef BAS_NOBBENV
#include <a_basfs_clientutil.h>
[% UNLESS opts.noSchema -%]
#include <a_basfs_replay.h>
#include <a_basfs_replayrequestcriteria.h>
[% END -%]

#include <e_ipcfs_address.h>
#include <e_ipcfs_addressutil.h>
#endif

#include <basapi_codecconfiguration.h>
[% UNLESS opts.noSchema -%]
#include <basapi_codecoptions.h>
#include <basapi_codecutil.h>
[% END -%]
#include <basapi_tcpclient.h>
#include <bascfg_loggingconfig.h>
#include <bassvc_loggermanager.h>

#include <bsct_encodingtype.h>
#include <bsct_serviceinformation.h>
#include <bsct_useridentification.h>

#include <baea_commandline.h>
#include <bael_log.h>

#include <bteso_resolveutil.h>

[% IF opts.noSchema -%]
#include <bcema_blob.h>
#include <bcema_blobutil.h>
#include <bcema_pooledblobbufferfactory.h>
[% END -%]
#include <bcef_bindutil.h>
#include <bcemt_barrier.h>
#include <bcemt_threadgroup.h>
#include <bces_atomictypes.h>

#include <bdef_bind.h>
#include <bdef_function.h>
#include <bdef_placeholder.h>
#include <bdepcre_regex.h>
#include <bdet_timeinterval.h>
#include <bdetu_systemtime.h>

#include <bsl_cstdlib.h>
#include <bsl_ctime.h>
#include <bsl_fstream.h>
#include <bsl_iostream.h>
#include <bsl_stdexcept.h>
#include <bsl_string.h>
#include <bsl_vector.h>

using namespace BloombergLP;
[% SET ret = 1 -%]
[% SET MSGNS = (pkg == msgpkg)
             ? String.new(pkg).append('::')
             : String.new(msgpkg).append('::') -%]
[% IF RequestType.length > ResponseType.length -%]
[% SET formatWidth = MSGNS.length + RequestType.length -%]
[% ELSE -%]
[% SET formatWidth = MSGNS.length + ResponseType.length -%]
[% END -%]

namespace {

const char LOG_CATEGORY[]      = "[% SERVICE %].TEST";
const char LOG_CATEGORY_PERF[] = "[% SERVICE %].PERFORMANCE";

enum { SUCCESS = 0, FAILURE = 1 };

                          // =====================
                          // struct ProgramOptions
                          // =====================

struct ProgramOptions {
    // This struct encapsulates the various program options specified as
    // command-line arguments to the test client.

    bsl::string              d_protocol;
    bsl::string              d_hostname;
    bsl::string              d_port;

    int                      d_verbosity;

    double                   d_connectTimeout;
    double                   d_requestTimeout;

    int                      d_numIterations;
    int                      d_numThreads;

    bool                     d_validateResponseFlag;
    bsl::string              d_responseFilename;

    bsl::string              d_requestFilename;

[% UNLESS opts.noSchema -%]
    bsl::string              d_journalFilename;
    bsl::vector<bsl::string> d_journalRecords;

[% END -%]
    bool                     d_sendAsyncFlag;
    bool                     d_isOneWayFlag;
    bool                     d_ackRequestedFlag;
    bool                     d_logPerformanceFlag;
[% UNLESS opts.noSchema -%]
    bool                     d_decodeOnlyFlag;
[% END -%]

    // MACRO-LEVEL OPTIONS
    basapi::CodecConfiguration d_codecConfig;
    bsct::ServiceInformation   d_serviceInfo;
    bsct::UserIdentification   d_userId;

    // CREATORS
    explicit ProgramOptions(bslma_Allocator *basicAllocator = 0)
    : d_protocol(basicAllocator)
    , d_hostname(basicAllocator)
    , d_port(basicAllocator)
    , d_verbosity(3)
    , d_connectTimeout(5.0)
    , d_requestTimeout(10.0)
    , d_numIterations(1)
    , d_numThreads(1)
    , d_validateResponseFlag(false)
    , d_responseFilename(basicAllocator)
    , d_requestFilename(basicAllocator)
[% UNLESS opts.noSchema -%]
    , d_journalFilename(basicAllocator)
    , d_journalRecords(basicAllocator)
[% END -%]
    , d_sendAsyncFlag(false)
    , d_isOneWayFlag(false)
    , d_ackRequestedFlag(false)
    , d_logPerformanceFlag(false)
[% UNLESS opts.noSchema -%]
    , d_decodeOnlyFlag(false)
[% END -%]
    , d_codecConfig(basicAllocator)
    {
    }
};

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

#ifndef BAS_NOBBENV
void runFastSendTest(
[% IF opts.noSchema -%]
        bces_AtomicInt         *status,
        bcema_Blob             *response,
        const bcema_Blob&       request,
        const bcema_Blob&       expectedResponse,
        const e_ipcfs_Address&  address,
        const ProgramOptions&   opts)
[% ELSE -%]
[% SET offlen = formatWidth - 14 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        bces_AtomicInt [% offset %]*status,
[% SET offlen = formatWidth - MSGNS.length - RequestType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% RequestType %]& [% offset %]request,
[% SET offlen = formatWidth - MSGNS.length - ResponseType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% ResponseType %]& [% offset %]expectedResponse,
[% SET offlen = formatWidth - 15 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const e_ipcfs_Address& [% offset %]address,
[% SET offlen = formatWidth - 14 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const ProgramOptions& [% offset %]opts)
[% END -%]
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    BAEL_LOG_DEBUG << "Sending request over FastSend: "
                      "address = fs://" << opts.d_hostname    << ":"
                                        << opts.d_port        << ", "
                      "serviceInfo = "  << opts.d_serviceInfo << "\n"
                   << [% -%]
                   [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&request)'
                                     : 'request' %]
                   << BAEL_LOG_END;

    bdet_TimeInterval wallStart = bdetu_SystemTime::now();
    bsl::clock_t      cpuStart = bsl::clock();
    int               iterations = opts.d_numIterations;
    int               rc;
    while (iterations--) {
[% SET amp = '' -%]
[% UNLESS opts.noSchema -%]
[% SET amp = '&' -%]
        [% MSGNS %][% ResponseType %] response;

[% END -%]
        if (opts.d_isOneWayFlag) {
            rc = a_basfs::ClientUtil::executeOneWayRequestAsUser(
                          address, &opts.d_serviceInfo, 1, opts.d_codecConfig,
                          opts.d_userId, opts.d_ackRequestedFlag, request);
        }
        else {
            rc = a_basfs::ClientUtil::executeRequestAsUser(
                          [% amp %]response, address, opts.d_serviceInfo,
                          opts.d_codecConfig, opts.d_userId, request);
        }

        if (0 != rc) {
            BAEL_LOG_ERROR << "Error executing request: rc = " << rc
                           << BAEL_LOG_END;
            *status = FAILURE;
            return;
        }

        if (!opts.d_isOneWayFlag) {
            BAEL_LOG_INFO << "Received response:\n"
                          << [% -%]
                      [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(response)'
                                            : 'response' %]
                          << BAEL_LOG_END;
        }

        if (opts.d_validateResponseFlag) {
            BAEL_LOG_INFO << "Validating response:\n"
                          << [% -%]
                          [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&expectedResponse)'
                                            : 'expectedResponse' %]
                          << BAEL_LOG_END;

            if (expectedResponse != [%- opts.noSchema ? '*' : '' %]response) {
                BAEL_LOG_ERROR << "Response validation failed" << BAEL_LOG_END;
                *status = FAILURE;
                return;
            }
        }
    }
    bdet_TimeInterval wallStop = bdetu_SystemTime::now();
    bsl::clock_t      cpuStop = bsl::clock();
    bsl::clock_t      cpuTotal = cpuStop - cpuStart;
    bdet_TimeInterval wallTotal = wallStop - wallStart;
    if (opts.d_logPerformanceFlag) {
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY_PERF);
        BAEL_LOG_INFO
            << "iterations = " << opts.d_numIterations             << ", "
               "ticks = "      << cpuTotal                         << ", "
               "cpuTime = "    << cpuTotal / (double)CLOCKS_PER_SEC<< " secs, "
               "wallTime = "   << wallTotal.totalSecondsAsDouble() << " secs, "
               "RTT cpu = "    << cpuTotal / (double)CLOCKS_PER_SEC
                                / (double)opts.d_numIterations     << " secs, "
               "RTT wall = "   << wallTotal.totalSecondsAsDouble()
                                / opts.d_numIterations             << " secs"
            << BAEL_LOG_END;
    }
}
#endif

void runTcpTest(
[% IF opts.noSchema -%]
        bces_AtomicInt           *status,
        basapi::TcpClient        *tcpClient,
        bcema_Blob               *response,
        const bcema_Blob&         request,
        const bcema_Blob&         expectedResponse,
        const bteso_IPv4Address&  address,
        const ProgramOptions&     opts)
[% ELSE -%]
[% SET offlen = formatWidth - 14 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        bces_AtomicInt[% offset %]  *status,
[% SET offlen = formatWidth - 17 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        basapi::TcpClient[% offset %]  *tcpClient,
[% SET offlen = formatWidth - MSGNS.length - RequestType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% RequestType %]&  [% offset %]request,
[% SET offlen = formatWidth - MSGNS.length - ResponseType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% ResponseType %]&  [% offset %]expectedResponse,
[% SET offlen = formatWidth - 17 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const bteso_IPv4Address&  [% offset %]address,
[% SET offlen = formatWidth - 14 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const ProgramOptions&  [% offset %]opts)
[% END -%]
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    bdet_TimeInterval connectTimeout(opts.d_connectTimeout);
    bdet_TimeInterval requestTimeout(opts.d_requestTimeout);

    int handle;
    if (0 != tcpClient->openHandle(&handle, connectTimeout, address)) {
        BAEL_LOG_FATAL << "Can't connect to " << address
                       << BAEL_LOG_END;
        *status = FAILURE;
        return;
    }

    BAEL_LOG_DEBUG << "Sending request over TCP: "
                      "address = tcp://" << opts.d_hostname    << ":"
                                         << opts.d_port        << ", "
                      "serviceInfo = "   << opts.d_serviceInfo << "\n"
                   << [% -%]
                   [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&request)'
                                     : 'request' %]
                   << BAEL_LOG_END;

    bdet_TimeInterval wallStart = bdetu_SystemTime::now();
    bsl::clock_t      cpuStart = bsl::clock();
    int               iterations = opts.d_numIterations;
    int               rc;
    while (iterations--) {
[% SET amp = '' -%]
[% UNLESS opts.noSchema -%]
[% SET amp = '&' -%]
        [% MSGNS %][% ResponseType %] response;

[% END -%]
        if (opts.d_isOneWayFlag) {
            if (opts.d_ackRequestedFlag) {
                rc = tcpClient->sendOneWayRequestWithAck(
                                                  handle,
                                                  &opts.d_serviceInfo, 1,
                                                  opts.d_codecConfig,
                                                  opts.d_userId,
                                                  requestTimeout,
                                                  request);
            }
            else {
                rc = tcpClient->sendOneWayRequest(handle,
                                                  opts.d_serviceInfo,
                                                  opts.d_codecConfig,
                                                  opts.d_userId,
                                                  request);
            }
        }
        else {
            rc = tcpClient->sendRequest([% amp %]response,
                                        handle,
                                        opts.d_serviceInfo,
                                        opts.d_codecConfig,
                                        opts.d_userId,
                                        requestTimeout,
                                        request);
        }

        if (0 != rc) {
            BAEL_LOG_ERROR << "Error sending request: rc = " << rc
                           << BAEL_LOG_END;
            *status = FAILURE;
            return;
        }

        if (!opts.d_isOneWayFlag) {
            BAEL_LOG_INFO << "Received response:\n"
                          << [% -%]
                      [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(response)'
                                            : 'response' %]
                          << BAEL_LOG_END;
        }

        if (opts.d_validateResponseFlag) {
            BAEL_LOG_INFO << "Validating response:\n"
                          << [% -%]
                          [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&expectedResponse)'
                                            : 'expectedResponse' %]
                          << BAEL_LOG_END;

            if (expectedResponse != [%- opts.noSchema ? '*' : '' %]response) {
                BAEL_LOG_ERROR << "Response validation failed" << BAEL_LOG_END;
                *status = FAILURE;
                return;
            }
        }
    }
    bdet_TimeInterval wallStop = bdetu_SystemTime::now();
    bsl::clock_t      cpuStop = bsl::clock();
    bsl::clock_t      cpuTotal = cpuStop - cpuStart;
    bdet_TimeInterval wallTotal = wallStop - wallStart;
    if (opts.d_logPerformanceFlag) {
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY_PERF);
        BAEL_LOG_INFO
            << "iterations = " << opts.d_numIterations             << ", "
            << "ticks = "      << cpuTotal                         << ", "
            << "cpuTime = "    << cpuTotal / (double)CLOCKS_PER_SEC<< " secs, "
            << "wallTime = "   << wallTotal.totalSecondsAsDouble() << " secs, "
            << "RTT cpu = "    << cpuTotal / (double)CLOCKS_PER_SEC
                                / (double)opts.d_numIterations     << " secs, "
            << "RTT wall = "   << wallTotal.totalSecondsAsDouble()
                                / opts.d_numIterations             << " secs"
            << BAEL_LOG_END;
    }

    tcpClient->closeHandle(handle);
}

void tcpCallback(
[% IF opts.noSchema -%]
        bces_AtomicInt        *status,
        int                    asyncSendResult,
        int                    handle,
        const bcema_Blob&      response,
        bool                   isFinal,
        int                    totalResponses,
        bces_AtomicInt        *numResponses,
        bcemt_Barrier         *barrier,
        const bcema_Blob&      expectedResponse,
        const ProgramOptions&  opts)
[% ELSE -%]
[% SET width = 12 + MSGNS.length + ResponseType.length -%]
[% SET offlen = width - 14 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        bces_AtomicInt[% offset %]  *status,
        int           [% offset %]   asyncSendResult,
        int           [% offset %]   handle,
        bdema_ManagedPtr<[% MSGNS %][% ResponseType %]>&  response,
        bool          [% offset %]   isFinal,
        int           [% offset %]   totalResponses,
        bces_AtomicInt[% offset %]  *numResponses,
        bcemt_Barrier [% offset %]  *barrier,
[% SET offlen = width - MSGNS.length - ResponseType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% ResponseType %]&  [% offset %]expectedResponse,
[% SET offlen = width - 14 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const ProgramOptions&  [% offset %]opts)
[% END -%]
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    if (basapi::TcpClient::SUCCESS != asyncSendResult) {
        BAEL_LOG_ERROR << "Error sending request:\n" << asyncSendResult
                       << BAEL_LOG_END;
        *status = FAILURE;
        barrier->wait();
        return;                                                       // RETURN
    }
    else {
        BAEL_LOG_INFO << "Received response:\n"
                      << [% -%]
                      [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&response)'
                                        : '*response' %]
                      << BAEL_LOG_END;

        if (opts.d_validateResponseFlag) {
            BAEL_LOG_INFO << "Validating response:\n"
                          << [% -%]
                          [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&expectedResponse)'
                                            : 'expectedResponse' %]
                          << BAEL_LOG_END;

            if (expectedResponse != [%- opts.noSchema ? '' : '*' %]response) {
                BAEL_LOG_ERROR << "Response validation failed" << BAEL_LOG_END;
                *status = FAILURE;
            }
        }
    }

    if (isFinal && ++*numResponses == totalResponses) {
        barrier->wait();
    }
}

void runAsyncTcpTest(
[% IF opts.noSchema -%]
        bces_AtomicInt           *status,
        basapi::TcpClient        *tcpClient,
        bcema_Blob               *response,
        const bcema_Blob&         request,
        const bcema_Blob&         expectedResponse,
        const bteso_IPv4Address&  address,
        const ProgramOptions&     opts)
[% ELSE -%]
[% SET offlen = formatWidth - 14 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        bces_AtomicInt[% offset %]  *status,
[% SET offlen = formatWidth - 17 + 6 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        basapi::TcpClient[% offset %]  *tcpClient,
[% SET offlen = formatWidth - MSGNS.length - RequestType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% RequestType %]&  [% offset %]request,
[% SET offlen = formatWidth - MSGNS.length - ResponseType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% ResponseType %]&  [% offset %]expectedResponse,
[% SET offlen = formatWidth - 17 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const bteso_IPv4Address&  [% offset %]address,
[% SET offlen = formatWidth - 14 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const ProgramOptions&  [% offset %]opts)
[% END -%]
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    bdet_TimeInterval connectTimeout(opts.d_connectTimeout);
    bdet_TimeInterval requestTimeout(opts.d_requestTimeout);

    int handle;
    if (0 != tcpClient->openHandle(&handle, connectTimeout, address)) {
        BAEL_LOG_FATAL << "Can't connect to " << address
                       << BAEL_LOG_END;
        *status = FAILURE;
        return;
    }

    BAEL_LOG_DEBUG << "Sending request over TCP: "
                      "address = tcp://" << opts.d_hostname    << ":"
                                         << opts.d_port        << ", "
                      "serviceInfo = "   << opts.d_serviceInfo << "\n"
                   << [% -%]
                   [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&request)'
                                     : 'request' %]
                   << BAEL_LOG_END;

    using bdef_PlaceHolders::_1;
    using bdef_PlaceHolders::_2;
    using bdef_PlaceHolders::_3;
    using bdef_PlaceHolders::_4;

    bcemt_Barrier  barrier(2);
    bces_AtomicInt numResponses = 0;
[% IF opts.noSchema -%]
    bdef_Function<void(*)(int, int, const bcema_Blob&, bool)> cb =
[% ELSE -%]
    typedef bdema_ManagedPtr<[% MSGNS%][% ResponseType %]>& ResponsePtr;
    bdef_Function<void(*)(int, int, ResponsePtr, bool)> cb =
[% END -%]
           bdef_BindUtil::bind(&tcpCallback, status, _1, _2, _3, _4,
                               opts.d_numIterations, &numResponses, &barrier,
                               expectedResponse, opts);

    bdet_TimeInterval wallStart = bdetu_SystemTime::now();
    bsl::clock_t      cpuStart = bsl::clock();
    int               iterations = opts.d_numIterations;
    int               rc;
    while (iterations) {
        rc = tcpClient->sendRequest(handle, cb, opts.d_serviceInfo,
                                    opts.d_codecConfig, opts.d_userId,
                                    requestTimeout, request);
        if (0 != rc) {
            BAEL_LOG_ERROR << "Error sending request: rc = " << rc
                           << BAEL_LOG_END;
            *status = FAILURE;
            return;
        }
        --iterations;
    }
    barrier.wait();
    bdet_TimeInterval wallStop = bdetu_SystemTime::now();
    bsl::clock_t      cpuStop = bsl::clock();
    bsl::clock_t      cpuTotal = cpuStop - cpuStart;
    bdet_TimeInterval wallTotal = wallStop - wallStart;
    if (opts.d_logPerformanceFlag) {
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY_PERF);
        BAEL_LOG_INFO
            << "iterations = " << opts.d_numIterations             << ", "
            << "ticks = "      << cpuTotal                         << ", "
            << "cpuTime = "    << cpuTotal / (double)CLOCKS_PER_SEC<< " secs, "
            << "wallTime = "   << wallTotal.totalSecondsAsDouble() << " secs, "
            << "RTT cpu = "    << cpuTotal / (double)CLOCKS_PER_SEC
                                / (double)opts.d_numIterations     << " secs, "
            << "RTT wall = "   << wallTotal.totalSecondsAsDouble()
                                / opts.d_numIterations             << " secs"
            << BAEL_LOG_END;
    }

    tcpClient->closeHandle(handle);
}

int sendRequest(
[% IF opts.noSchema -%]
        bcema_Blob            *response,
        const bcema_Blob&      request,
        const bcema_Blob&      expectedResponse,
        const ProgramOptions&  opts)
[% ELSE -%]
[% SET offlen = formatWidth - MSGNS.length - RequestType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% RequestType %]& [% offset %]request,
[% SET offlen = formatWidth - MSGNS.length - ResponseType.length -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const [% MSGNS%][% ResponseType %]& [% offset %]expectedResponse,
[% SET offlen = formatWidth - 14 -%]
[% SET offset = String.new(' ').repeat(offlen) -%]
        const ProgramOptions& [% offset %]opts)
[% END -%]
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    BAEL_LOG_INFO << "Sending request:\n"
                  << [% -%]
                     [%- opts.noSchema ? 'bcema_BlobUtilHexDumper(&request)'
                                       : 'request' %]
                  << BAEL_LOG_END;

    int rc = 0;

    basapi::TcpClient         tcpClient;
    bdef_Function<void(*)()>  job;
    bces_AtomicInt            status = SUCCESS;

    if ("tcp" == opts.d_protocol) {
        bteso_IPv4Address address;
        int errorCode;
        if (0 != bteso_ResolveUtil::getAddress(&address,
                                               opts.d_hostname.c_str(),
                                               &errorCode))
        {
            BAEL_LOG_FATAL << "Could not resolve "
                           << opts.d_hostname
                           << ": rc = " << errorCode
                           << BAEL_LOG_END;
            return [% ret %];
[% ret = ret + 1 -%]
        }
        address.setPortNumber(bsl::atoi(opts.d_port.c_str()));

        if (opts.d_sendAsyncFlag) {
            job = bcef_BindUtil::bind(bslma_Default::allocator(),
                                      &runAsyncTcpTest,
                                      &status,
                                      &tcpClient, [% -%]
                                      [%- opts.noSchema ? 'response, ' : '' -%]
                                      [%- %]request,
                                      expectedResponse,
                                      address,
                                      opts);
        }
        else {
            job = bcef_BindUtil::bind(bslma_Default::allocator(),
                                      &runTcpTest,
                                      &status,
                                      &tcpClient, [% -%]
                                      [%- opts.noSchema ? 'response, ' : '' -%]
                                      [%- %]request,
                                      expectedResponse,
                                      address,
                                      opts);
        }
    }
    else if ("fs" == opts.d_protocol) {
#ifdef BAS_NOBBENV
        BAEL_LOG_ERROR << "FastSend support is disabled\n"
                       << BAEL_LOG_END;
        return [% ret %];
#else
        int machineNumber;
        if (0 != e_ipcfs_AddressUtil::getMachineNumber(
                                                  &machineNumber,
                                                  opts.d_hostname.c_str()))
        {
            BAEL_LOG_FATAL << "Could not resolve "
                           << opts.d_hostname
                           << ": rc = " << rc
                           << BAEL_LOG_END;
            return [% ret %];
[% ret = ret + 1 -%]
        }

        int localMachineNumber = e_ipcfs_AddressUtil::localMachineNumber();
        if (localMachineNumber == machineNumber) {
            machineNumber = 0;
        }

        e_ipcfs_Address address(bsl::atoi(opts.d_port.c_str()), machineNumber);
        job = bcef_BindUtil::bind(bslma_Default::allocator(),
                                  &runFastSendTest,
                                  &status,
                                  [% opts.noSchema ? 'response, ' : '' -%]
                                  [%- %]request,
                                  expectedResponse,
                                  address,
                                  opts);
#endif
    }
    else {
        BAEL_LOG_ERROR << "Unknown protocol in service location URI: "
                       << "'" << opts.d_protocol << "://" << opts.d_hostname
                       << ":" << opts.d_port << "'"
                       << BAEL_LOG_END;
        return [% ret %];
[% ret = ret + 1 -%]
    }

    bcemt_ThreadGroup threadGroup;

    for (int i = 0; i < opts.d_numThreads; ++i) {
        int rc = threadGroup.addThread(job);
        if (0 != rc) {
            BAEL_LOG_ERROR << "Failed to start thread " << i << BAEL_LOG_END;
        }
    }

    threadGroup.joinAll();

    return status;
}

int parseServiceLocation(
        bsl::string        *protocol,
        bsl::string        *hostname,
        bsl::string        *port,
        const bsl::string&  serviceLocation)
{
    // Parse the specified 'serviceLocation' URI having the form
    //..
    //  protocol://hostname:port
    //..
    // For example, the URI
    //..
    //  tcp://n100:30190
    //..
    // specifies a FastSend channel to taskNumber 30190 on n100.  Load the
    // protocol into the specified 'protocol', the host name into the specified
    // 'hostname', and the port into the specified 'port'.  Return 0 on
    // success, and a non-zero value otherwise.

    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    bsl::string errorMessage;
    int         errorOffset;
    const char  PATTERN[] =
        "^"
        "(" "[a-z]+"         ")://" // protocol
        "(" "[a-z][a-z0-9]*" "):"   // hostname
        "(" "[1-9][0-9]*"    ")\$";  // port

    bdepcre_RegEx uri;
    int rc = uri.prepare(&errorMessage, &errorOffset, PATTERN);
    if (0 != rc) {
        BAEL_LOG_ERROR << errorMessage << ": "
                       << "line = " << errorOffset << ", "
                       << "rc = "   << rc
                       << BAEL_LOG_END;
        return rc;                                                    // RETURN
    }

    bsl::vector< bsl::pair<int, int> > matches;
    rc = uri.match(&matches,
                   serviceLocation.c_str(),
                   serviceLocation.length());
    if (0 != rc) {
        if (4 != matches.size()) {
            BAEL_LOG_ERROR << "Failed to parse service location: "
                           << "found " << (0 == matches.size()
                                          ? 0 : matches.size() - 1)
                           << " of 3 components in specified URI"
                           << BAEL_LOG_END;
        }
        return (0 != rc) ? rc : 11;                                   // RETURN
    }

    protocol->assign(serviceLocation.substr(
            matches[1].first, matches[1].second));

    hostname->assign(serviceLocation.substr(
            matches[2].first, matches[2].second));

    port->assign(serviceLocation.substr(
            matches[3].first, matches[3].second));

    return 0;
}

int parseServiceInformation(
        bsct::ServiceInformation *result,
        const bsl::string&        serviceInfo)
{
    // Parse the specified 'serviceInfo'  string having the form
    //..
    //  serviceId [ - version ]
    //..
    // where "serviceId" specifies a BAS service ID, and "version" specifies
    // a version string having the (optional) components
    //..
    //   majorVersion [ . minorVersion [ . patchLevel ] ]
    //..
    // For example, the string "30190-1.2.5" represents service ID 30190,
    // version 1.2.5.  Load into the specified 'result' the serviceId and
    // version information.  If no version information is present, load the
    // value 1.0.0.  Otherwise, load the major version number, and as many
    // subsequent components of the version as are specified, defaulting to 0
    // if no value is specified.  Return 0 on success, and a non-zero value
    // otherwise.

    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    bsl::string errorMessage;
    int         errorOffset;
    const char  PATTERN[] =
      "^"
      "(" "[1-9][0-9]*"                           ")"    // service ID
      "(-" "([0-9]+)(\\.([0-9]+)(\\.([0-9]+))?)?" ")?\$"; // version
                                                         // (major.minor.patch)

    bdepcre_RegEx uri;
    int rc = uri.prepare(&errorMessage, &errorOffset, PATTERN);
    if (0 != rc) {
        BAEL_LOG_ERROR << errorMessage << ": "
                       << "line = " << errorOffset << ", "
                       << "rc = "   << rc
                       << BAEL_LOG_END;
        return rc;                                                    // RETURN
    }

    bsl::vector< bsl::pair<int, int> > matches;
    rc = uri.match(&matches,
                   serviceInfo.c_str(),
                   serviceInfo.length());
    if (0 != rc) {
        if (matches.size() < 2) {
            BAEL_LOG_ERROR << "Failed to parse service information"
                           << BAEL_LOG_END;
        }
        return (0 != rc) ? rc : 11;                                   // RETURN
    }

    result->reset();
    result->setServiceVersionMajor([% svc.serviceVersionMajor %]);
    result->setServiceVersionMinor(0);

    bsl::string value(serviceInfo.substr(matches[1].first, matches[1].second));
    result->setServiceId(bsl::atoi(value.c_str()));

    if (0 < matches[3].second) {
        value.assign(serviceInfo.substr(matches[3].first, matches[3].second));
        result->setServiceVersionMajor(bsl::atoi(value.c_str()));
    }

    if (0 < matches[5].second) {
        value.assign(serviceInfo.substr(matches[5].first, matches[5].second));
        result->setServiceVersionMinor(bsl::atoi(value.c_str()));
    }

    if (0 < matches[7].second) {
        value.assign(serviceInfo.substr(matches[7].first, matches[7].second));
        result->setServiceVersionPatch(bsl::atoi(value.c_str()));
    }

    return 0;
}

int parseProgramOptions(
        ProgramOptions   *opts,
        int               argc,
        char            **argv,
        bsl::ostream&     stream)
{
    // Parse and validate each of the specified 'opts' options in the specified
    // 'argv' array, and ensure any restrictions that could not be enforced
    // through the command-line parser.  On success, set the value of the
    // specified 'opts' to the parsed options and return 0.  Otherwise, write
    // the command line usage to the specified 'stream' and return a non-zero
    // value.

    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

[% UNLESS opts.noSchema -%]
    bsl::vector<bsl::string> inputFilenames;
[% ELSE -%]
    bsl::string inputFilename;
[% END -%]

    bsl::string rawServiceLocation;
    bsl::string rawServiceInfo;
    bsl::string encodingAsString("[% opts.noSchema ? 'raw' : 'xml' %]");

    bsl::string xmlNamespace("[% svc.WSDL
                               ? svc.types.schema.targetNamespace
                               : svc.targetNamespace %]");

    int terminalSerialNumber = 0;
    int uuid = 0;
    int rc = 0;

    baea_CommandLineOptionInfo specTable[] = {
        {
            "l|serviceLocation",
            "location",
            "Service location",
            baea_CommandLineTypeInfo(&rawServiceLocation),
            baea_CommandLineOccurrenceInfo::REQUIRED
        },
        {
            "s|serviceInfo",
            "info",
            "Service ID and version",
            baea_CommandLineTypeInfo(&rawServiceInfo),
            baea_CommandLineOccurrenceInfo::REQUIRED
        },
        {
            "v|verbosity",
            "level",
            "initial verbosity for logging",
            baea_CommandLineTypeInfo(&opts->d_verbosity)
        },
        {
            "e|encoding",
            "type",
            "message encoding (raw, bdex, ber, xml)",
            baea_CommandLineTypeInfo(&encodingAsString)
        },
        {
            "z|connectTimeout",
            "connectTimeout",
            "TCP connect timeout (in seconds)",
            baea_CommandLineTypeInfo(&opts->d_connectTimeout)
        },
        {
            "Z|requestTimeout",
            "requestTimeout",
            "TCP request timeout (in seconds)",
            baea_CommandLineTypeInfo(&opts->d_requestTimeout)
        },
        {
            "A|async",
            "async",
            "use Asynchronous transport",
            baea_CommandLineTypeInfo(&opts->d_sendAsyncFlag)
        },
        {
            "o|oneWay",
            "oneWay",
            "send one-way message (no ack)",
            baea_CommandLineTypeInfo(&opts->d_isOneWayFlag),
        },
        {
            "O|oneWayAck",
            "oneWayAck",
            "send one-way message (with ack)",
            baea_CommandLineTypeInfo(&opts->d_ackRequestedFlag),
        },
        {
            "P|logPerformance",
            "logPerformance",
            "log performance metrics (at verbosity 2)",
            baea_CommandLineTypeInfo(&opts->d_logPerformanceFlag),
        },
        {
            "U|uuid",
            "uuid",
            "client UUID",
            baea_CommandLineTypeInfo(&uuid)
        },
        {
            "S|serialNumber",
            "serialNumber",
            "client terminal serial number",
            baea_CommandLineTypeInfo(&terminalSerialNumber)
        },
        {
            "I|numIterations",
            "numIterations",
            "number of iterations per thread (default 1)",
            baea_CommandLineTypeInfo(&opts->d_numIterations),
        },
        {
            "T|numThreads",
            "numThreads",
            "number of threads (default 1)",
            baea_CommandLineTypeInfo(&opts->d_numThreads),
        },
[% IF opts.noSchema -%]
        {
            "V|validateResponse",
            "responseFilename",
            "validate response against the specified response",
            baea_CommandLineTypeInfo(&opts->d_responseFilename),
        },
[% ELSE -%]
        {
            "j|journal",
            "journalFilename",
            "load requests from specified journal filename",
            baea_CommandLineTypeInfo(&opts->d_journalFilename),
        },
        {
            "r|record",
            "record-handle",
            "process specified journal record",
            baea_CommandLineTypeInfo(&opts->d_journalRecords)
        },
        {
            "V|validateResponse",
            "responseFilename",
            "validate response received against the specified response "
            "(implicit with -j)",
            baea_CommandLineTypeInfo(&opts->d_validateResponseFlag),
        },
[% END -%]
[% UNLESS opts.noSchema -%]
        {
            "d|decodeOnly",
            "decodeOnly",
            "decode the request, but do not send it to the service",
            baea_CommandLineTypeInfo(&opts->d_decodeOnlyFlag)
        },
        {
            "x|xmlns",
            "namespace",
            "XML namespace of message schema",
            baea_CommandLineTypeInfo(&xmlNamespace)
        },
[% END -%]
        {
            "",
            "input",
            "input filename",
[% IF !opts.noSchema -%]
            baea_CommandLineTypeInfo(&inputFilenames)
[% ELSE -%]
            baea_CommandLineTypeInfo(&inputFilename)
[% END -%]
        },
    };

    const char MORE_USAGE[] =
        "\nExamples:\n"
        "  -l fs://sundev13:21945 -s 30190 2.xml\n"
        "      Send the \"2.xml\" request encoded as XML (default) to\n"
        "      the service identified by the BAS service Id 30190 and\n"
        "      version 1.0.0 (default) on sundev13 at FastSend\n"
        "      dbNum 21945.\n"
        "\n"
        "  -l tcp://sundev13:21945 -s 30190-2.1 2.xml\n"
        "      Send the \"2.xml\" request encoded as XML (default) to\n"
        "      the service identified by the BAS service Id 30190 and\n"
        "      version 2.1.0 on sundev13 at TCP port 21945.\n"
        "\n"
        "  -l fs://sundev13:21945 -s 30190 -e ber -I 10000 -P 2.xml\n"
        "      Send 10000 \"2.xml\" requests using the BER encoding to\n"
        "      the service identified by the BAS service Id 30190 and\n"
        "      version 1.0.0 on sundev13 at FastSend dbNum 21945, and\n"
        "      output a performance profile (average round-trip time and\n"
        "      local I/O overhead).\n"
        "\n"
        "  -l fs://sundev13:21945 -s 30190 -V request.xml response.xml\n"
        "      Send \"request.xml\" to the service identified by the BAS\n"
        "      service Id 30190 and version 1.0.0 on sundev13 at FastSend\n"
        "      dbNum 21945, and verify (i.e. compare) the received response\n"
        "      against \"response.xml\".\n"
[% IF !opts.noSchema -%]
        "\n"
        "  -l tcp://sundev13:21945 -s 30190 -e xml -j mysvc.journal\n"
        "      Load all the records from the persistant journal at\n"
        "      \"mysvc.journal\" that match the specified service ID,\n"
        "      encode the request using the \"xml\" encoding, then send\n"
        "      each request to the service identified by the BAS service\n"
        "      Id 30190 and version 2.1.0 on sundev13 at TCP port 21945.\n"
        "\n"
        "  -l tcp://sundev13:21945 -s 30190 -e xml -j mysvc.journal -r 4\n"
        "      Load record handle 4 from the persistant journal at\n"
        "      \"mysvc.journal\", encode the request using the \"xml\"\n"
        "      encoding, then send the request to the service identified by\n"
        "      the BAS service Id 30190 and version 2.1.0 on sundev13 at\n"
        "      TCP port 21945.\n"
[% END -%]
        ;

    baea_CommandLine commandLine(specTable);
    if (commandLine.parse(argc, argv)) {
        commandLine.printUsage(stream);
        stream << MORE_USAGE << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }

    // Parse the service location.
    rc = parseServiceLocation(&opts->d_protocol,
                              &opts->d_hostname,
                              &opts->d_port,
                              rawServiceLocation);
    if (0 != rc) {
        stream << "Invalid service location: "
               << "'" << rawServiceLocation << "': rc = " << rc
               << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }

    // Parse the service information.
    rc = parseServiceInformation(&opts->d_serviceInfo, rawServiceInfo);
    if (0 != rc) {
        stream << "Invalid service information: "
               << "'" << rawServiceInfo << "': rc = " << rc
               << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }

    // Convert the encoder string to the enumeration value.
    bsct::EncodingType::Value encoding;
    if (0 != bsct::EncodingType::fromString(&encoding,
                                            encodingAsString.c_str(),
                                            encodingAsString.length()))
    {
        stream << "Unsupported message encoding: " << encodingAsString
               << bsl::endl;
        return [% ret %];
[% ret = ret + 1 -%]
    }

    // Set the codec options and encoding type.
    basapi::CodecOptions& codecOptions = opts->d_codecConfig.codecOptions();
    codecOptions.xmlEncoderOptions().setObjectNamespace(xmlNamespace);
    codecOptions.xmlEncoderOptions().setTag("[% svc.requestElement %]");
    opts->d_codecConfig.encodingType() = encoding;

    // Set the user identification.
    opts->d_userId.setUuid(uuid);
    opts->d_userId.setTerminalSerialNumber(terminalSerialNumber);

    opts->d_validateResponseFlag = commandLine.isSpecified("responseFilename");

[%#
    The following blocks all return the same value on error
-%]
    // Validate options.
    {
        bool isTcp = "tcp" == opts->d_protocol;

        if (opts->d_sendAsyncFlag) {
            if (!isTcp) {
                stream << "Option '--async' is only supported by TCP"
                       << bsl::endl;
                return [% ret %];
            }

            if (opts->d_isOneWayFlag) {
                stream << "Options '--oneWay' and '--async' "
                       << "are mutually exclusive" << bsl::endl;
                return [% ret %];
            }
            if (opts->d_ackRequestedFlag) {
                stream << "Options '--oneWayAck' and '--async' "
                       << "are mutually exclusive" << bsl::endl;
                return [% ret %];
            }
        }

        if (opts->d_ackRequestedFlag) {
            if (opts->d_isOneWayFlag) {
                stream << "Options '--oneWayAck' and '--oneWay' "
                       << "are mutually exclusive" << bsl::endl;
                return [% ret %];
            }
            opts->d_isOneWayFlag = true;
        }
[% IF !opts.noSchema -%]
        if (opts->d_journalFilename.empty()) {
            if (opts->d_validateResponseFlag) {
                if (inputFilenames.size() != 2) {
                    stream << "Unexpected number of input files: expected "
                              "<requestFilename> <responseFilename>"
                           << bsl::endl;
                    return [% ret %];
                }

                opts->d_requestFilename  = inputFilenames[0];
                opts->d_responseFilename = inputFilenames[1];
            }
            else {
                if (inputFilenames.size() != 1) {
                    stream << "Unexpected number of input files: expected "
                              "<requestFilename>" << bsl::endl;
                    return [% ret %];
                }

                opts->d_requestFilename  = inputFilenames[0];
            }
        }

        if (opts->d_requestFilename.empty() &&
            opts->d_journalFilename.empty())
        {
            stream << "Either option -j <journalFilename> or "
                   << "non-option <requestFilename> must be "
                   << "specified" << bsl::endl;
            return [% ret %];
        }

        if ((!opts->d_requestFilename.empty()) &&
            (!opts->d_journalFilename.empty()))
        {
            stream << "Option -j <journalFilename> and non-option "
                   << "<requestFilename> are mutually exclusive" << bsl::endl;
            return [% ret %];
        }

        if ((!opts->d_journalRecords.empty()) &&
             (opts->d_journalFilename.empty()))
        {
            stream << "Option -r requires options -j" << bsl::endl;
            return [% ret %];
        }

        if ((!opts->d_journalFilename.empty()) &&
            (opts->d_validateResponseFlag) &&
            (!opts->d_responseFilename.empty()))
        {
           stream << "Warning: validating journal request against "
                  << "corresponding response, specified response filename is "
                  << "ignored" << bsl::endl;
        }
[% ELSE -%]

        opts->d_requestFilename  = inputFilename;

        if (!opts->d_responseFilename.empty()) {
            opts->d_validateResponseFlag = true;
        }
[% END -%]
    }
[% ret = ret + 1 -%]

    return 0;
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
[% UNLESS opts.noSchema -%]
#ifndef BAS_NOBBENV
                           // ====================
                           // class ReplayCallback
                           // ====================

class ReplayCallback :
    public a_basfs::Replay::Callback<[% MSGNS%][% RequestType %],
                                     [% MSGNS%][% ResponseType %]>
{
    // The class provides a collection of callback functions through which to
    // respond to various events that arise during the playback of requests
    // using 'a_basfs::Replay'.

    // INSTANCE DATA
    const ProgramOptions& d_opts;

  public:
    // TYPES
    typedef a_basfs::Replay::Response<[% MSGNS%][% RequestType %],
                                      [% MSGNS%][% ResponseType %]> ResponseType;
        // The request/response types expected by 'a_basfs::Replay'.

    // CREATORS
    explicit ReplayCallback(const ProgramOptions& opts);

    // MANIPULATORS
    int onDecodingError(const bcema_Blob&           badData,
                        baecs_Journal::RecordHandle handle);
        // Callback function invoked by 'a_basfs::Replay' when either a request
        // or a response cannot be decoded.  Return 0 if 'a_basfs::Replay'
        // should continue replaying requests or a non-zero value to stop
        // replaying requests.

    int onReplayResponse(const ResponseType& result);
        // Callback function invoked by 'a_basfs::Replay' when the service
        // endpoint for a replayed request returns a response.  Return 0 if
        // 'a_basfs::Replay' should continue replaying requests or a non-zero
        // value to stop replaying requests.
};

ReplayCallback::ReplayCallback(const ProgramOptions& opts)
: d_opts(opts)
{
}

int ReplayCallback::onDecodingError(
        const bcema_Blob&           badData,
        baecs_Journal::RecordHandle handle)
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
    BAEL_LOG_ERROR << "Failed to decode record handle " << handle
                   << BAEL_LOG_END;
    return 0;
}

int ReplayCallback::onReplayResponse(
        const ReplayCallback::ResponseType& result)
{
    BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

    if (d_opts.d_decodeOnlyFlag) {
       return 0;                                                      // RETURN
    }

    if (d_opts.d_validateResponseFlag) {
        if (result.d_saved.empty()) {
            BAEL_LOG_ERROR << "Failed to validate journal request because no "
                              "corresponding response exists in the journal"
                           << BAEL_LOG_END;
            return -1;
        }

        if (a_basfs::Replay::ERROR_RECORD == result.d_saved[0].d_type) {
            BAEL_LOG_ERROR << "Failed to validate journal request because the "
                              "saved response is of type ERROR_MESSAGE"
                           << BAEL_LOG_END;
            return -1;
        }

        if (a_basfs::Replay::ONEWAY_ACK_RECORD == result.d_saved[0].d_type) {
            BAEL_LOG_WARN << "Not performing response validation: the saved "
                             "response is of type MESSAGE_ACK"
                          << BAEL_LOG_END;
        }
        else {
            return sendRequest(result.d_requestSent,
                               result.d_saved[0].d_as.d_response.object(),
                               d_opts);
        }
    }

    [% MSGNS%][% ResponseType %] expectedResponse;
    return sendRequest(result.d_requestSent, expectedResponse, d_opts);
}
#endif
[% END -%]

}  // close unnamed namespace

//=============================================================================
//                                 MAIN PROGRAM
//-----------------------------------------------------------------------------

int main(int argc, char *argv[])
{
    int rc = 0;
    try {
        ProgramOptions opts;
        rc = parseProgramOptions(&opts, argc, argv, bsl::cout);
        if (0 != rc) {
            return rc;
        }

        bassvc::LoggerManager loggerManager;
        bascfg::LoggingConfig loggerConfiguration;
        loggerConfiguration.verbosityLevel() = opts.d_verbosity;
        loggerConfiguration.stdoutLoggingThreshold() = 5;
        rc = loggerManager.initialize(loggerConfiguration);
        if (0 != rc) {
            bsl::cerr << "Failed to initialize logger manager: "
                         "rc = " << rc << bsl::endl;
            return [% ret %];
[% ret = ret + 1 -%]
        }

        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);

        if (opts.d_logPerformanceFlag) {
            loggerManager.setCategoryVerbosityLevel(LOG_CATEGORY_PERF, 5);
        }

[% IF opts.noSchema -%]
        bcema_PooledBlobBufferFactory blobBufferFactory(8 * 1024);
        bcema_Blob                    request(&blobBufferFactory);
        bcema_Blob                    response(&blobBufferFactory);

        bsl::ifstream ifs(opts.d_requestFilename.c_str());
        if (!ifs) {
            BAEL_LOG_FATAL << "Cannot open request file: "
                           << opts.d_requestFilename
                           << BAEL_LOG_END;
            return [% ret %];
[% ret = ret + 1 -%]
        }
        {
            bcesb_OutBlobStreamBuf osb(&request);
            bsl::ostream           os(&osb);
            os << ifs.rdbuf();
            if (!os) {
                BAEL_LOG_FATAL << "Cannot read request file: "
                               << opts.d_requestFilename
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }
        }

        bcema_Blob expectedResponse(&blobBufferFactory);
        if (opts.d_validateResponseFlag) {
            bsl::ifstream ifs(opts.d_responseFilename.c_str());
            if (!ifs) {
                BAEL_LOG_ERROR << "Failed to open validating response "
                               << "file '"
                               << opts.d_responseFilename << "'"
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            bcesb_OutBlobStreamBuf osb(&expectedResponse);
            bsl::ostream           os(&osb);
            os << ifs.rdbuf();
        }
        rc = sendRequest(&response, request, expectedResponse, opts);
        if (0 != rc) {
            BAEL_LOG_ERROR << "Failed to send request" << BAEL_LOG_END;
            return [% ret %];
[% ret = ret + 1 -%]
        }
[% ELSE -%]
        [% MSGNS %][% RequestType %] request;

        if (opts.d_journalFilename.empty()) {
            bsl::ifstream ifs(opts.d_requestFilename.c_str());
            if (!ifs) {
                BAEL_LOG_FATAL << "Failed to open request file '"
                               << opts.d_requestFilename << "'"
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            basapi::CodecOptions codecOptions;
            codecOptions.xmlDecoderOptions().setSkipUnknownElements(false);

            rc = basapi::CodecUtil::decode(ifs.rdbuf(),
                                           &request,
                                           bsct::EncodingType::XML,
                                           codecOptions);
            if (0 != rc) {
                BAEL_LOG_ERROR << "Error parsing the request" << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            if (opts.d_decodeOnlyFlag) {
                return 0;                                             // RETURN
            }

            // Load and decode the expected response.
            [% MSGNS %][% ResponseType %] expectedResponse;
            if (opts.d_validateResponseFlag) {
                bsl::ifstream ifs(opts.d_responseFilename.c_str());
                if (!ifs) {
                    BAEL_LOG_ERROR << "Failed to open validating response "
                                   << "file '"
                                   << opts.d_responseFilename << "'"
                                   << BAEL_LOG_END;
                    return [% ret %];
[% ret = ret + 1 -%]
                }

                rc = basapi::CodecUtil::decode(ifs.rdbuf(),
                                               &expectedResponse,
                                               bsct::EncodingType::XML,
                                               codecOptions);
                if (0 != rc) {
                    BAEL_LOG_ERROR << "Error parsing the validating response"
                                   << BAEL_LOG_END;
                    return [% ret %];
[% ret = ret + 1 -%]
                }
            }

            rc = sendRequest(request, expectedResponse, opts);
            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to send request"
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }
        }
        else {
#ifdef BAS_NOBBENV
            BAEL_LOG_ERROR << "Replay support is disabled\n"
                           << BAEL_LOG_END;
            return [% ret %];
#else
            a_basfs::Replay replay;
            rc = replay.openJournal(opts.d_journalFilename.c_str());
            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to open journal file "
                               << "'" << opts.d_journalFilename << "'"
                               << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            a_basfs::ReplayRequestCriteria criteria;
            rc = a_basfs::Replay::makeCriteria(&criteria,
                                               bsl::vector<bsl::string>());

            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to create the replay request "
                                  "criteria" << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }

            typedef bsl::vector<bsl::string>::const_iterator Iter;
            for (Iter it =  opts.d_journalRecords.begin();
                      it != opts.d_journalRecords.end();
                    ++it)
            {
                criteria.recordHandle().push_back(bsl::atoi(it->c_str()));
            }

            criteria.serviceId().value() = opts.d_serviceInfo.serviceId();
            criteria.serviceVersionMajor().value() =
                                      opts.d_serviceInfo.serviceVersionMajor();
            criteria.serviceVersionMinor().value() =
                                      opts.d_serviceInfo.serviceVersionMinor();
            criteria.useConfirmed().makeValue(true);
            criteria.useUnconfirmed().makeValue(true);

            ReplayCallback replayCallback(opts);
            rc = replay.run(criteria, replayCallback);

            if (0 != rc) {
                BAEL_LOG_ERROR << "Failed to replay request using criteria '"
                               << criteria << "'" << BAEL_LOG_END;
                return [% ret %];
[% ret = ret + 1 -%]
            }
#endif
        }
[% END -%]
    }
    catch (bsl::exception& e) {
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
        BAEL_LOG_FATAL << e.what() << BAEL_LOG_END;
        return [% ret %];
[% ret = ret + 1 -%]
    }
    catch (...) {
        BAEL_LOG_SET_CATEGORY(LOG_CATEGORY);
        BAEL_LOG_FATAL << "Unknown exception occured" << BAEL_LOG_END;
        return [% ret %];
[% ret = ret + 1 -%]
    }
    return rc;
}

// ----------------------------------------------------------------------------
// NOTICE:
//      Copyright (C) Bloomberg L.P., [% year.format %]
//      All Rights Reserved.
//      Property of Bloomberg L.P. (BLP)
//      This software is made available solely pursuant to the
//      terms of a BLP license agreement which governs its use.
// ------------------------------- END-OF-FILE --------------------------------
