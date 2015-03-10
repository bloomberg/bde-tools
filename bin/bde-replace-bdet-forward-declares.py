#!/opt/bb/bin/python

import os
import sys
import optparse
import re
import shutil
import datetime

USAGE = """
 Usage: %prog [options] file
"""

DESCRIPTION = """
This script updates forward declarations of vocabulary date & time types in the
'bdet' package (e.g., 'bdet_Date') to refer to their open-source variants in
the 'bdlt' package (e.g., 'bdlt::Date').  Aliases to the 'bdet' type names
are maintained to allow code that used the 'bdet' forward declares to continue
to compile.
""".lstrip()

FORWARD_DECLARATIONS = {
    "TimeInterval"     : "bsls",
    "MonthOfYear"      : "bdlt",
    "DayOfWeek"        : "bdlt",
    "DatetimeInterval" : "bdlt",
    "DayOfWeekSet"     : "bdlt",
    "Time"             : "bdlt",
    "Date"             : "bdlt",
    "TimeTz"           : "bdlt",
    "Datetime"         : "bdlt",
    "DateTz"           : "bdlt",
    "DatetimeTz"       : "bdlt",
}

PREAMBLE_UPDATE = """
// Updated by 'bde-replace-bdet-forward-declares.py -m bdlt': {0}
// Updated declarations tagged with '// bdet -> bdlt'.

""".format(datetime.datetime.now().strftime("%Y-%m-%d"))

PREAMBLE_REMOVE = """
// Updated by 'bde-replace-bdet-forward-declares.py -m include': {0}
// New includes and commented out BDE 2.23 compatible declarations tagged with
// '// bdet -> #include'.
""".format(datetime.datetime.now().strftime("%Y-%m-%d"))


class PlainHelpFormatter(optparse.IndentedHelpFormatter):
    """
    Formatter that works with 'optparse' that does not modify the formatting
    of the text.
    """   
    def format_description(self, description):
        if description:
            return description + "\n"
        else:
            return ""


class InputError(Exception):
    """
    Exception raised for errors in the user input.

    Attributes:
        msg  -- explanation of the error
    """
    def __init__(self, msg):        
        self.msg = msg
        return


def add_right_justified_comment(text, comment):
    """
    Append the specified 'comment', right justified, to each line in the
    specified 'text'

    Parameters:
        text(string) - text to which to append 'comment'

        commnt(string) - the comment to append
   """

    text_lines = text.splitlines(False)

    for index, line in enumerate(text_lines):
        text_lines[index] = line + comment.rjust(79-len(line)) + "\n"

    return "".join(text_lines)

def get_replacement_text(namespace, typename, comment):
    """
    Return the replacement forward declaration for the specified 'typename' in
    the specified 'namespace'.  Append and right-justify the
    specified 'comment' to the lines of text. 
    
    Parameters:         
        namespace(string) - the opensource namespace 'typename'
          belongs in
          
        typename(string) - the type name to replace with a bdlt type name (no
          namespace

        comment(string) - a comment to append to each line (right-justified)

    Returns:
        string - the forward delcaration text for 'typename'
    """

    forward_declare = "namespace {0} {{ class {1}; }}".format(
        namespace,
        typename)

    alias_declare = "typedef ::BloombergLP::{0}::{1} {2};".format(
        namespace,
        typename,
        "bdet_" + typename)

    # Right justify comment tags
    
    forward_declare = forward_declare + comment.rjust(79-len(forward_declare))
    alias_declare   = alias_declare + comment.rjust(79-len(alias_declare))

    return "\n".join(["", forward_declare, alias_declare, ""])


def get_include_text(header):
    """
    Return the #include text for the specified 'header'.  Note that the
    identifying comments are right justified to 79 characters.

    Parameters:         
        header(string) - the name of the header to #include
          
    Returns:
        string - the text for including 'header'
    """

    postfix = "// bdet->#include"
    
    # Right justify comment tags

    lines = [
        "#ifndef INCLUDED_{0}".format(header.upper()),
        "#include <{0}.h>".format(header),
        "#endif"
        ]

    lines = map(lambda x: x + postfix.rjust(79 - len(x)), lines)
        
    return "\n" + "\n".join(lines) + "\n"

                              
def convert_bdet_to_bdlt(text, verbose = False):
    """
    Return a string having the specified 'text' but with forward declarations
    to 'bdet' vocabulary types replaced with forward declarations to 'bdlt'
    types.
    """

    count = 0
    for key, value in FORWARD_DECLARATIONS.iteritems():
        replacement = get_replacement_text(value, key, "// bdet->bdlt")
        (text, num) = re.subn(
                             "^\s*(class\s*{0}\s*;).*\n".format("bdet_" + key),
                             replacement,
                             text,
                             0,
                             re.MULTILINE)
        count = count + num
        
    # Find the first updated forward declare and prepend the preamable text.
    if (count > 0):
        match = re.search("^namespace.*// bdet->bdlt$",
                          text,
                          re.MULTILINE)
        start = match.start()
        text = text[:start] + PREAMBLE_UPDATE + text[start:]
    
    return text

