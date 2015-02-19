"""
Bloomberg Python Package - blp.utils - ttengine.py

'ttengine' is a component that tries to emulate Microsoft's T4 Text Template
Generation Engine.  http://msdn.microsoft.com/en-us/library/bb126445.aspx
It takes as input a specially formatted file that serves as a script for
generating a string.  The input script contains normal text with special
command tags which allow access to Python commands.  These commands are
contained within '<#' and '#>' tags in the text.  These commands can run
any valid Python code, make use of variables, if statements, for loops, etc.

Ex:

input = '''Hello all,
The winning numbers are:
<# "Put comments in quotes" #>
<# for i in numbers: #>
    - <#= i #>
<# end #>
Stay tuned next week for more!'''

answer = ttengine.processtext(input, {"numbers" : [4,8,16,32,48,52]})

'''Hello all,
The winning numbers are:
    - 4
    - 8
    - 16
    - 32
    - 48
    - 52
Stay tuned next week for more!'''

"""

__all__ = ["processfile", "processtext"]

import re

def processfile(filepath, symbols = None):
    """ Processes the text in 'filepath' and uses 'symbols' as name/value variables to
        use when evaluating the file.
    """
    filetext = ""
    with open(filepath, "r") as infile:
        filetext = infile.read()

    return processtext(filetext, symbols)

def processtext(text, symbols = None):
    """ Generates a function that will define all the variables in 'symbols' and
        then execute the statements in 'text'.  Return the value of this function
        which will be the generated string.
    """
    if symbols is None:
        symbols = {}

    #Create the code to generate the text
    _output = []
    _gencode = []
    _lines = [_line + '\n' for _line in text.split('\n')]

    #Define variables. This must be done in this function since the scope matters.
    for (_name,_val) in symbols.iteritems():
        exec(compile(_name + " = _val", "<variable_declaration>", "exec"))  #pylint: disable-msg=W0122

    #Generate code for every line
    indent = ""
    for _line in _lines:
        m = re.match(r'(?P<indent>\s*)<#\s+(?P<command>[^#]+)', _line)
        if m:   #Python command, so just insert exactly
            if m.group("command") == "end ":  #Drops one indent level
                indent = indent[:-4]
            else:
                _gencode.append(indent + m.group("command"))
                if m.group("command")[-2:] == ": ":
                    indent = indent + '    '
        else:   #String with possible embedded eval commands
            _line = re.sub(r'<#=\s+([^#]+)#>', r"''' + str(\1) + '''", _line)
            _line = re.sub(r"\\", r"\\\\", _line)
            _gencode.append("%s_output.append('''%s''')" % (indent, _line))

    #Execute and return the output
    exec(compile('\n'.join(_gencode), "<input_text>", "exec"))  #pylint: disable-msg=W0122
    return ''.join(_output)[:-1]


__copyright__ = """
Copyright (C) Bloomberg L.P., 2009
All Rights Reserved.
Property of Bloomberg L.P. (BLP)
This software is made available solely pursuant to the
terms of a BLP license agreement which governs its use.
"""
