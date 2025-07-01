#!/bin/bash
set -e

if [ ! -d build ]; then
  exit 0
fi

find build -type d -name 'CMakeFiles' | while read -r cmake_dir; do
  build_dir=$(dirname "$cmake_dir")
  if [ -f "$build_dir/Makefile" ] || [ -f "$build_dir/build.ninja" ]; then
    echo "Cleaning $build_dir"
    (cd "$build_dir" && cmake --build . --target clean || true)
  fi
done