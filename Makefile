TARGET := iphone:clang:latest:12.0
OneKeepAlive_LDFLAGS += -Wl,-install_name,@executable_path/Frameworks/OneKeepAlive.dylib
