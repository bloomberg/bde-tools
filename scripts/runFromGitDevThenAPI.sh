#!/usr/bin/bash

SCRIPT_NAME=runFromGitDevThenAPI

# redirect outputs so we can track failures - nysbldo2 does
# not mail cron job results
exec > ~bdebuild/logs/log.$SCRIPT_NAME.`date +"%Y%m%d-%H%M%S"` 2>&1

/usr/atria/bin/cleartool startview bde_devintegrator

PATH="/opt/SUNWspro/bin/:/bbcm/infrastructure/tools/bin:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin"
export PATH

# run dev build
/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
       -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config  \
       -f -k -m -idev                                                              \
       bsl zde bde bbe bce bae bte                                                 \
       bsi                                                                         \
       a_bdema a_bteso a_xercesc bsc e_ipc a_ossl a_fsipc bas a_xmf         \
       a_baslt a_bassvc bap a_comdb2 a_basfs a_bascat z_bae a_fsbaem z_bas   \
       < /dev/null 2>&1                                      \
   | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev \
   && /home/bdebuild/bin/report-latest dev

# THEN run api and fde builds
/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
        -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config \
        -f -k -m -idev-api -wbde_devintegrator                                     \
        api apt apu aps apn blpapi                                                 \
        < /dev/null 2>&1                                                \
   | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev-api   \
   && /home/bdebuild/bin/report-latest dev-api &

/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
        -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config \
        -f -k -m -idev-fde -wbde_devintegrator                                     \
        fde                                                                        \
        < /dev/null 2>&1                                              \
  | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.dev-fde       \
  && /home/bdebuild/bin/report-latest dev-fde &

wait


~bdebuild/bin/generateGccWarningsLogs.pl dev bde_devintegrator

