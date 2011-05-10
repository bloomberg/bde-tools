# vanilla.spec
#-------------------------------------------------------------------------------
# This config spec provides the simplest possible 'correct' view for BDE
# development. It can be used in an emergency, in the event that a view's
# config spec has become disfunctional.
#
# This file should not be customised. Use bde.config.spec for a configurable
# view and follow the instructions there.
#
# Queries: contact Peter Wainwright (pwainwright@bloomberg.net)
#-------------------------------------------------------------------------------

element * CHECKEDOUT
element * .../dev/LATEST
element * /main/bb/LATEST -mkbranch dev
element * /main/LATEST -mkbranch bb
