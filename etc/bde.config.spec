# BDE development config.spec
#-------------------------------------------------------------------------------
# This file is NOT editable. To change the view, edit bde.config.dirs instead.

# Checked out files:
element *						CHECKEDOUT

# Activity branch(es):

# Special cases
element /bbcm/infrastructure/etc/default.config.dirs	/main/bb/dev/LATEST
element /bbcm/infrastructure/etc/default.config.dirs	/main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/etc/default.config.dirs	/main/LATEST -mkbranch bb
element /bbcm/infrastructure/etc/vanilla.spec		/main/bb/dev/LATEST
element /bbcm/infrastructure/etc/vanilla.spec		/main/bb/LATEST -mkbranch dev
element /bbcm/infrastructure/etc/vanilla.spec		/main/LATEST -mkbranch bb

# Per-directory rules file
include /bbcm/infrastructure/etc/bde.config.dirs

# All other files and directories:
element *						/main/bb/LATEST -nocheckout
element *						/main/LATEST -nocheckout
