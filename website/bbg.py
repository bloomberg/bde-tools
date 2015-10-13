#!/usr/bin/python
# Enable CGI debugging output
import cgitb

cgitb.enable()

import cgi


_fieldStore = cgi.FieldStorage()


print "Location: bbg://screens/DRQS %s\n\n" % _fieldStore["drqs"].value;
