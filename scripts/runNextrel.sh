#!/usr/bin/bash

export PATH="/opt/SUNWspro/bin/:/bbcm/infrastructure/tools/bin:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin:$PATH"

/usr/atria/bin/cleartool startview bde_devintegrator
/usr/atria/bin/cleartool startview bde_releaseintegrator2
/usr/atria/bin/cleartool startview bde_devapinextrelbdebas

/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
        -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config \
        -w bde_releaseintegrator2 -f -k -m -inextrel                               \
        bsl zde bde bbe bce bae bte                                                \
        bsi                                                                        \
        a_bdema a_bteso a_xercesc bsc e_ipc a_ossl a_fsipc bas a_xmf        \
        a_baslt a_bassvc bap a_comdb2 a_basfs a_bascat z_bae a_fsbaem z_bas      \
        < /dev/null 2>&1    \
    | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.nextrel

/home/bdebuild/bin/report-latest nextrel

/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config -f -k -m -inextrel-api -wbde_releaseintegrator2                   \
                  api apt apu aps blpapi                                           \
                  < /dev/null 2>&1 |                                               \
   /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.nextrel-api                 \
   && /home/bdebuild/bin/report-latest nextrel-api &

/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config -f -k -m -idev-nextrel-api -wbde_devapinextrelbdebas              \
                  api apt apu aps blpapi                                           \
                  < /dev/null 2>&1 |                                               \
   /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev-nextrel-api             \
   && /home/bdebuild/bin/report-latest dev-nextrel-api &

wait

/home/bdebuild/bin/generateGccWarningsLogs.pl nextrel bde_releaseintegrator2

rsync -va /view/bde_releaseintegrator2/bbcm/infrastructure/lib     \
          /view/bde_releaseintegrator2/bbcm/infrastructure/include \
          /bbshr/bde/releases/nightly_beta

