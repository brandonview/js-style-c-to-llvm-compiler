all: build

build:
	bison -oparser.c parser.y -d -Wnone; flex -oscanner.c scanner.l; g++ parser.c scanner.c SymbolTable.cc Type.cc -o parser `llvm-config --cppflags` `llvm-config --ldflags` -lLLVM-3.4 -std=c++11
