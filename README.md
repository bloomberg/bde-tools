#BDE Tools

This repository contains a collection of useful tools to help with the
development of [BDE libraries](https://github.com/bloomberg/bde),
including:

* [Waf-Based Build System](http://github.com/bloomberg/bde-tools/wiki/Waf-Build)

##Waf-Based Build System

This repository provides a system, based on
[waf](https://code.google.com/p/waf/), for building code whose source files are
organized according to the
[BDE Style](https://github.com/bloomberg/bde-tools/wiki/BDE-Style-Repository).
This is the tool used to build the
[BDE libraries](https://github.com/bloomberg/bde).

For detail documentation, please see the
[Waf Build System Wiki](http://github.com/bloomberg/bde-tools/wiki/Waf-Build)

##Future Plans

The following tools will be made available in the near future:

* bde_verify

  `bde_verify` is a static analysis tool that verifies that source code adheres
  to the
  [BDE coding standards](https://github.com/bloomberg/bde/wiki/Introduction-to-BDE-Coding-Standards).
  It is built within the clang C++ compiler tool system, and therefore has
  access to proper syntax and type information about the program it is
  examining, unlike text-based scanning tools.

#License

The BDE tools repository is distributed under a simple MIT-style license; see the
LICENSE file at the top of the source tree for more information.

#Question, Comments and Feedback

If you have questions, comments, suggestions for improvement or any other
inquiries regarding BDE, feel free to open an issue in the
[issue tracker](https://github.com/bloomberg/bde-tools/issues).