def undo_convert_bdet_to_include(text):

    (text, num) = re.subn("^// *(class .*;) *// bdet->#include$\n",
                          "\\1 \n",
                          text,
                          flags=re.MULTILINE)

    (text, num) = re.subn("^.*// bdet->#include$\n",
                          "",
                          text,
                          flags=re.MULTILINE)
    (text, num) = re.subn("\n// Updated.*\n.*\n.*bdet -> #include'\..*\n",
                          "",
                          text)
    return text

    
def convert_bdet_to_include(text, verbose = False):
    """
    Return a string having the specified 'text' but with forward declarations
    to 'bdet' vocabulary types replaced with #include to headers for those
    types.
    """

    new_includes         = []
    for key, value in FORWARD_DECLARATIONS.iteritems():
        bdet_typename = "bdet_" + key
        bdet_header   = "bdet_" + key.lower()

        replacement = "// class {0};".format(bdet_typename)
        replacement = add_right_justified_comment(replacement,
                                                  "// bdet->#include")

        (text, num) = re.subn(
                             "^\s*(class\s*{0}\s*;).*\n".format(bdet_typename),
                             replacement,
                             text,
                             0,
                             re.MULTILINE)
        if (num > 0):
            if (not re.search("^\s*#include\s*<{0}\\.h>".format(bdet_header),
                              text,
                              re.MULTILINE)):
                new_includes.append(bdet_header)

    if (len(new_includes) == 0):
        return text

    text_lines = text.splitlines(True)

    insertion_point = 0
    for index, line in enumerate(text_lines):
        if (re.search("^\s*#if(?!ndef INCLUDED_)", line)):
            break
            
        if (re.search("^\s*#include\s<.*>", line)):
            insertion_point = index + 1
            if (re.search("\s*endif", text_lines[index + 1])):
                insertion_point = index+2


    new_text = PREAMBLE_REMOVE
    for include in new_includes:
        new_text += get_include_text(include)

    return "".join(text_lines[0:insertion_point] +\
                   [new_text] +\
                   text_lines[insertion_point:])


def main():
    parser = optparse.OptionParser(
                        usage       = USAGE,
                        description = DESCRIPTION,
                        formatter   = PlainHelpFormatter())

    parser.disable_interspersed_args()

    parser.add_option(
        "-v",
        "--verbose",
        action="store_true",
        dest="verbose",
        default=False,
        help="Print verbose output")


    parser.add_option(
        "-c",
        "--check",
        action="store_true",
        dest="check",
        default=False,
        help="Check if a file would be modified by this script")

    parser.add_option(
        "-o",
        "--overwrite",
        action="store_true",
        dest="overwrite",
        default=False,
        help="To overwrite the existing file, rather than output to the "\
             "console.  The old file is backed up as filename.orig")

    parser.add_option(
        "-m",
        "--mode",
        action="store",
        dest="mode",
        default="include",
        help="Either \"include\" or \"bdlt\".  If \"include\" forward "\
             "declares of 'bdet' types are replaced with a #include for that "\
             "type.  If \"bdlt\" then forward delcares of 'bdet' types are "\
             "replaced by forward declares of 'bdlt' types. "\
             "[default: include]")

    (options, args) = parser.parse_args()

    if (options.mode != "include" and options.mode != "bdlt"):
        parser.error('--mode option must be either "include" or "bdlt"')

    if (0 >= len(args)):
        parser.error("File name required")

    if (not os.path.isfile(args[0])):
        parser.error("File not found: {0}".format(args[0]))

    try:
        with open(args[0], "r") as input_file:
            original_text = input_file.read()

        text = original_text

        if (options.verbose):
            print("Processing {0}".format(args[0]))

        if (options.mode == "bdlt"):
            text = undo_convert_bdet_to_include(text)
            text = convert_bdet_to_bdlt(text, options.verbose)
        else:
            text = convert_bdet_to_include(text, options.verbose)

        if (options.check):
          if(text != original_text):
              print("\tForward declarations found: {0}".format(args[0]))
              sys.exit(0)
          sys.exit(1)
      
        elif (options.overwrite):
            if (text != original_text):
                print("\tUpdating: {0}".format(args[0]))
                shutil.copyfile(args[0], args[0]+".orig")
                with open(args[0], "w") as output_file:
                    output_file.write(text)
        else:
            (text, num) = re.subn("\n$", "", text);
            print text
        
    except InputError as e:
        parser.error(e.msg)

    except KeyError as e:
       parser.error("Invalid configuration.  Error on element: {0}".format(e))
        
if __name__ == "__main__":
    main()

