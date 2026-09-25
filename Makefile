.PHONY: build test app clean

build:
	swift build --arch arm64 --product Schreibtischunterlage

test:
	swift test --arch arm64

app:
	./Scripts/build-app.sh

clean:
	swift package clean
