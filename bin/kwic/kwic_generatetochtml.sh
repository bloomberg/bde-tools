#!/usr/bin/ksh
#==============================================================================
# Syntax:  kwic_generatetochtml.sh [-h] [-t <title>] [-c <css>] [-c <path>] \
#                                  [-f <suffix>]
# Purpose: Convert extracted '@PURPOSE' contents to HTML Table.
#==============================================================================

syntax="Syntax: "
syntax="${syntax}kwic_generatetochtml.sh [-h] [-t <title>] [-c <css>]"
syntax="${syntax}\n\t\t\t\t[-p <path>]"
syntax="${syntax}\n\t\t\t\t[-f <suffix>]"
syntax="${syntax}\n\t-h          -- print help message"
syntax="${syntax}\n\t-t <title>  -- generate specified title"
syntax="${syntax}\n\t-c <css>    -- use specified css file"
syntax="${syntax}\n\t               (default: kwic_bde_go.CSS)"
syntax="${syntax}\n\t-p <path>   -- path for html links"
syntax="${syntax}\n\t-f <suffix> -- strip specified suffix from file names"
syntax="${syntax}\n\t               (default: _8h_source.html)"

#------------------------------------------------------------------------------
# Defaults
#------------------------------------------------------------------------------

: ${CSS:="kwic_bde_go.CSS"}
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
function linkToHeaderPage(doxygenSourceFile) {
    href    = doxygenSourceFile
    display = doxygenSourceFile

	sub(".*/", "", href);
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

BEGIN { FS="|";

    title = "'"${TITLE}"'";

    printf "<html>\n"
    printf "<head>\n"

    if (title) {
        printf "<title>" title "</title>\n";
    }

    printf "<link rel=\"stylesheet\" type=\"text/css\" href=\"'"${CSS}"'\"/>\n"

    printf "<style>\n"
#    printf "a         { color: #f07c0a; text-decoration: none;\n"
#    printf "            white-space: nowrap;\n"
#    printf "          }\n"
    printf "a:hover   { color: #f07c0a; text-decoration: underline}\n"
    printf "a:link    { color: black; text-decoration: none }\n"
#    printf "a:visited { color: #f07c0a; text-decoration: none}\n"
    printf "</style>\n"
    printf "</head>\n"
    printf "<body>\n"

    if (title) {
        printf "<h1>" title "</h2>\n";
    }

    printf "<table>\n"
    printf "<col valign=\"top\" align=\"left\">\n"
    printf "<col valign=\"top\" align=\"left\">\n"
    printf "<thead>\n";
    printf "<th>Component Source</th>\n";
    printf "<th>Purpose</th>\n";
    printf "</thead>\n";
}
    {
        printf "<tr>\n";
        printf "<td>%s</td>\n", linkToHeaderPage($1)
        printf "<td>%s</td>\n", linkToComponentPage($1, $2);
        printf "</tr>\n";
        printf "\n";
    }
END {    printf "</table>\n"

        printf "</body>\n"
        printf "</html>\n"
    }
'
