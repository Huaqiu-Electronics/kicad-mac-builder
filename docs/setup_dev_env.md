# Setup development environment

## Build dependencies

```bash
export WX_SKIP_DOXYGEN_VERSION_CHECK=1  

./build.py --arch=arm64 --target setup-kicad-dependencies

```

-DCMAKE_TOOLCHAIN_FILE=/Users/admin/code/kicad-mac-builder/toolchain/kicad-mac-builder.cmake