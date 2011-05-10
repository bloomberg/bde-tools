[% USE String -%]
[% USE Dumper -%]
[%#
     Some useful vars & macros
-%]
[% SET namespace = String.new(cmp.package).lower -%]
[% SET basename = cmp.package _ '_' _ cmp.component -%]
[% USE year = date(format => '%Y') -%]
