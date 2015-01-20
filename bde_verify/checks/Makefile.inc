# Makefile.inc                                                   -*-makefile-*-
VERBOSE ?= @

BDEVERIFY ?= $(BDE_VERIFY_DIR)/scripts/bde_verify

ALL ?= off

define CHECKARGS
    -nodefdef                                                                 \
    -config=/dev/null                                                         \
    -cl='namespace bde_verify'                                                \
    -cl='all $(ALL)'                                                          \
    $(foreach N,$(CHECKNAME),-cl='check $(N) on')                             \
    -Wno-string-plus-int                                                      \
    -std=c++11                                                                \
    -D_X86INTRIN_H_INCLUDED                                                   \
    -I $(BDE_VERIFY_DIR)/groups/csa/csadep                                    \
    -I $(BDE_VERIFY_DIR)/checks/include                                       \
    $(BDE_VERIFY_ARGS)
endef

define CHECK
	$(VERBOSE) $(BDEVERIFY) $(CHECKARGS) $(basename $@) 2>&1 | \
        diff -q - *.exp >/dev/null && echo OK $(basename $@) || \
    $(BDEVERIFY) $(CHECKARGS) $(basename $@) 2>&1 | \
        diff - *.exp
endef

define RUN
	$(VERBOSE) $(BDEVERIFY) $(CHECKARGS) -fcolor-diagnostics $(basename $@)
endef

CHECKFILES = $(patsubst %,%.check,$(FILES))
RUNFILES   = $(patsubst %,%.run,$(FILES))

.PHONY: run check $(CHECKFILES) $(RUNFILES)

check: $(CHECKFILES)

$(CHECKFILES):
	$(CHECK)

run: $(RUNFILES)

$(RUNFILES):
	$(RUN)

## ----------------------------------------------------------------------------
## Copyright (C) 2014 Bloomberg Finance L.P.
##
## Permission is hereby granted, free of charge, to any person obtaining a copy
## of this software and associated documentation files (the "Software"), to
## deal in the Software without restriction, including without limitation the
## rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
## sell copies of the Software, and to permit persons to whom the Software is
## furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in
## all copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
## IN THE SOFTWARE.
## ----------------------------- END-OF-FILE ----------------------------------
