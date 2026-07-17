# Native UI tests

Open `FamilyTreeStudioUI.xcworkspace` in full Xcode and run the shared
`FamilyTreeStudio-UI` scheme. Production sources and dependencies still come from the
Swift package; the small `.xcodeproj` contains only the native XCUITest bundle. Every
test launches with a unique `--storage-folder`, so it cannot touch a development or
real family library.

The command-line-only toolchain cannot execute XCUITest. Internal release acceptance
therefore requires this scheme to pass on a full-Xcode machine before packaging.
