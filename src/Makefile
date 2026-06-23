CXX      = g++
CXXFLAGS = -std=c++98
TARGET   = generator
DESTDIR  = ..

all: $(TARGET)

build:
	mkdir -p ../build

clean:
	rm $(DESTDIR)/$(TARGET)

$(TARGET): build config_parser.cc config_parser_fetch.cc config_parser_make.cc error.cc utils.cc generator.cc
	$(CXX) $(CXXFLAGS) config_parser.cc config_parser_fetch.cc config_parser_make.cc error.cc utils.cc generator.cc -o $(DESTDIR)/$(TARGET)
