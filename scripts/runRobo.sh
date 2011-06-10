#!/usr/bin/bash


#########################################
##
## 2010-06-30 - disabling robo builds
##  Mike G., this can be disabled now.  The merge of bsl_hybrid_stl to dev will
##  be completed today.  We'll have you lock the branch soon (but not just yet).
##  Thanks, clay
##
#########################################

exit 0

export PATH="/opt/SUNWspro/bin/:/bbcm/infrastructure/tools/bin:/usr/bin:/usr/sbin:/sbin:/usr/bin/X11:/usr/local/bin:/bb/bin:/bb/shared/bin:/bb/shared/abin:/bb/bin/robo:/bbsrc/tools/bbcm:/bbsrc/tools/bbcm/parent:/usr/atria/bin:$PATH"

/usr/atria/bin/cleartool startview bde_devintegrator
/usr/atria/bin/cleartool startview bde_integrator

#/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
#        -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config \
#        -w bde_integrator -f -k -m -irobo                                          \
#        bsl bde bbe bce bae bte                                                    \
#        bsi                                                                        \
#        a_bdema a_bteso a_xercesc bsc e_ipc a_ossl a_fsipc bas a_xmf        \
#        a_baslt bap a_comdb2 a_basfs a_bascat z_bae a_fsbaem z_bas      \
#        < /dev/null 2>&1     \
#    | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.robo

/view/bde_devintegrator/bbcm/infrastructure/tools/bin/bde_bldmgr -v                \
        -k /view/bde_devintegrator/bbcm/infrastructure/tools/etc/bde_bldmgr.config \
        -w bde_integrator -f -k -m -irobo                                          \
        bsl bde bbe bce bae bte                                                    \
        < /dev/null 2>&1     \
    | /home/bdebuild/bin/logTs.pl /home/bdebuild/logs/log.robo

/home/bdebuild/bin/report-latest robo

/home/bdebuild/bin/generateGccWarningsLogs.pl bslbranch bde_integrator


