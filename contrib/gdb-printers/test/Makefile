# Build all of the test programs

ARCH=linux

TARGETS=$(patsubst %.cpp,%,$(wildcard *.cpp))
TASKS=$(patsubst %.cpp,%.linux.tsk,$(wildcard *.cpp))

%.linux.tsk : %.cpp
	pcomp $<

all : $(TASKS)

.PHONY : $(TARGETS)
$(TARGETS) : % : %.linux.tsk

.PHONY : clean
clean:
	rm -f *.o *.tsk
