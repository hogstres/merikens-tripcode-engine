﻿Meriken's Tripcode Engine
=========================

"Meriken's Tripcode Engine" is a Windows application designed to generate custom/vanity tripcodes at maximum speed. 
It is arguably the fastest and most powerful program of its kind. It makes effecitive use of available computing power of CPUs and GPUs, 
and the user can specify flexible regex patterns for tripcodes. It features highly optimized, extensively parallelized 
implementations of bitslice DES and SHA-1 for OpenCL, AMD GCN, NVIDIA CUDA, and Intel SSE2/AVX/AVX2.

The English version of this program is available for free download here:

http://meriken.ygch.net/programming/merikens-tripcode-engine-english/

This program is part of "Meriken's Tripcode Generator," a GUI-based tripcode generator targeted primarily to users in Japan:

http://meriken.ygch.net/programming/merikens-tripcode-generator/

## Prerequisites

You need the following software installed:

* [Microsoft Visual C++ 2010 Redistributable Package (x86)][1]
* Microsoft Visual C++ 2010 Redistributable Package (x64)
  (if you are using a 64bit operating system)
* Visual C++ Redistributable for Visual Studio 2015
  (if you are using an AMD graphics card)
* NVIDIA Display Driver Version 352.78 or later
  (if you are using an NVIDIA graphics card) 
* AMD Radeon Desktop Video Card Driver
  (if you are using an AMD graphics card)

[1]: https://www.microsoft.com/en-us/download/details.aspx?id=5555

## Building

You need the following tools to build Meriken's Tripcode Engine.

* Visual Studio 2010 Professional
* CUDA Toolkit 7.5
* AMD APP SDK 3.0
* YASM 1.2.0

This program uses Multiple Precision Integers and Rationals (MPIR). Make sure to copy MPIR header and library files into appropriate Visual Studio folders.

See MerikensTripcodeEngine.h for various build options. Don't forget to define ENGLISH_VERSION if you want to build an English version for 4chan.

## License

Meriken's Tripcode Engine is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Meriken's Tripcode Engine is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Meriken's Tripcode Engine.  If not, see <http://www.gnu.org/licenses/>.

Copyright © 2016 ◆Meriken.Z.