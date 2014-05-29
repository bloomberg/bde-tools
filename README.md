#BDE Tools

This repository contains a collection of useful tools to help with the
development of the [BDE libraries](https://github.com/bloomberg/bde),
including:

* [Waf-Based Build Tool](http://github.com/bloomberg/bde-tools/wiki/Waf-Build)
* bde_verify

##Waf-Based Build tool

This build tool builds on top of [waf](https://code.google.com/p/waf/) to
support building BDE-style repositories (including the open source BDE
libraries hosted on github).

For detail documentation, please see the
[wiki](http://github.com/bloomberg/bde-tools/wiki/Waf-Build)

##bde_verify

This tool performs a variety of checks intended to foster improved adherence to
BDE design rules,
[coding standards](https://github.com/bloomberg/bde/wiki/bdestds.pdf), and
practices and to detect potential errors. It is built within the clang C++
compiler tool system, and therefore has access to proper syntax and type
information about the program it is examining, unlike text-based scanning
tools.

#License

The BDE tools repository is distributed under a simple MIT-style license; see the
LICENSE file at the top of the source tree for more information.

#Question, Comments and Feedback

If you have questions, comments, suggestions for improvement or any other
inquiries regarding BDE, feel free to open an issue in the
[issue tracker](https://github.com/bloomberg/bde-tools/issues).
