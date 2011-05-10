#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_generateindexhtml.sh [-h] [-t <title>] \
#                                    [-c <css>] [ -p <path>] [-f <suffix>]
# Purpose: Convert extracted/permuted/sorted '@PURPOSE' contents to HTML Table.
#==============================================================================

syntax="Syntax: "
syntax="${syntax}kwic_generateindexhtml.sh [-t <title>]" 
syntax="${syntax} [-c <css>]"
syntax="${syntax} [-p <path>]"
syntax="${syntax} [-f <suffix>]"
syntax="${syntax}\n\t-h          -- print help message"
syntax="${syntax}\n\t-t <title>  -- generate specified title"
syntax="${syntax}\n\t-c <css>    -- use specified css file"
syntax="${syntax}\n\t               (default: kwic_bde_go.CSS)"
syntax="${syntax}\n\t-p <path>  --  path for html links"
syntax="${syntax}\n\t               (default: current directory)"
syntax="${syntax}\n\t-f <suffix> -- strip specified suffix from file names"
syntax="${syntax}\n\t               (default: _8h_source.html)"

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

: ${CSS:="bde_go.css"}
: ${SUFFIX:="_8h_source.html"}
: ${HTML_PATH:="./"}

#------------------------------------------------------------------------------
# Parameter Parsing
#------------------------------------------------------------------------------

while getopts ":t:c:p:f:h" opt; do
    case $opt in
     t )
        TITLE=$OPTARG;;
     c )
        CSS=$OPTARG;;
	 p )
		HTML_PATH=$OPTARG;;
     f )
        SUFFIX=$OPTARG;;
     h )
        print "${syntax}"
        exit 0;;
     * )
        print -u2 "${syntax}"
        exit 1;;
    esac
done
shift $(($OPTIND - 1))

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------

nawk '

function linkToComponentPage(doxygenSourceFile, display) {
    href = doxygenSourceFile
	#print "linkToComponentPage: href: ", href

    sub("'"${SUFFIX}"'$", "", href);
	#print "linkToComponentPage: href: ", href
    sub("$", ".html", href);
	#print "linkToComponentPage: href: ", href

	sub("^.*/", "", href);
    sub("^", "group__", href);
    html_path = "'"${HTML_PATH}"'";
	if (html_path) {
		href = html_path href
	}
	#print "linkToComponentPage: href: ", href

    link = "<a href=\""
	link = link href
	link = link "\">"
	link = link display
	link = link "</a>"
    return link
}

function linkToHeaderPage(doxygenSourceFile) {
    href    = doxygenSourceFile
    display = doxygenSourceFile

	sub("^.*/", "", href);
    html_path = "'"${HTML_PATH}"'";
	if (html_path) {
		href = htmp_path href;
	}

	sub("^.*/", "", display);
    sub("'"${SUFFIX}"'$", "", display);
    gsub("__", "_", display);

    link = "<a href=\""
	link = link href;
	link = link "\">"
	link = link "<code class=CW>"
	link = link display
	link = link "</code>"
	link = link "</a>"

    return link
}

function embolden1(string) {
    nfields = split(string, fields, ORIG_FS);
    outString = ""
    for (i = 1; i <= nfields; ++i) {
        if (1 == i) {
                   if (sub(/\.$/, "", fields[i])) {
                        outString = "<strong>" fields[i] "</strong>."
            } else if (sub(/\,$/, "", fields[i])) {
                        outString = "<strong>" fields[i] "</strong>,"
            } else {
                        outString = "<strong>" fields[i] "</strong>"
            }
        } else {
            outString = outString " " fields[i];
        }
    }
    return outString
}

BEGIN { ORIG_FS = FS;
        FS="|";

    title = "'"${TITLE}"'";


    printf "<html>\n"
    printf "<head>\n"

    if (title) {
        printf "<title>" title "</title>";
    }

    printf "<link rel=\"stylesheet\" type=\"text/css\" href=\"'"${CSS}"'\"/>\n"
    printf "<style>\n"
    printf "a         { color: #f07c0a; text-decoration: none;\n"
    printf "            white-space: nowrap;\n"
    printf "          }\n"
#    printf "a:hover   { color: #f07c0a; text-decoration: underline}\n"
#    printf "a:link    { color: #f07c0a; text-decoration: none }\n"
#    printf "a:visited { color: #f07c0a; text-decoration: none}\n"
    printf "a:hover   { color: #f07c0a; text-decoration: underline}\n"
    printf "a:link    { color: black; text-decoration: none }\n"
    printf "</style>\n"
    printf "</head>\n"
    printf "<body\n>"

    if (title) {
        printf "<h1>" title "</h2>";
    }

    printf "<table>\n"
    printf "<col valign=\"top\"    align=\"right\" width=\"30%\">\n"
    printf "<col valign=\"bottom\" align=\"left\"  width=\"50%\">\n"
    printf "<col valign=\"bottom\" align=\"left\"  width=\"20%\">\n"
    printf "<thead>\n";
    printf "<th align=\"left\">Purpose</th>\n";
    printf "<th></th>\n";
    printf "<th align=\"left\">Component Source</th>\n";
    printf "</thead>\n";
}
    {
        printf "<tr>\n";
        printf "<td>%s</td>\n", $3
        printf "<td>%s</td>\n", linkToComponentPage($4, embolden1($2))
        printf "<td>%s</td>",   linkToHeaderPage($4)
        printf "</tr>\n";
        printf "\n"
    }
END {
        printf "</table>\n"

        printf "</body>\n"
        printf "</html>\n"
    }
'
