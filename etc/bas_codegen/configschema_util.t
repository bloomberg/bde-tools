[% USE String -%]
[% USE Dumper -%]
[%#
     Some useful vars & macros
-%]
[% USE year = date(format => '%Y') -%]
[% SET PKG = String.new(opts.package).upper -%]
[% SET pkg = String.new(PKG).lower -%]
[% SET namespace = pkg -%]
[% SET MSGPKG = String.new(opts.msgLibrary).upper -%]
[% SET msgpkg = String.new(MSGPKG).lower -%]
[% SET msgnamespace = msgpkg -%]
[% SET MSGNS = (pkg == msgpkg) ? '' : String.new(msgpkg).append('::') -%]
