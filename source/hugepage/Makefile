LEVEL = ../..
DYLIB_NAME = libhugepage_text_rt.so
CXX= g++

# Build and install this archive.                                                                                                            
CXXFLAGS=-O3 -std=c++11 -fPIC -Wall

.cc.o:
	$(CXX) -c $(CXXFLAGS) $< -o $@

all: hugepage_text.o
	$(CXX) -shared  $(CXXFLAGS) $^ -o $(LEVEL)/build/$(DYLIB_NAME)  $(LDFLAGS)
clean:
	rm -f $(LEVEL)/build/$(DYLIB_NAME) *.o

