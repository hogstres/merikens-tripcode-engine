#!/bin/sh
cd BoostPackages
7z x boost_1_61_0.7z
cd boost_1_61_0
./bootstrap.sh 
./b2 link=static runtime-link=static -j 8
cd ../..
mkdir CMakeBuild
cd CMakeBuild
cmake ../CMake
make
