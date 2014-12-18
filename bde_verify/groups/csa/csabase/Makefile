# Makefile                                                       -*-makefile-*-

CSABASE     = csabase
LIBCSABASE  = libcsabase.a
GCCVERSION  = 4.8.1
GCCDIR      = /opt/swt/install/gcc-$(GCCVERSION)
LLVMVERSION = 3.6.0
SYSTEM      = $(shell uname -s)
LLVMDIR     = /home/hrosen4/mbig/llvm-$(LLVMVERSION)/install-$(SYSTEM)
SHELL       = /opt/swt/bin/bash
CXXFLAGS   += -std=c++11

default: $(CSABASE)

# Set up locations and flags for the compiler that will build bde_verify.
ifeq ($(SYSTEM),Linux)
    COMPILER ?= clang
    ifeq    ($(COMPILER),gcc)
VERSION     = $(GCCVERSION)
CXX         = $(GCCDIR)/bin/g++
AR          = /usr/bin/ar
CXXFLAGS   += -Wno-unused-local-typedefs
    endif
    ifeq ($(COMPILER),clang)
VERSION     = $(LLVMVERSION)
CXX         = $(LLVMDIR)/bin/clang++
    endif
endif
ifeq ($(SYSTEM),SunOS)
    COMPILER ?= gcc
    ifeq    ($(COMPILER),gcc)
VERSION     = $(GCCVERSION)
CXX         = $(GCCDIR)/bin/g++
CXXFLAGS   += -m64 -pthreads -mno-faster-structs -DBYTE_ORDER=BIG_ENDIAN
CFLAGS     += -m64 -pthreads -mno-faster-structs -DBYTE_ORDER=BIG_ENDIAN
AR          = /usr/ccs/bin/ar
CXXFLAGS   += -Wno-unused-local-typedefs
    endif
endif

OBJ         = $(SYSTEM)-$(COMPILER)-$(VERSION)

# Set up location of clang headers and libraries needed by bde_verify.
INCFLAGS   += -I$(LLVMDIR)/include

export VERBOSE ?= @

#  ----------------------------------------------------------------------------

CXXFILES =                                                 \
        csabase_abstractvisitor.cpp                        \
        csabase_analyse.cpp                                \
        csabase_analyser.cpp                               \
        csabase_attachments.cpp                            \
        csabase_checkregistry.cpp                          \
        csabase_clang.cpp                                  \
        csabase_config.cpp                                 \
        csabase_debug.cpp                                  \
        csabase_diagnosticfilter.cpp                       \
        csabase_filenames.cpp                              \
        csabase_format.cpp                                 \
        csabase_location.cpp                               \
        csabase_ppobserver.cpp                             \
        csabase_registercheck.cpp                          \
        csabase_report.cpp                                 \
        csabase_tool.cpp                                   \
        csabase_util.cpp                                   \
        csabase_visitor.cpp                                \

# -----------------------------------------------------------------------------

DEFFLAGS += -D__STDC_LIMIT_MACROS
DEFFLAGS += -D__STDC_CONSTANT_MACROS
INCFLAGS += -I.
CXXFLAGS += -g -fno-common -fno-strict-aliasing -fno-exceptions -fno-rtti

OFILES = $(CXXFILES:%.cpp=$(OBJ)/%.o)

$(CSABASE): $(OBJ)/$(LIBCSABASE)

$(OBJ)/$(LIBCSABASE): $(OFILES)
	@echo creating library
	$(VERBOSE) $(AR) cr $@ $(OFILES)

$(OBJ)/%.o: %.cpp
	@if [ ! -d $(@D) ]; then mkdir -p $(@D); fi
	@echo compiling $(@:$(OBJ)/%.o=%.cpp)
	$(VERBOSE) $(CXX) $(INCFLAGS) $(DEFFLAGS) $(CXXFLAGS) $(WARNFLAGS) \
                          -o $@ -c $(@:$(OBJ)/%.o=%.cpp)

.PHONY: clean

clean:
	@echo cleaning files
	$(VERBOSE) $(RM) $(OFILES)
	$(VERBOSE) $(RM) $(OBJ)/$(LIBCSABASE)
	$(VERBOSE) $(RM) $(OBJ)/make.depend
	$(VERBOSE) $(RM) -r $(OBJ)
	$(VERBOSE) $(RM) mkerr olderr *~

# -----------------------------------------------------------------------------

.PHONY: depend

depend $(OBJ)/make.depend:
	@if [ ! -d $(OBJ) ]; then mkdir $(OBJ); fi
	@echo analysing dependencies
	$(VERBOSE) $(CXX) $(INCFLAGS) $(DEFFLAGS) -M $(CXXFILES)                  \
            $(filter-out -Wno-unused-local-typedefs, $(CXXFLAGS))             \
		| perl -pe 's[^(?! )][$(OBJ)/]' > $(OBJ)/make.depend

ifneq "$(MAKECMDGOALS)" "clean"
    include $(OBJ)/make.depend
endif

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
