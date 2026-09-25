.PHONY: build test app clean

build:
	swift build --arch arm64

test:
	swift run --arch arm64 SchreibtischunterlageCoreTests

app:
	./Scripts/build-app.sh

clean:
	swift package clean
