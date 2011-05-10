# release.spec
#------------------------------------------------------------------------------
# This is a specialised view for working on release mechanics. If you are not
# involved in rolling releases or invoking the makefile generator you should
# probably not be using it.
#
# Queries: contact Peter Wainwright (pwainwright@bloomberg.net)
#------------------------------------------------------------------------------

element * CHECKEDOUT

element /bbcm/infrastructure/bin/... /main/bb/dev/LATEST
element /bbcm/infrastructure/bin/... /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/etc/... /main/bb/dev/LATEST
element /bbcm/infrastructure/etc/... /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/*/*scm/... /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/*/*scm/... /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/*/group/*.mk /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/*/group/*.mk /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/*/group/*.nmk /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/*/group/*.nmk /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/*/group/*.sum /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/*/group/*.sum /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/*/group/*.vars /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/*/group/*.vars /main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/groups/releases/BLP_LIB_BDE/... /main/bb/dev/LATEST
element /bbcm/infrastructure/groups/releases/BLP_LIB_BDE/... /main/bb/LATEST -mkbranch dev

# Enable and adjust this line to point at a specific labelled release
# element * BLP_LIB_BDE_0.01.6       -nocheckout

element * /main/bb/LATEST -nocheckout
element * /main/LATEST    -nocheckout
