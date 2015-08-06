// Meriken's Tripcode Engine 2.0.0
// Copyright (c) 2011-2015 Meriken.Z. <meriken.2ch@gmail.com>
//
// The initial versions of this software were based on:
// CUDA SHA-1 Tripper 0.2.1
// Copyright (c) 2009 Horo/.IBXjcg
// 
// The code that deals with DES decryption is partially adopted from:
// John the Ripper password cracker
// Copyright (c) 1996-2002, 2005, 2010 by Solar Designer
//
// The code that deals with SHA-1 hash generation is partially adopted from:
// sha_digest-2.2
// Copyright (C) 2009 Jens Thoms Toerring <jt@toerring.de>
// VecTripper 
// Copyright (C) 2011 tmkk <tmkk@smoug.net>
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.



// TO DO: Use smallKeyBitmap[]!



///////////////////////////////////////////////////////////////////////////////
// INCLUDE FILE(S)                                                           //
///////////////////////////////////////////////////////////////////////////////

#include "MerikensTripcodeEngine.h"



///////////////////////////////////////////////////////////////////////////////
// VARIABLES FOR CUDA CODES                                                  //
///////////////////////////////////////////////////////////////////////////////

__device__ __constant__ unsigned char   CUDA_keyCharTable_OneByte[SIZE_KEY_CHAR_TABLE];
__device__ __constant__ unsigned char   CUDA_keyCharTable_FirstByte  [SIZE_KEY_CHAR_TABLE];
__device__ __constant__ unsigned char   CUDA_keyCharTable_SecondByte [SIZE_KEY_CHAR_TABLE];
__device__ __constant__ char            CUDA_base64CharTable[64];
__device__ __constant__ unsigned char   CUDA_key[12];



///////////////////////////////////////////////////////////////////////////////
// BITSLICE DES                                                              //
///////////////////////////////////////////////////////////////////////////////

#define NUM_THREADS_PER_BITSICE_DES   4

// FOR DEVICE CODES ONLY
#if   __CUDA_ARCH__ == 200
#define CUDA_DES_NUM_THREADS_PER_BLOCK      768
#elif __CUDA_ARCH__ == 300
#define CUDA_DES_NUM_THREADS_PER_BLOCK      768
#elif __CUDA_ARCH__ == 320
#define CUDA_DES_NUM_THREADS_PER_BLOCK      768
#elif __CUDA_ARCH__ == 350
#define CUDA_DES_NUM_THREADS_PER_BLOCK      768
#elif __CUDA_ARCH__ == 370
#define CUDA_DES_NUM_THREADS_PER_BLOCK      448
#elif __CUDA_ARCH__ == 500
#define CUDA_DES_NUM_THREADS_PER_BLOCK      512
#elif __CUDA_ARCH__ == 520
#define CUDA_DES_NUM_THREADS_PER_BLOCK      512
#elif __CUDA_ARCH__ == 530
#define CUDA_DES_NUM_THREADS_PER_BLOCK      512
#else
#define CUDA_DES_NUM_THREADS_PER_BLOCK      512 // dummy value to make nvcc happy
#endif
#define CUDA_DES_NUM_BITSLICE_DES_CONTEXTS_PER_BLOCK (CUDA_DES_NUM_THREADS_PER_BLOCK / NUM_THREADS_PER_BITSICE_DES)
#define N CUDA_DES_NUM_BITSLICE_DES_CONTEXTS_PER_BLOCK

#define CUDA_DES_BS_DEPTH                   32
#define CUDA_DES_MAX_PASS_COUNT             10

typedef int           DES_ARCH_WORD;
typedef int           DES_ARCH_WORD_32;
#define DES_ARCH_SIZE 4
#define DES_ARCH_BITS 32

typedef int           DES_Vector;
// #define CUDA_DES_BS_DEPTH  DES_ARCH_BITS
#define DES_VECTOR_ZERO               0
#define DES_VECTOR_ONES               ~(DES_Vector)0

#define DES_VECTOR_NOT(dst, a)        (dst) =  ~(a)
#define DES_VECTOR_AND(dst, a, b)     (dst) =   (a) &  (b)
#define DES_VECTOR_OR(dst, a, b)      (dst) =   (a) |  (b)
#define DES_VECTOR_AND_NOT(dst, a, b) (dst) =   (a) & ~(b)
#define DES_VECTOR_XOR_NOT(dst, a, b) (dst) = ~((a) ^  (b))
#define DES_VECTOR_NOT_OR(dst, a, b)  (dst) = ~((a) |  (b))
#define DES_VECTOR_SEL(dst, a, b, c)  (dst) = (((a) & ~(c)) ^ ((b) & (c)))
#define DES_VECTOR_XOR_FUNC(a, b)              ((a) ^  (b))
#define DES_VECTOR_XOR(dst, a, b)     (dst) = DES_VECTOR_XOR_FUNC((a), (b))
#define DES_VECTOR_SET(dst, ofs, src) *((DES_Vector *)((DES_Vector *)&(dst) + ((ofs) * N))) = (src)

#define DES_CONSTANT_QUALIFIERS      __device__ __constant__
#define DES_FUNCTION_QUALIFIERS      __device__ __forceinline__
#define DES_SBOX_FUNCTION_QUALIFIERS __device__ __forceinline__

extern __shared__ DES_Vector dataBlocks[];

const unsigned char expansionTable[48] = {
	31,  0,  1,  2,  3,  4,
	 3,  4,  5,  6,  7,  8,
	 7,  8,  9, 10, 11, 12,
	11, 12, 13, 14, 15, 16,
	15, 16, 17, 18, 19, 20,
	19, 20, 21, 22, 23, 24,
	23, 24, 25, 26, 27, 28,
	27, 28, 29, 30, 31,  0
};

__device__ __constant__ unsigned char CUDA_smallKeyBitmap[SMALL_KEY_BITMAP_SIZE];
__device__ __constant__ unsigned char CUDA_expansionFunction[96];
__device__ __constant__ unsigned char CUDA_key7Array[CUDA_DES_BS_DEPTH];
__device__ __constant__ DES_Vector    CUDA_keyFrom49To55Array[7];

const char charToIndexTableForDES[0x100] = {
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x00, 0x01,
	0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09,
	0x0a, 0x0b, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12,
	0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a,
	0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20, 0x21, 0x22,
	0x23, 0x24, 0x25, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c,
	0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34,
	0x35, 0x36, 0x37, 0x38, 0x39, 0x3a, 0x3b, 0x3c,
	0x3d, 0x3e, 0x3f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
	0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f, 0x7f,
};

DES_CONSTANT_QUALIFIERS char CUDA_DES_indexToCharTable[64] =
//	"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
{
	/* 00 */ '.', '/',
	/* 02 */ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 
	/* 12 */ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 
	/* 28 */ 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	/* 38 */ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
	/* 54 */ 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 
};

DES_CONSTANT_QUALIFIERS unsigned char keySchedule[DES_SIZE_KEY_SCHEDULE] = {
	12, 46, 33, 52, 48, 20, 34, 55,  5, 13, 18, 40,  4, 32, 26, 27,
	38, 54, 53,  6, 31, 25, 19, 41, 15, 24, 28, 43, 30,  3, 35, 22,
	 2, 44, 14, 23, 51, 16, 29, 49,  7, 17, 37,  8,  9, 50, 42, 21,
	 5, 39, 26, 45, 41, 13, 27, 48, 53,  6, 11, 33, 52, 25, 19, 20,
	31, 47, 46, 54, 55, 18, 12, 34,  8, 17, 21, 36, 23, 49, 28, 15,
	24, 37,  7, 16, 44,  9, 22, 42,  0, 10, 30,  1,  2, 43, 35, 14,
	46, 25, 12, 31, 27, 54, 13, 34, 39, 47, 52, 19, 38, 11,  5,  6,
	48, 33, 32, 40, 41,  4, 53, 20, 51,  3,  7, 22,  9, 35, 14,  1,
	10, 23, 50,  2, 30, 24,  8, 28, 43, 49, 16, 44, 17, 29, 21,  0,
	32, 11, 53, 48, 13, 40, 54, 20, 25, 33, 38,  5, 55, 52, 46, 47,
	34, 19, 18, 26, 27, 45, 39,  6, 37, 42, 50,  8, 24, 21,  0, 44,
	49,  9, 36, 17, 16, 10, 51, 14, 29, 35,  2, 30,  3, 15,  7, 43,
	18, 52, 39, 34, 54, 26, 40,  6, 11, 19, 55, 46, 41, 38, 32, 33,
	20,  5,  4, 12, 13, 31, 25, 47, 23, 28, 36, 51, 10,  7, 43, 30,
	35, 24, 22,  3,  2, 49, 37,  0, 15, 21, 17, 16, 42,  1, 50, 29,
	 4, 38, 25, 20, 40, 12, 26, 47, 52,  5, 41, 32, 27, 55, 18, 19,
	 6, 46, 45, 53, 54, 48, 11, 33,  9, 14, 22, 37, 49, 50, 29, 16,
	21, 10,  8, 42, 17, 35, 23, 43,  1,  7,  3,  2, 28, 44, 36, 15,
	45, 55, 11,  6, 26, 53, 12, 33, 38, 46, 27, 18, 13, 41,  4,  5,
	47, 32, 31, 39, 40, 34, 52, 19, 24,  0,  8, 23, 35, 36, 15,  2,
	 7, 49, 51, 28,  3, 21,  9, 29, 44, 50, 42, 17, 14, 30, 22,  1,
	31, 41, 52, 47, 12, 39, 53, 19, 55, 32, 13,  4, 54, 27, 45, 46,
	33, 18, 48, 25, 26, 20, 38,  5, 10, 43, 51,  9, 21, 22,  1, 17,
	50, 35, 37, 14, 42,  7, 24, 15, 30, 36, 28,  3,  0, 16,  8, 44,
	55, 34, 45, 40,  5, 32, 46, 12, 48, 25,  6, 52, 47, 20, 38, 39,
	26, 11, 41, 18, 19, 13, 31, 53,  3, 36, 44,  2, 14, 15, 51, 10,
	43, 28, 30,  7, 35,  0, 17,  8, 23, 29, 21, 49, 50,  9,  1, 37,
	41, 20, 31, 26, 46, 18, 32, 53, 34, 11, 47, 38, 33,  6, 55, 25,
	12, 52, 27,  4,  5, 54, 48, 39, 42, 22, 30, 17,  0,  1, 37, 49,
	29, 14, 16, 50, 21, 43,  3, 51,  9, 15,  7, 35, 36, 24, 44, 23,
	27,  6, 48, 12, 32,  4, 18, 39, 20, 52, 33, 55, 19, 47, 41, 11,
	53, 38, 13, 45, 46, 40, 34, 25, 28,  8, 16,  3, 43, 44, 23, 35,
	15,  0,  2, 36,  7, 29, 42, 37, 24,  1, 50, 21, 22, 10, 30,  9,
	13, 47, 34, 53, 18, 45,  4, 25,  6, 38, 19, 41,  5, 33, 27, 52,
	39, 55, 54, 31, 32, 26, 20, 11, 14, 51,  2, 42, 29, 30,  9, 21,
	 1, 43, 17, 22, 50, 15, 28, 23, 10, 44, 36,  7,  8, 49, 16, 24,
	54, 33, 20, 39,  4, 31, 45, 11, 47, 55,  5, 27, 46, 19, 13, 38,
	25, 41, 40, 48, 18, 12,  6, 52,  0, 37, 17, 28, 15, 16, 24,  7,
	44, 29,  3,  8, 36,  1, 14,  9, 49, 30, 22, 50, 51, 35,  2, 10,
	40, 19,  6, 25, 45, 48, 31, 52, 33, 41, 46, 13, 32,  5, 54, 55,
	11, 27, 26, 34,  4, 53, 47, 38, 43, 23,  3, 14,  1,  2, 10, 50,
	30, 15, 42, 51, 22, 44,  0, 24, 35, 16,  8, 36, 37, 21, 17, 49,
	26,  5, 47, 11, 31, 34, 48, 38, 19, 27, 32, 54, 18, 46, 40, 41,
	52, 13, 12, 20, 45, 39, 33, 55, 29,  9, 42,  0, 44, 17, 49, 36,
	16,  1, 28, 37,  8, 30, 43, 10, 21,  2, 51, 22, 23,  7,  3, 35,
	19, 53, 40,  4, 55, 27, 41, 31, 12, 20, 25, 47, 11, 39, 33, 34,
	45,  6,  5, 13, 38, 32, 26, 48, 22,  2, 35, 50, 37, 10, 42, 29,
	 9, 51, 21, 30,  1, 23, 36,  3, 14, 24, 44, 15, 16,  0, 49, 28,
};

void DES_CreateExpansionFunction(char *saltString, unsigned char *expansionFunction)
{
	unsigned char saltChar1 = '.', saltChar2 = '.';
	DES_ARCH_WORD salt;
	DES_ARCH_WORD mask;
	int src, dst;

	if (saltString[0]) {
		saltChar1 = saltString[0];
		if (saltString[1])
			saltChar2 = saltString[1];
	}
	salt =    charToIndexTableForDES[saltChar1]
	       | (charToIndexTableForDES[saltChar2] << 6);

	mask = 1;
	for (dst = 0; dst < 48; dst++) {
		if (dst == 24) mask = 1;

		if (salt & mask) {
			if (dst < 24) src = dst + 24; else src = dst - 24;
		} else src = dst;

		expansionFunction[dst     ] = expansionTable[src];
		expansionFunction[dst + 48] = expansionTable[src] + 32;

		mask <<= 1;
	}
}

#if __CUDA_ARCH__ < 500

// Bitslice DES S-boxes for x86 with MMX/SSE2/AVX and for typical RISC
// architectures.  These use AND, OR, XOR, NOT, and AND-NOT gates.
//
// Gate counts: 49 44 46 33 48 46 46 41
// Average: 44.125
//
// Several same-gate-count expressions for each S-box are included (for use on
// different CPUs/GPUs).
//
// These Boolean expressions corresponding to DES S-boxes have been generated
// by Roman Rusakov <roman_rus at openwall.com> for use in Openwall's
// John the Ripper password cracker: http://www.openwall.com/john/
// Being mathematical formulas, they are not copyrighted and are free for reuse
// by anyone.
//
// This file (a specific representation of the S-box expressions, surrounding
// logic) is Copyright (c) 2011 by Solar Designer <solar at openwall.com>.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted.  (This is a heavily cut-down "BSD license".)
//
// The effort has been sponsored by Rapid7: http://www.rapid7.com

//
// s1-00484, 49 gates, 17 regs, 11 andn, 4/9/39/79/120 stalls, 74 biop
// Currently used for MMX/SSE2 and x86-64 SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s1(
	DES_Vector arg1,
	DES_Vector arg2,
	DES_Vector arg3,
	DES_Vector arg4,
	DES_Vector arg5,
	DES_Vector arg6,
    DES_Vector *out1,
    DES_Vector *out2,
    DES_Vector *out3,
    DES_Vector *out4
) {
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    ".reg .u32 t10;         \n\t"
	    ".reg .u32 t11;         \n\t"
	    ".reg .u32 t12;         \n\t"
	    ".reg .u32 t13;         \n\t"
	    
	    "not.b32 t0,  %8;      \n\t"
	    "and.b32 t0,  %4, t0;  \n\t"
	    "xor.b32 t1,  %7, t0;  \n\t"
	    "or.b32  t2,  %6, %9; \n\t"
	    "xor.b32 t3,  %4, %6; \n\t"
	    "and.b32 t4,  t2,  t3;  \n\t"
	    "xor.b32 t5,  %7, t4;  \n\t"
	    "not.b32 t6,  t1;       \n\t"
	    "and.b32 t6,  t5,  t6;  \n\t"

	    "xor.b32 t7,  %8, %9; \n\t"
	    "xor.b32 t8,  %6, t7;  \n\t"
	    "not.b32 t9,  t8;       \n\t"
	    "and.b32 t9,  t1,  t9;  \n\t"
	    "or.b32  t8,  %9, t4;  \n\t"
	    "xor.b32 t4,  t9,  t8;  \n\t"
	    "not.b32 t8,  t6;       \n\t"
	    "and.b32 t8,  t4,  t8;  \n\t"

	    "or.b32  t9,  %4, %9; \n\t"
	    "or.b32  t10, t4,  t9;  \n\t"
	    "not.b32 t11, t5;       \n\t"
	    "and.b32 t11, %8, t11; \n\t"
	    "xor.b32 t5,  t10, t11; \n\t"

	    "not.b32 t12, t9;       \n\t"
		"and.b32 t12, %7, t12; \n\t"
	    "xor.b32 t9,  t11, t12; \n\t"
	    "not.b32 t12, t3;       \n\t"
	    "and.b32 t12, t7,  t12; \n\t"
	    "or.b32  t3,  t9,  t12; \n\t"

	    "not.b32 t12, t0;       \n\t"
	    "and.b32 t12, %6, t12; \n\t"
	    "xor.b32 t0,  t1,  t10; \n\t"
	    "not.b32 t9,  t12;      \n\t"
	    "and.b32 t9,  t0,  t9;  \n\t"
	    "not.b32 t12, t9;       \n\t"
	    "and.b32 t0,  t2,  t4;  \n\t"
	    "xor.b32 t4,  t12, t0;  \n\t"
	    "not.b32 t13, %5;      \n\t"
	    "and.b32 t13, t5,  t13; \n\t"
	    "xor.b32 t5,  t13, t4;  \n\t"
	    "xor.b32 %2, %2, t5;  \n\t"
	
	    "xor.b32 t12, t7,  t9;  \n\t"
	    "or.b32  t0,  t11, t12; \n\t"
	    "xor.b32 t5,  t2,  t0;  \n\t"
	    "xor.b32 t11, %4, t5;  \n\t"
	    "xor.b32 t5,  t4,  t11; \n\t"
	    "or.b32  t9,  t6,  %5; \n\t"
	    "xor.b32 t12, t9,  t5;  \n\t"
	    "xor.b32 %0, %0, t12; \n\t"
	
	    "xor.b32 t13, t2,  t10; \n\t"
	    "or.b32  t0,  t3,  t13; \n\t"
	    "xor.b32 t13, t11, t0;  \n\t"
	    "or.b32  t0,  t7,  t5;  \n\t"
	    "xor.b32 t5,  t13, t0;  \n\t"
	    "or.b32  t0,  t8,  %5; \n\t"
	    "xor.b32 t6,  t0,  t5;  \n\t"
	    "xor.b32 %1, %1, t6;  \n\t"

	    "or.b32  t6,  %8, t1;  \n\t"
	    "not.b32 t9,  t13;      \n\t"
	    "and.b32 t9,  t6,  t9;  \n\t"
	    "and.b32 t13, t8,  t11; \n\t"
	    "xor.b32 t11, t9,  t13; \n\t"
	    "or.b32  t13, t11, %5; \n\t"
	    "xor.b32 t12, t13, t3;  \n\t"
	    "xor.b32 %3, %3, t12;   \n\t"
	    "}                      \n\t"

	    : "+r"(*out1),  // %0
	      "+r"(*out2),  // %1
	      "+r"(*out3),  // %2
	      "+r"(*out4)   // %3
	      
	    : "r"(arg1)     // %4
	      "r"(arg2)     // %5
	      "r"(arg3)     // %6
	      "r"(arg4)     // %7
	      "r"(arg5)     // %8
	      "r"(arg6));   // %9
}

//
// s2-016251, 44 gates, 14 regs, 13 andn, 1/9/22/61/108 stalls, 66 biop */
//
DES_SBOX_FUNCTION_QUALIFIERS void
s2(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    ".reg .u32 t10;         \n\t"
	    ".reg .u32 t11;         \n\t"
	    ".reg .u32 t12;         \n\t"

		"xor.b32 t0, %5, %8;    \n\t"

		"not.b32 t1, %9;        \n\t"
		"and.b32 t1, %4, t1;    \n\t"
		"not.b32 t2, t1;        \n\t"
		"and.b32 t2, %8, t2;    \n\t"
		"or.b32  t1, %5, t2;    \n\t"

		"not.b32 t3, %9;        \n\t"
		"and.b32 t3, t0, t3;    \n\t"
		"and.b32 t4, %4, t0;    \n\t"
		"xor.b32 t5, %8, t4;    \n\t"
		"not.b32 t6, t3;        \n\t"
		"and.b32 t6, t5, t6;    \n\t"

		"and.b32 t7, %6, %9;    \n\t"
		"xor.b32 t8, t2, t3;    \n\t"
		"and.b32 t2, t1, t8;    \n\t"
		"not.b32 t3, t7;        \n\t"
		"and.b32 t3, t2, t3;    \n\t"

		"and.b32 t8, %6, t2;    \n\t"
		"not.b32 t2, %4;        \n\t"
		"xor.b32 t9, t8, t2;    \n\t"
		"xor.b32 t2, %9, t0;    \n\t"
		"not.b32 t0, t7;        \n\t"
		"and.b32 t0, t2, t0;    \n\t"
		"xor.b32 t10, t9, t0;   \n\t"
		"not.b32 t11, t3;       \n\t"
		"and.b32 t11, %7, t11;  \n\t"
		"xor.b32 t3, t11, t10;  \n\t"
		"xor.b32 %1, %1, t3;    \n\t"

		"not.b32 t3, t0;        \n\t"
		"and.b32 t3, %5, t3;    \n\t"
		"xor.b32 t0, t5, t3;    \n\t"
		"not.b32 t5, t0;        \n\t"
		"and.b32 t5, t9, t5;    \n\t"
		"xor.b32 t9, %6, t2;    \n\t"
		"xor.b32 t11, t5, t9;   \n\t"
		"not.b32 t5, %7;        \n\t"
		"and.b32 t5, t1, t5;    \n\t"
		"xor.b32 t12, t5, t11;  \n\t"
		"xor.b32 %0, %0, t12;   \n\t"

		"xor.b32 t5, t8, t3;    \n\t"
		"or.b32  t3, t9, t5;    \n\t"
		"xor.b32 t8, t1, t10;   \n\t"
		"or.b32  t1, t7, t8;    \n\t"
		"xor.b32 t7, t3, t1;    \n\t"

		"not.b32 t1, t11;       \n\t"
		"and.b32 t1, t10, t1;   \n\t"
		"xor.b32 t3, t4, t5;    \n\t"
		"or.b32  t4, t1, t3;    \n\t"
		"not.b32 t1, t9;        \n\t"
		"and.b32 t1, t6, t1;    \n\t"
		"xor.b32 t3, t4, t1;    \n\t"
		"or.b32  t1, t3, %7;    \n\t"
		"xor.b32 t4, t1, t7;    \n\t"
		"xor.b32 %2, %2, t4;    \n\t"

		"not.b32 t1, t0;        \n\t"
		"and.b32 t1, t3, t1;    \n\t"
		"or.b32  t0, t2, t8;    \n\t"
		"xor.b32 t2, t1, t0;    \n\t"
		"or.b32  t0, t6, %7;    \n\t"
		"xor.b32 t1, t0, t2;    \n\t"
		"xor.b32 %3, %3, t1;    \n\t"
		
		"}                      \n\t"

	    : "+r"(*out1), // %0
	      "+r"(*out2), // %1
	      "+r"(*out3), // %2
	      "+r"(*out4)  // %3
	      
	    : "r"(a1)      // %4
	      "r"(a2)      // %5
	      "r"(a3)      // %6
	      "r"(a4)      // %7
	      "r"(a5)      // %8
	      "r"(a6));    // %9
}

//
// s3-000426, 46 gates, 16 regs, 14 andn, 2/5/12/35/75 stalls, 68 biop
// Currently used for x86-64 SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s3(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    ".reg .u32 t10;         \n\t"

		"not.b32 t0, %5;        \n\t"
		"and.b32 t0, %4, t0;    \n\t"
		"xor.b32 t1, %6, %9;    \n\t"
		"or.b32  t2, t0, t1;    \n\t"
		"xor.b32 t0, %7, %9;    \n\t"
		"not.b32 t3, %4;        \n\t"
		"and.b32 t3, t0, t3;    \n\t"
		"xor.b32 t4, t2, t3;    \n\t"

		"xor.b32 t5, %5, t1;    \n\t"
		"not.b32 t6, %9;        \n\t"
		"and.b32 t6, t5, t6;    \n\t"
		"xor.b32 t7, t2, t6;    \n\t"
		"not.b32 t2, t7;        \n\t"
		"and.b32 t2, t4, t2;    \n\t"

		"and.b32 t6, %9, t4;    \n\t"
		"or.b32  t8, %7, t6;    \n\t"
		"and.b32 t6, %4, t8;    \n\t"
		"xor.b32 t8, t5, t6;    \n\t"
		"not.b32 t6, %8;        \n\t"
		"and.b32 t6, t4, t6;    \n\t"
		"xor.b32 t9, t6, t8;    \n\t"
		"xor.b32 %3, %3, t9;    \n\t"

		"and.b32 t6, t1, t0;    \n\t"
		"xor.b32 t0, %4, %7;    \n\t"
		"xor.b32 t9, t7, t0;    \n\t"
		"or.b32  t7, %6, t9;    \n\t"
		"not.b32 t9, t6;        \n\t"
		"and.b32 t9, t7, t9;    \n\t"

		"or.b32  t6, t3, t0;    \n\t"
		"not.b32 t0, t6;        \n\t"
		"and.b32 t0, t8, t0;    \n\t"
		"and.b32 t7, %7, %9;    \n\t"
		"not.b32 t8, %5;        \n\t"
		"and.b32 t8, t7, t8;    \n\t"
		"xor.b32 t10, t0, t8;   \n\t"

		"not.b32 t0, %6;        \n\t"
		"and.b32 t0, t10, t0;   \n\t"
		"or.b32  t8, t5, t7;    \n\t"
		"not.b32 t7, t0;        \n\t"
		"and.b32 t7, t8, t7;    \n\t"
		"xor.b32 t0, %4, t7;    \n\t"
		"and.b32 t7, t9, %8;    \n\t"
		"xor.b32 t8, t7, t0;    \n\t"
		"xor.b32 %1, %1, t8;    \n\t"

		"not.b32 t0, %5;        \n\t"
		"and.b32 t0, t4, t0;    \n\t"
		"not.b32 t4, %6;        \n\t"
		"and.b32 t4, t0, t4;    \n\t"
		"xor.b32 t7, t5, t6;    \n\t"
		"not.b32 t6, t7;        \n\t"
		"xor.b32 t7, t4, t6;    \n\t"
		"not.b32 t4, t2;        \n\t"
		"and.b32 t4, %8, t4;    \n\t"
		"xor.b32 t2, t4, t7;    \n\t"
		"xor.b32 %0, %0, t2;    \n\t"

		"and.b32 t2, %7, t1;    \n\t"
		"or.b32  t1, t5, t7;    \n\t"
		"not.b32 t4, t2;        \n\t"
		"and.b32 t4, t1, t4;    \n\t"
		"or.b32  t1, t3, t0;    \n\t"
		"xor.b32 t0, t4, t1;    \n\t"
		"or.b32  t1, t10, %8;   \n\t"
		"xor.b32 t2, t1, t0;    \n\t"
		"xor.b32 %2, %2, t2;    \n\t"
		
		"}                      \n\t"

	    : "+r"(*out1), // %0
	      "+r"(*out2), // %1
	      "+r"(*out3), // %2
	      "+r"(*out4)  // %3
	      
	    : "r"(a1)      // %4
	      "r"(a2)      // %5
	      "r"(a3)      // %6
	      "r"(a4)      // %7
	      "r"(a5)      // %8
	      "r"(a6));    // %9
}

//
// s4, 33 gates, 11/12 regs, 9 andn, 2/21/53/86/119 stalls, 52 biop
//
DES_SBOX_FUNCTION_QUALIFIERS void
s4(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"

	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	
		"xor.b32 t0, %4, %6;    \n\t"
		"xor.b32 t1, %6, %8;    \n\t"
		"or.b32  t2, %5, %7;    \n\t"
		"xor.b32 t3, %8, t2;    \n\t"
		"not.b32 t2, t3;        \n\t"
		"and.b32 t2, t1, t2;    \n\t"
		"not.b32 t3, %5;        \n\t"
		"and.b32 t3, t1, t3;    \n\t"
		"xor.b32 t4, %7, t3;    \n\t"
		"or.b32  t5, t0, t4;    \n\t"
		"not.b32 t6, t2;        \n\t"
		"and.b32 t6, t5, t6;    \n\t"
		"xor.b32 t5, %5, t6;    \n\t"

		"and.b32 t7, t4, t5;    \n\t"
		"not.b32 t4, t7;        \n\t"
		"and.b32 t4, t1, t4;    \n\t"
		"xor.b32 t1, t0, t5;    \n\t"
		"not.b32 t0, t4;        \n\t"
		"and.b32 t0, t1, t0;    \n\t"
		"xor.b32 t4, t2, t0;    \n\t"

		"xor.b32 t0, %5, %7;    \n\t"
		"or.b32  t2, %8, t3;    \n\t"
		"xor.b32 t3, t1, t2;    \n\t"
		"not.b32 t1, t0;        \n\t"
		"and.b32 t1, t3, t1;    \n\t"
		"xor.b32 t2, t6, t1;    \n\t"
		"not.b32 t1, t4;        \n\t"
		"and.b32 t1, %9, t1;    \n\t"
		"xor.b32 t6, t1, t2;    \n\t"
		"xor.b32 %0, %0, t6;    \n\t"

		"not.b32 t1, t2;        \n\t"
		"not.b32 t2, %9;        \n\t"
		"and.b32 t2, t4, t2;    \n\t"
		"xor.b32 t6, t2, t1;    \n\t"
		"xor.b32 %1, %1, t6;    \n\t"

		"xor.b32 t2, t4, t1;    \n\t"
		"not.b32 t1, t0;        \n\t"
		"and.b32 t1, t2, t1;    \n\t"
		"or.b32  t0, t7, t1;    \n\t"
		"xor.b32 t1, t3, t0;    \n\t"
		"or.b32  t0, t5, %9;    \n\t"
		"xor.b32 t2, t0, t1;    \n\t"
		"xor.b32 %2, %2, t2;    \n\t"

		"and.b32 t0, %9, t5;    \n\t"
		"xor.b32 t2, t0, t1;    \n\t"
		"xor.b32 %3, %3, t2;    \n\t"
		
		"}                      \n\t"

	    : "+r"(*out1), // %0
	      "+r"(*out2), // %1
	      "+r"(*out3), // %2
	      "+r"(*out4)  // %3
	      
	    : "r"(a1)      // %4
	      "r"(a2)      // %5
	      "r"(a3)      // %6
	      "r"(a4)      // %7
	      "r"(a5)      // %8
	      "r"(a6));    // %9
}

//
// s5-04832, 48 gates, 15/16 regs, 9 andn, 5/23/62/109/159 stalls, 72 biop
// Currently used for MMX/SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s5(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"

	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    ".reg .u32 t10;          \n\t"
	    ".reg .u32 t11;          \n\t"
	    ".reg .u32 t12;          \n\t"
	
		"or.b32 t1, %4, %6; \n\t"
		"not.b32 t10, %9; \n\t"
		"and.b32 t10, t1, t10; \n\t"
		"xor.b32 t6, %4, t10; \n\t"
		"xor.b32 t2, %6, t6; \n\t"
		"or.b32 t3, %7, t2; \n\t"
		"not.b32 t7, %7; \n\t"
		"and.b32 t7, t10, t7; \n\t"
		"xor.b32 t10, %6, t7; \n\t"
		"and.b32 t7, %8, t10; \n\t"
		"or.b32 t12, %4, t2; \n\t"
		"xor.b32 t2, t7, t12; \n\t"
		"xor.b32 t7, %7, t2; \n\t"
		"xor.b32 t2, %9, t7; \n\t"
		"or.b32 t4, t6, t2; \n\t"
		"and.b32 t8, %8, t4; \n\t"
		"xor.b32 t11, t6, t8; \n\t"
		"and.b32 t9, %7, t12; \n\t"
		"xor.b32 t5, t11, t9; \n\t"
		"not.b32 t11, %4; \n\t"
		"and.b32 t11, t4, t11; \n\t"
		"xor.b32 t4, t10, t11; \n\t"
		"xor.b32 t9, %8, t3; \n\t"
		"not.b32 t0, t4; \n\t"
		"and.b32 t0, t9, t0; \n\t"
		"not.b32 t4, t0; \n\t"
		"not.b32 t0, %5; \n\t"
		"and.b32 t0, t4, t0; \n\t"
		"xor.b32 t4, t0, t7; \n\t"
		"xor.b32 %2, %2, t4; \n\t"
		"not.b32 t7, t8; \n\t"
		"and.b32 t7, t10, t7; \n\t"
		"xor.b32 t0, t11, t9; \n\t"
		"or.b32 t11, t5, t0; \n\t"
		"not.b32 t4, t7; \n\t"
		"and.b32 t4, t11, t4; \n\t"
		"not.b32 t0, t4; \n\t"
		"and.b32 t0, t3, t0; \n\t"
		"and.b32 t11, t2, t4; \n\t"
		"xor.b32 t7, t9, t11; \n\t"
		"and.b32 t2, t10, t12; \n\t"
		"or.b32 t11, t7, t2; \n\t"
		"xor.b32 t9, t8, t11; \n\t"
		"and.b32 t11, t9, %5; \n\t"
		"xor.b32 t12, t11, t5; \n\t"
		"xor.b32 %3, %3, t12; \n\t"
		"xor.b32 t12, t1, t4; \n\t"
		"xor.b32 t2, %4, t12; \n\t"
		"and.b32 t11, %7, t7; \n\t"
		"xor.b32 t8, t2, t11; \n\t"
		"or.b32 t12, t0, %5; \n\t"
		"xor.b32 t11, t12, t8; \n\t"
		"xor.b32 %0, %0, t11; \n\t"
		"xor.b32 t9, t3, t10; \n\t"
		"not.b32 t5, t8; \n\t"
		"and.b32 t5, t9, t5; \n\t"
		"xor.b32 t4, t6, t7; \n\t"
		"xor.b32 t1, t5, t4; \n\t"
		"and.b32 t2, t3, %5; \n\t"
		"xor.b32 t0, t2, t1; \n\t"
		"xor.b32 %1, %1, t0; \n\t"

		"}                      \n\t"

	    : "+r"(*out1), // %0
	      "+r"(*out2), // %1
	      "+r"(*out3), // %2
	      "+r"(*out4)  // %3
	      
	    : "r"(a1)      // %4
	      "r"(a2)      // %5
	      "r"(a3)      // %6
	      "r"(a4)      // %7
	      "r"(a5)      // %8
	      "r"(a6));    // %9
}

//
// s6-000007, 46 gates, 19 regs, 8 andn, 3/19/39/66/101 stalls, 69 biop
// Currently used for x86-64 SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s6(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    ".reg .u32 t10;         \n\t"
	    ".reg .u32 t11;         \n\t"
	    ".reg .u32 t12;         \n\t"
	    ".reg .u32 t13;         \n\t"
	    
		"xor.b32 t0, %5, %8; \n\t"

		"or.b32 t8, %5, %9; \n\t"
		"and.b32 t1, %4, t8; \n\t"
		"xor.b32 t8, t0, t1; \n\t"
		"xor.b32 t0, %9, t8; \n\t"
		"not.b32 t12, t0; \n\t"
		"and.b32 t12, %8, t12; \n\t"

		"and.b32 t11, %4, t0; \n\t"
		"xor.b32 t0, %5, t11; \n\t"
		"xor.b32 t4, %4, %6; \n\t"
		"or.b32 t13, t0, t4; \n\t"
		"xor.b32 t2, t8, t13; \n\t"

		"and.b32 t7, %6, t2; \n\t"
		"not.b32 t6, %9; \n\t"
		"and.b32 t6, t7, t6; \n\t"
		"or.b32 t9, t12, t0; \n\t"
		"xor.b32 t0, t6, t9; \n\t"
		"and.b32 t10, t0, %7; \n\t"
		"xor.b32 t5, t10, t2; \n\t"
		"xor.b32 %3, %3, t5; \n\t"

		"xor.b32 t5, %5, t13; \n\t"
		"not.b32 t13, t5; \n\t"
		"and.b32 t13, %9, t13; \n\t"
		"xor.b32 t10, %6, t13; \n\t"
		"not.b32 t13, t7; \n\t"
		"and.b32 t13, %8, t13; \n\t"
		"or.b32 t3, t10, t13; \n\t"

		"or.b32 t13, %4, t2; \n\t"
		"and.b32 t2, t9, t13; \n\t"
		"xor.b32 t9, t10, t2; \n\t"
		"not.b32 t13, t6; \n\t"
		"and.b32 t13, t9, t13; \n\t"
		"or.b32 t6, t12, %7; \n\t"
		"xor.b32 t12, t6, t13; \n\t"
		"xor.b32 %2, %2, t12; \n\t"

		"or.b32 t2, %5, t4; \n\t"
		"xor.b32 t6, t0, t2; \n\t"
		"or.b32 t12, t1, t3; \n\t"
		"xor.b32 t13, t6, t12; \n\t"

		"xor.b32 t4, t8, t9; \n\t"
		"not.b32 t0, t4; \n\t"
		"and.b32 t0, %8, t0; \n\t"
		"not.b32 t1, t5; \n\t"
		"xor.b32 t6, t2, t1; \n\t"
		"xor.b32 t12, t0, t6; \n\t"
		"not.b32 t9, %7; \n\t"
		"and.b32 t9, t12, t9; \n\t"
		"xor.b32 t12, t9, t13; \n\t"
		"xor.b32 %1, %1, t12; \n\t"

		"xor.b32 t9, %9, t11; \n\t"
		"xor.b32 t8, %4, t10; \n\t"
		"and.b32 t4, t9, t8; \n\t"
		"xor.b32 t5, t7, t6; \n\t"
		"xor.b32 t2, t4, t5; \n\t"
		"not.b32 t1, %7; \n\t"
		"and.b32 t1, t3, t1; \n\t"
		"xor.b32 t0, t1, t2; \n\t"
		"xor.b32 %0, %0, t0; \n\t"

	    "}                      \n\t"

	    : "+r"(*out1),  // %0
	      "+r"(*out2),  // %1
	      "+r"(*out3),  // %2
	      "+r"(*out4)   // %3
	      
	    : "r"(a1)     // %4
	      "r"(a2)     // %5
	      "r"(a3)     // %6
	      "r"(a4)     // %7
	      "r"(a5)     // %8
	      "r"(a6));   // %9
}

//
// s7-056945, 46 gates, 16 regs, 7 andn, 10/31/62/107/156 stalls, 67 biop
// Currently used for MMX/SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s7(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    
		"xor.b32 t6, %7, %8; \n\t"
		"xor.b32 t3, %6, t6; \n\t"
		"and.b32 t1, %9, t3; \n\t"
		"and.b32 t2, %7, t6; \n\t"
		"xor.b32 t4, %5, t2; \n\t"
		"and.b32 t0, t1, t4; \n\t"

		"and.b32 t7, %9, t2; \n\t"
		"xor.b32 t5, %6, t7; \n\t"
		"or.b32 t7, t4, t5; \n\t"
		"xor.b32 t8, %9, t6; \n\t"
		"xor.b32 t6, t7, t8; \n\t"
		"not.b32 t7, t0; \n\t"
		"and.b32 t7, %4, t7; \n\t"
		"xor.b32 t9, t7, t6; \n\t"
		"xor.b32 %3, %3, t9; \n\t"

		"not.b32 t7, t3; \n\t"
		"and.b32 t7, %8, t7; \n\t"
		"or.b32 t0, t4, t7; \n\t"
		"xor.b32 t9, t1, t5; \n\t"
		"xor.b32 t5, t0, t9; \n\t"

		"xor.b32 t0, t1, t8; \n\t"
		"not.b32 t1, t0; \n\t"
		"and.b32 t1, %7, t1; \n\t"
		"not.b32 t0, t1; \n\t"
		"and.b32 t0, t4, t0; \n\t"
		"xor.b32 t4, %8, t9; \n\t"
		"xor.b32 t1, t0, t4; \n\t"

		"or.b32 t9, t2, t6; \n\t"
		"and.b32 t0, %6, t1; \n\t"
		"or.b32 t4, t9, t0; \n\t"
		"not.b32 t2, t8; \n\t"
		"and.b32 t2, t3, t2; \n\t"
		"xor.b32 t6, t4, t2; \n\t"
		"not.b32 t8, %4; \n\t"
		"and.b32 t8, t6, t8; \n\t"
		"xor.b32 t9, t8, t5; \n\t"
		"xor.b32 %0, %0, t9; \n\t"

		"or.b32 t9, t1, t6; \n\t"
		"and.b32 t8, %9, t9; \n\t"
		"and.b32 t3, %5, t8; \n\t"
		"xor.b32 t4, t5, t6; \n\t"
		"xor.b32 t2, t3, t4; \n\t"

		"or.b32 t9, t0, t2; \n\t"
		"xor.b32 t5, t8, t9; \n\t"
		"xor.b32 t3, %8, t4; \n\t"
		"or.b32 t0, t5, t3; \n\t"
		"and.b32 t9, t0, %4; \n\t"
		"xor.b32 t5, t9, t1; \n\t"
		"xor.b32 %2, %2, t5; \n\t"

		"xor.b32 t9, t8, t0; \n\t"
		"or.b32 t4, t7, t9; \n\t"
		"not.b32 t5, t6; \n\t"
		"xor.b32 t3, t4, t5; \n\t"
		"not.b32 t1, %4; \n\t"
		"and.b32 t1, t3, t1; \n\t"
		"xor.b32 t0, t1, t2; \n\t"
		"xor.b32 %1, %1, t0; \n\t"


	    "}                      \n\t"

	    : "+r"(*out1),  // %0
	      "+r"(*out2),  // %1
	      "+r"(*out3),  // %2
	      "+r"(*out4)   // %3
	      
	    : "r"(a1)     // %4
	      "r"(a2)     // %5
	      "r"(a3)     // %6
	      "r"(a4)     // %7
	      "r"(a5)     // %8
	      "r"(a6));   // %9
}

//
// s8-004798, 41 gates, 14 regs, 7 andn, 7/35/76/118/160 stalls, 59 biop
// Currently used for MMX/SSE2
//
DES_SBOX_FUNCTION_QUALIFIERS void
s8(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
    DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	asm("{                      \n\t"
	    ".reg .u32 t0;          \n\t"
	    ".reg .u32 t1;          \n\t"
	    ".reg .u32 t2;          \n\t"
	    ".reg .u32 t3;          \n\t"
	    ".reg .u32 t4;          \n\t"
	    ".reg .u32 t5;          \n\t"
	    ".reg .u32 t6;          \n\t"
	    ".reg .u32 t7;          \n\t"
	    ".reg .u32 t8;          \n\t"
	    ".reg .u32 t9;          \n\t"
	    
		"not.b32 t8, %5; \n\t"
		"and.b32 t8, %6, t8; \n\t"
		"not.b32 t1, %6; \n\t"
		"and.b32 t1, %8, t1; \n\t"
		"xor.b32 t6, %7, t1; \n\t"
		"and.b32 t1, %4, t6; \n\t"
		"not.b32 t7, t8; \n\t"
		"and.b32 t7, t1, t7; \n\t"

		"not.b32 t3, t6; \n\t"
		"and.b32 t3, %5, t3; \n\t"
		"or.b32 t9, %4, t3; \n\t"
		"not.b32 t0, %6; \n\t"
		"and.b32 t0, %5, t0; \n\t"
		"xor.b32 t4, %8, t0; \n\t"
		"and.b32 t0, t9, t4; \n\t"
		"or.b32 t2, t1, t0; \n\t"

		"xor.b32 t1, t6, t0; \n\t"
		"not.b32 t0, t1; \n\t"
		"not.b32 t6, t9; \n\t"
		"and.b32 t6, %6, t6; \n\t"
		"xor.b32 t1, t0, t6; \n\t"
		"xor.b32 t9, t8, t1; \n\t"
		"or.b32 t8, t7, %9; \n\t"
		"xor.b32 t6, t8, t9; \n\t"
		"xor.b32 %1, %1, t6; \n\t"

		"xor.b32 t0, %4, t9; \n\t"
		"and.b32 t6, %8, t0; \n\t"
		"xor.b32 t8, %5, t1; \n\t"
		"xor.b32 t9, t6, t8; \n\t"
		"xor.b32 t1, t3, t9; \n\t"

		"or.b32 t6, %7, t8; \n\t"
		"xor.b32 t3, t1, t6; \n\t"
		"xor.b32 t5, t4, t3; \n\t"
		"xor.b32 t8, %4, t5; \n\t"
		"and.b32 t6, t8, %9; \n\t"
		"xor.b32 t4, t6, t1; \n\t"
		"xor.b32 %3, %3, t4; \n\t"

		"xor.b32 t6, t2, t9; \n\t"
		"or.b32 t4, %5, t6; \n\t"
		"xor.b32 t3, t0, t4; \n\t"
		"xor.b32 t8, %8, t3; \n\t"
		"and.b32 t9, t2, %9; \n\t"
		"xor.b32 t6, t9, t8; \n\t"
		"xor.b32 %2, %2, t6; \n\t"

		"or.b32  t9, %7, t0; \n\t"
		"not.b32 t6, t9; \n\t"
		"and.b32 t6, t8, t6; \n\t"
		"or.b32  t4, t7, t6; \n\t"
		"xor.b32 t3, t5, t4; \n\t"
		"or.b32  t2, t3, %9; \n\t"
		"xor.b32 t0, t2, t1; \n\t"
		"xor.b32 %0, %0, t0; \n\t"

	    "}                      \n\t"

	    : "+r"(*out1),  // %0
	      "+r"(*out2),  // %1
	      "+r"(*out3),  // %2
	      "+r"(*out4)   // %3
	      
	    : "r"(a1)     // %4
	      "r"(a2)     // %5
	      "r"(a3)     // %6
	      "r"(a4)     // %7
	      "r"(a5)     // %8
	      "r"(a6));   // %9
}

#else

//
// Bitslice DES S-boxes with LOP3.LUT instructions
// For NVIDIA Maxwell architecture and CUDA 7.5 RC
// by DeepLearningJohnDoe, version 0.1.6, 2015/07/19
//
// Gate counts: 25 24 25 18 25 24 24 23
// Average: 23.5
// Depth: 8 7 7 6 8 10 10 8
// Average: 8
//
// Note that same S-box function with a lower gate count isn't necessarily faster.
//
// These Boolean expressions corresponding to DES S-boxes were
// discovered by <deeplearningjohndoe at gmail.com>
//
// This file itself is Copyright (c) 2015 by <deeplearningjohndoe at gmail.com>
// Redistribution and use in source and binary forms, with or without
// modification, are permitted.
//
// The underlying mathematical formulas are NOT copyrighted.
//

#define LUT(a,b,c,d,e) DES_Vector a; asm("lop3.b32 %0, %1, %2, %3, "#e";" : "=r"(##a): "r"(##b), "r"(##c), "r"(##d));
#define LUT_(a,b,c,d,e) asm("lop3.b32 %0, %1, %2, %3, "#e";" : "=r"(##a): "r"(##b), "r"(##c), "r"(##d));

__device__ __forceinline__ void
s1(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(xAA55AA5500550055, a1, a4, a6, 0xC1)
		LUT(xA55AA55AF0F5F0F5, a3, a6, xAA55AA5500550055, 0x9E)
		LUT(x5F5F5F5FA5A5A5A5, a1, a3, a6, 0xD6)
		LUT(xF5A0F5A0A55AA55A, a4, xAA55AA5500550055, x5F5F5F5FA5A5A5A5, 0x56)
		LUT(x947A947AD1E7D1E7, a2, xA55AA55AF0F5F0F5, xF5A0F5A0A55AA55A, 0x6C)
		LUT(x5FFF5FFFFFFAFFFA, a6, xAA55AA5500550055, x5F5F5F5FA5A5A5A5, 0x7B)
		LUT(xB96CB96C69936993, a2, xF5A0F5A0A55AA55A, x5FFF5FFFFFFAFFFA, 0xD6)
		LUT(x3, a5, x947A947AD1E7D1E7, xB96CB96C69936993, 0x6A)
		LUT(x55EE55EE55EE55EE, a1, a2, a4, 0x7A)
		LUT(x084C084CB77BB77B, a2, a6, xF5A0F5A0A55AA55A, 0xC9)
		LUT(x9C329C32E295E295, x947A947AD1E7D1E7, x55EE55EE55EE55EE, x084C084CB77BB77B, 0x72)
		LUT(xA51EA51E50E050E0, a3, a6, x55EE55EE55EE55EE, 0x29)
		LUT(x4AD34AD3BE3CBE3C, a2, x947A947AD1E7D1E7, xA51EA51E50E050E0, 0x95)
		LUT(x2, a5, x9C329C32E295E295, x4AD34AD3BE3CBE3C, 0xC6)
		LUT(xD955D95595D195D1, a1, a2, x9C329C32E295E295, 0xD2)
		LUT(x8058805811621162, x947A947AD1E7D1E7, x55EE55EE55EE55EE, x084C084CB77BB77B, 0x90)
		LUT(x7D0F7D0FC4B3C4B3, xA51EA51E50E050E0, xD955D95595D195D1, x8058805811621162, 0x76)
		LUT(x0805080500010001, a3, xAA55AA5500550055, xD955D95595D195D1, 0x80)
		LUT(x4A964A96962D962D, xB96CB96C69936993, x4AD34AD3BE3CBE3C, x0805080500010001, 0xA6)
		LUT(x4, a5, x7D0F7D0FC4B3C4B3, x4A964A96962D962D, 0xA6)
		LUT(x148014807B087B08, a1, xAA55AA5500550055, x947A947AD1E7D1E7, 0x21)
		LUT(x94D894D86B686B68, xA55AA55AF0F5F0F5, x8058805811621162, x148014807B087B08, 0x6A)
		LUT(x5555555540044004, a1, a6, x084C084CB77BB77B, 0x70)
		LUT(xAFB4AFB4BF5BBF5B, x5F5F5F5FA5A5A5A5, xA51EA51E50E050E0, x5555555540044004, 0x97)
		LUT(x1, a5, x94D894D86B686B68, xAFB4AFB4BF5BBF5B, 0x6C)

		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s2(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(xEEEEEEEE99999999, a1, a2, a6, 0x97)
		LUT(xFFFFEEEE66666666, a5, a6, xEEEEEEEE99999999, 0x67)
		LUT(x5555FFFFFFFF0000, a1, a5, a6, 0x76)
		LUT(x6666DDDD5555AAAA, a2, xFFFFEEEE66666666, x5555FFFFFFFF0000, 0x69)
		LUT(x6969D3D35353ACAC, a3, xFFFFEEEE66666666, x6666DDDD5555AAAA, 0x6A)
		LUT(xCFCF3030CFCF3030, a2, a3, a5, 0x65)
		LUT(xE4E4EEEE9999F0F0, a3, xEEEEEEEE99999999, x5555FFFFFFFF0000, 0x8D)
		LUT(xE5E5BABACDCDB0B0, a1, xCFCF3030CFCF3030, xE4E4EEEE9999F0F0, 0xCA)
		LUT(x3, a4, x6969D3D35353ACAC, xE5E5BABACDCDB0B0, 0xC6)
		LUT(x3333CCCC00000000, a2, a5, a6, 0x14)
		LUT(xCCCCDDDDFFFF0F0F, a5, xE4E4EEEE9999F0F0, x3333CCCC00000000, 0xB5)
		LUT(x00000101F0F0F0F0, a3, a6, xFFFFEEEE66666666, 0x1C)
		LUT(x9A9A64646A6A9595, a1, xCFCF3030CFCF3030, x00000101F0F0F0F0, 0x96)
		LUT(x2, a4, xCCCCDDDDFFFF0F0F, x9A9A64646A6A9595, 0x6A)
		LUT(x3333BBBB3333FFFF, a1, a2, x6666DDDD5555AAAA, 0xDE)
		LUT(x1414141441410000, a1, a3, xE4E4EEEE9999F0F0, 0x90)
		LUT(x7F7FF3F3F5F53939, x6969D3D35353ACAC, x9A9A64646A6A9595, x3333BBBB3333FFFF, 0x79)
		LUT(x9494E3E34B4B3939, a5, x1414141441410000, x7F7FF3F3F5F53939, 0x29)
		LUT(x1, a4, x3333BBBB3333FFFF, x9494E3E34B4B3939, 0xA6)
		LUT(xB1B1BBBBCCCCA5A5, a1, a1, xE4E4EEEE9999F0F0, 0x4A)
		LUT(xFFFFECECEEEEDDDD, a2, x3333CCCC00000000, x9A9A64646A6A9595, 0xEF)
		LUT(xB1B1A9A9DCDC8787, xE5E5BABACDCDB0B0, xB1B1BBBBCCCCA5A5, xFFFFECECEEEEDDDD, 0x8D)
		LUT(xFFFFCCCCEEEE4444, a2, a5, xFFFFEEEE66666666, 0x2B)
		LUT(x4, a4, xB1B1A9A9DCDC8787, xFFFFCCCCEEEE4444, 0x6C)

		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s3(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(xA50FA50FA50FA50F, a1, a3, a4, 0xC9)
		LUT(xF0F00F0FF0F0F0F0, a3, a5, a6, 0x4B)
		LUT(xAF0FA0AAAF0FAF0F, a1, xA50FA50FA50FA50F, xF0F00F0FF0F0F0F0, 0x4D)
		LUT(x5AA5A55A5AA55AA5, a1, a4, xF0F00F0FF0F0F0F0, 0x69)
		LUT(xAA005FFFAA005FFF, a3, a5, xA50FA50FA50FA50F, 0xD6)
		LUT(x5AA5A55A0F5AFAA5, a6, x5AA5A55A5AA55AA5, xAA005FFFAA005FFF, 0x9C)
		LUT(x1, a2, xAF0FA0AAAF0FAF0F, x5AA5A55A0F5AFAA5, 0xA6)
		LUT(xAA55AA5500AA00AA, a1, a4, a6, 0x49)
		LUT(xFAFAA50FFAFAA50F, a1, a5, xA50FA50FA50FA50F, 0x9B)
		LUT(x50AF0F5AFA50A5A5, a1, xAA55AA5500AA00AA, xFAFAA50FFAFAA50F, 0x66)
		LUT(xAFAFAFAFFAFAFAFA, a1, a3, a6, 0x6F)
		LUT(xAFAFFFFFFFFAFAFF, a4, x50AF0F5AFA50A5A5, xAFAFAFAFFAFAFAFA, 0xEB)
		LUT(x4, a2, x50AF0F5AFA50A5A5, xAFAFFFFFFFFAFAFF, 0x6C)
		LUT(x500F500F500F500F, a1, a3, a4, 0x98)
		LUT(xF0505A0505A5050F, x5AA5A55A0F5AFAA5, xAA55AA5500AA00AA, xAFAFAFAFFAFAFAFA, 0x1D)
		LUT(xF0505A05AA55AAFF, a6, x500F500F500F500F, xF0505A0505A5050F, 0x9A)
		LUT(xFF005F55FF005F55, a1, a4, xAA005FFFAA005FFF, 0xB2)
		LUT(xA55F5AF0A55F5AF0, a5, xA50FA50FA50FA50F, x5AA5A55A5AA55AA5, 0x3D)
		LUT(x5A5F05A5A55F5AF0, a6, xFF005F55FF005F55, xA55F5AF0A55F5AF0, 0xA6)
		LUT(x3, a2, xF0505A05AA55AAFF, x5A5F05A5A55F5AF0, 0xA6)
		LUT(x0F0F0F0FA5A5A5A5, a1, a3, a6, 0xC6)
		LUT(x5FFFFF5FFFA0FFA0, x5AA5A55A5AA55AA5, xAFAFAFAFFAFAFAFA, x0F0F0F0FA5A5A5A5, 0xDB)
		LUT(xF5555AF500A05FFF, a5, xFAFAA50FFAFAA50F, xF0505A0505A5050F, 0xB9)
		LUT(x05A5AAF55AFA55A5, xF0505A05AA55AAFF, x0F0F0F0FA5A5A5A5, xF5555AF500A05FFF, 0x9B)
		LUT(x2, a2, x5FFFFF5FFFA0FFA0, x05A5AAF55AFA55A5, 0xA6)

		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s4(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(x55F055F055F055F0, a1, a3, a4, 0x72)
		LUT(xA500F5F0A500F5F0, a3, a5, x55F055F055F055F0, 0xAD)
		LUT(xF50AF50AF50AF50A, a1, a3, a4, 0x59)
		LUT(xF5FA0FFFF5FA0FFF, a3, a5, xF50AF50AF50AF50A, 0xE7)
		LUT(x61C8F93C61C8F93C, a2, xA500F5F0A500F5F0, xF5FA0FFFF5FA0FFF, 0xC6)
		LUT(x9999666699996666, a1, a2, a5, 0x69)
		LUT(x22C022C022C022C0, a2, a4, x55F055F055F055F0, 0x18)
		LUT(xB35C94A6B35C94A6, xF5FA0FFFF5FA0FFF, x9999666699996666, x22C022C022C022C0, 0x63)
		LUT(x4, a6, x61C8F93C61C8F93C, xB35C94A6B35C94A6, 0x6A)
		LUT(x4848484848484848, a1, a2, a3, 0x12)
		LUT(x55500AAA55500AAA, a1, a5, xF5FA0FFFF5FA0FFF, 0x28)
		LUT(x3C90B3D63C90B3D6, x61C8F93C61C8F93C, x4848484848484848, x55500AAA55500AAA, 0x1E)
		LUT(x8484333384843333, a1, x9999666699996666, x4848484848484848, 0x14)
		LUT(x4452F1AC4452F1AC, xF50AF50AF50AF50A, xF5FA0FFFF5FA0FFF, xB35C94A6B35C94A6, 0x78)
		LUT(x9586CA379586CA37, x55500AAA55500AAA, x8484333384843333, x4452F1AC4452F1AC, 0xD6)
		LUT(x2, a6, x3C90B3D63C90B3D6, x9586CA379586CA37, 0x6A)
		LUT(x1, a6, x3C90B3D63C90B3D6, x9586CA379586CA37, 0xA9)
		LUT(x3, a6, x61C8F93C61C8F93C, xB35C94A6B35C94A6, 0x56)

		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s5(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(xA0A0A0A0FFFFFFFF, a1, a3, a6, 0xAB)
		LUT(xFFFF00005555FFFF, a1, a5, a6, 0xB9)
		LUT(xB3B320207777FFFF, a2, xA0A0A0A0FFFFFFFF, xFFFF00005555FFFF, 0xE8)
		LUT(x50505A5A5A5A5050, a1, a3, xFFFF00005555FFFF, 0x34)
		LUT(xA2A2FFFF2222FFFF, a1, a5, xB3B320207777FFFF, 0xCE)
		LUT(x2E2E6969A4A46363, a2, x50505A5A5A5A5050, xA2A2FFFF2222FFFF, 0x29)
		LUT(x3, a4, xB3B320207777FFFF, x2E2E6969A4A46363, 0xA6)
		LUT(xA5A50A0AA5A50A0A, a1, a3, a5, 0x49)
		LUT(x969639396969C6C6, a2, a6, xA5A50A0AA5A50A0A, 0x96)
		LUT(x1B1B1B1B1B1B1B1B, a1, a2, a3, 0xCA)
		LUT(xBFBFBFBFF6F6F9F9, a3, xA0A0A0A0FFFFFFFF, x969639396969C6C6, 0x7E)
		LUT(x5B5BA4A4B8B81D1D, xFFFF00005555FFFF, x1B1B1B1B1B1B1B1B, xBFBFBFBFF6F6F9F9, 0x96)
		LUT(x2, a4, x969639396969C6C6, x5B5BA4A4B8B81D1D, 0xCA)
		LUT(x5555BBBBFFFF5555, a1, a2, xFFFF00005555FFFF, 0xE5)
		LUT(x6D6D9C9C95956969, x50505A5A5A5A5050, xA2A2FFFF2222FFFF, x969639396969C6C6, 0x97)
		LUT(x1A1A67676A6AB4B4, xA5A50A0AA5A50A0A, x5555BBBBFFFF5555, x6D6D9C9C95956969, 0x47)
		LUT(xA0A0FFFFAAAA0000, a3, xFFFF00005555FFFF, xA5A50A0AA5A50A0A, 0x3B)
		LUT(x36369C9CC1C1D6D6, x969639396969C6C6, x6D6D9C9C95956969, xA0A0FFFFAAAA0000, 0xD9)
		LUT(x1, a4, x1A1A67676A6AB4B4, x36369C9CC1C1D6D6, 0xCA)
		LUT(x5555F0F0F5F55555, a1, a3, xFFFF00005555FFFF, 0xB1)
		LUT(x79790202DCDC0808, xA2A2FFFF2222FFFF, xA5A50A0AA5A50A0A, x969639396969C6C6, 0x47)
		LUT(x6C6CF2F229295D5D, xBFBFBFBFF6F6F9F9, x5555F0F0F5F55555, x79790202DCDC0808, 0x6E)
		LUT(xA3A3505010101A1A, a2, xA2A2FFFF2222FFFF, x36369C9CC1C1D6D6, 0x94)
		LUT(x7676C7C74F4FC7C7, a1, x2E2E6969A4A46363, xA3A3505010101A1A, 0xD9)
		LUT(x4, a4, x6C6CF2F229295D5D, x7676C7C74F4FC7C7, 0xC6)

		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s6(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(x5050F5F55050F5F5, a1, a3, a5, 0xB2)
		LUT(x6363C6C66363C6C6, a1, a2, x5050F5F55050F5F5, 0x66)
		LUT(xAAAA5555AAAA5555, a1, a1, a5, 0xA9)
		LUT(x3A3A65653A3A6565, a3, x6363C6C66363C6C6, xAAAA5555AAAA5555, 0xA9)
		LUT(x5963A3C65963A3C6, a4, x6363C6C66363C6C6, x3A3A65653A3A6565, 0xC6)
		LUT(xE7E76565E7E76565, a5, x6363C6C66363C6C6, x3A3A65653A3A6565, 0xAD)
		LUT(x455D45DF455D45DF, a1, a4, xE7E76565E7E76565, 0xE4)
		LUT(x4, a6, x5963A3C65963A3C6, x455D45DF455D45DF, 0x6C)
		LUT(x1101220211012202, a2, xAAAA5555AAAA5555, x5963A3C65963A3C6, 0x20)
		LUT(xF00F0FF0F00F0FF0, a3, a4, a5, 0x69)
		LUT(x16E94A9716E94A97, xE7E76565E7E76565, x1101220211012202, xF00F0FF0F00F0FF0, 0x9E)
		LUT(x2992922929929229, a1, a2, xF00F0FF0F00F0FF0, 0x49)
		LUT(xAFAF9823AFAF9823, a5, x5050F5F55050F5F5, x2992922929929229, 0x93)
		LUT(x3, a6, x16E94A9716E94A97, xAFAF9823AFAF9823, 0x6C)
		LUT(x4801810248018102, a4, x5963A3C65963A3C6, x1101220211012202, 0xA4)
		LUT(x5EE8FFFD5EE8FFFD, a5, x16E94A9716E94A97, x4801810248018102, 0x76)
		LUT(xF0FF00FFF0FF00FF, a3, a4, a5, 0xCD)
		LUT(x942D9A67942D9A67, x3A3A65653A3A6565, x5EE8FFFD5EE8FFFD, xF0FF00FFF0FF00FF, 0x86)
		LUT(x1, a6, x5EE8FFFD5EE8FFFD, x942D9A67942D9A67, 0xA6)
		LUT(x6A40D4ED6F4DD4EE, a2, x4, xAFAF9823AFAF9823, 0x2D)
		LUT(x6CA89C7869A49C79, x1101220211012202, x16E94A9716E94A97, x6A40D4ED6F4DD4EE, 0x26)
		LUT(xD6DE73F9D6DE73F9, a3, x6363C6C66363C6C6, x455D45DF455D45DF, 0x6B)
		LUT(x925E63E1965A63E1, x3A3A65653A3A6565, x6CA89C7869A49C79, xD6DE73F9D6DE73F9, 0xA2)
		LUT(x2, a6, x6CA89C7869A49C79, x925E63E1965A63E1, 0xCA)


		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s7(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(x88AA88AA88AA88AA, a1, a2, a4, 0x0B)
		LUT(xAAAAFF00AAAAFF00, a1, a4, a5, 0x27)
		LUT(xADAFF8A5ADAFF8A5, a3, x88AA88AA88AA88AA, xAAAAFF00AAAAFF00, 0x9E)
		LUT(x0A0AF5F50A0AF5F5, a1, a3, a5, 0xA6)
		LUT(x6B69C5DC6B69C5DC, a2, xADAFF8A5ADAFF8A5, x0A0AF5F50A0AF5F5, 0x6B)
		LUT(x1C69B2DC1C69B2DC, a4, x88AA88AA88AA88AA, x6B69C5DC6B69C5DC, 0xA9)
		LUT(x1, a6, xADAFF8A5ADAFF8A5, x1C69B2DC1C69B2DC, 0x6A)
		LUT(x9C9C9C9C9C9C9C9C, a1, a2, a3, 0x63)
		LUT(xE6E63BFDE6E63BFD, a2, xAAAAFF00AAAAFF00, x0A0AF5F50A0AF5F5, 0xE7)
		LUT(x6385639E6385639E, a4, x9C9C9C9C9C9C9C9C, xE6E63BFDE6E63BFD, 0x93)
		LUT(x5959C4CE5959C4CE, a2, x6B69C5DC6B69C5DC, xE6E63BFDE6E63BFD, 0x5D)
		LUT(x5B53F53B5B53F53B, a4, x0A0AF5F50A0AF5F5, x5959C4CE5959C4CE, 0x6E)
		LUT(x3, a6, x6385639E6385639E, x5B53F53B5B53F53B, 0xC6)
		LUT(xFAF505FAFAF505FA, a3, a4, x0A0AF5F50A0AF5F5, 0x6D)
		LUT(x6A65956A6A65956A, a3, x9C9C9C9C9C9C9C9C, xFAF505FAFAF505FA, 0xA6)
		LUT(x8888CCCC8888CCCC, a1, a2, a5, 0x23)
		LUT(x94E97A9494E97A94, x1C69B2DC1C69B2DC, x6A65956A6A65956A, x8888CCCC8888CCCC, 0x72)
		LUT(x4, a6, x6A65956A6A65956A, x94E97A9494E97A94, 0xAC)
		LUT(xA050A050A050A050, a1, a3, a4, 0x21)
		LUT(xC1B87A2BC1B87A2B, xAAAAFF00AAAAFF00, x5B53F53B5B53F53B, x94E97A9494E97A94, 0xA4)
		LUT(xE96016B7E96016B7, x8888CCCC8888CCCC, xA050A050A050A050, xC1B87A2BC1B87A2B, 0x96)
		LUT(xE3CF1FD5E3CF1FD5, x88AA88AA88AA88AA, x6A65956A6A65956A, xE96016B7E96016B7, 0x3E)
		LUT(x6776675B6776675B, xADAFF8A5ADAFF8A5, x94E97A9494E97A94, xE3CF1FD5E3CF1FD5, 0x6B)
		LUT(x2, a6, xE96016B7E96016B7, x6776675B6776675B, 0xC6)


		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

__device__ __forceinline__ void
s8(DES_Vector a1, DES_Vector a2, DES_Vector a3, DES_Vector a4, DES_Vector a5, DES_Vector a6,
DES_Vector * out1, DES_Vector * out2, DES_Vector * out3, DES_Vector * out4)
{
	LUT(xEEEE3333EEEE3333, a1, a2, a5, 0x9D)
		LUT(xBBBBBBBBBBBBBBBB, a1, a1, a2, 0x83)
		LUT(xDDDDAAAADDDDAAAA, a1, a2, a5, 0x5B)
		LUT(x29295A5A29295A5A, a3, xBBBBBBBBBBBBBBBB, xDDDDAAAADDDDAAAA, 0x85)
		LUT(xC729695AC729695A, a4, xEEEE3333EEEE3333, x29295A5A29295A5A, 0xA6)
		LUT(x3BF77B7B3BF77B7B, a2, a5, xC729695AC729695A, 0xF9)
		LUT(x2900FF002900FF00, a4, a5, x29295A5A29295A5A, 0x0E)
		LUT(x56B3803F56B3803F, xBBBBBBBBBBBBBBBB, x3BF77B7B3BF77B7B, x2900FF002900FF00, 0x61)
		LUT(x4, a6, xC729695AC729695A, x56B3803F56B3803F, 0x6C)
		LUT(xFBFBFBFBFBFBFBFB, a1, a2, a3, 0xDF)
		LUT(x3012B7B73012B7B7, a2, a5, xC729695AC729695A, 0xD4)
		LUT(x34E9B34C34E9B34C, a4, xFBFBFBFBFBFBFBFB, x3012B7B73012B7B7, 0x69)
		LUT(xBFEAEBBEBFEAEBBE, a1, x29295A5A29295A5A, x34E9B34C34E9B34C, 0x6F)
		LUT(xFFAEAFFEFFAEAFFE, a3, xBBBBBBBBBBBBBBBB, xBFEAEBBEBFEAEBBE, 0xB9)
		LUT(x2, a6, x34E9B34C34E9B34C, xFFAEAFFEFFAEAFFE, 0xC6)
		LUT(xCFDE88BBCFDE88BB, a2, xDDDDAAAADDDDAAAA, x34E9B34C34E9B34C, 0x5C)
		LUT(x3055574530555745, a1, xC729695AC729695A, xCFDE88BBCFDE88BB, 0x71)
		LUT(x99DDEEEE99DDEEEE, a4, xBBBBBBBBBBBBBBBB, xDDDDAAAADDDDAAAA, 0xB9)
		LUT(x693CD926693CD926, x3BF77B7B3BF77B7B, x34E9B34C34E9B34C, x99DDEEEE99DDEEEE, 0x69)
		LUT(x3, a6, x3055574530555745, x693CD926693CD926, 0x6A)
		LUT(x9955EE559955EE55, a1, a4, x99DDEEEE99DDEEEE, 0xE2)
		LUT(x9D48FA949D48FA94, x3BF77B7B3BF77B7B, xBFEAEBBEBFEAEBBE, x9955EE559955EE55, 0x9C)
		LUT(x1, a6, xC729695AC729695A, x9D48FA949D48FA94, 0x39)


		*out1 ^= x1;
	*out2 ^= x2;
	*out3 ^= x3;
	*out4 ^= x4;
}

#endif

#define CLEAR_BLOCK_8(i)                                                             \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 0, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 1, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 2, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 3, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 4, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 5, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 6, DES_VECTOR_ZERO); \
	DES_VECTOR_SET(dataBlocks[threadIdx.x + (i*N)] , 7, DES_VECTOR_ZERO); \

#define CLEAR_BLOCK()  \
	CLEAR_BLOCK_8(0);  \
	CLEAR_BLOCK_8(8);  \
	CLEAR_BLOCK_8(16); \
	CLEAR_BLOCK_8(24); \
	CLEAR_BLOCK_8(32); \
	CLEAR_BLOCK_8(40); \
	CLEAR_BLOCK_8(48); \
	CLEAR_BLOCK_8(56); \

DES_FUNCTION_QUALIFIERS
void DES_Crypt(volatile unsigned int keyFrom00To27, volatile unsigned int keyFrom28To48)
{
	if (threadIdx.y == 0)
		CLEAR_BLOCK();
	
	DES_Vector *db = dataBlocks + threadIdx.x;
	int E0, E1, E2, E3, E4, E5;

	switch (threadIdx.y) {
	case 0: 
		E0 = CUDA_expansionFunction[0]*N;
		E1 = CUDA_expansionFunction[1]*N;
		E2 = CUDA_expansionFunction[2]*N;
		E3 = CUDA_expansionFunction[3]*N;
		E4 = CUDA_expansionFunction[4]*N;
		E5 = CUDA_expansionFunction[5]*N;
		break;
	case 1: 
		E0 = CUDA_expansionFunction[6]*N;
		E1 = CUDA_expansionFunction[7]*N;
		E2 = CUDA_expansionFunction[8]*N;
		E3 = CUDA_expansionFunction[9]*N;
		E4 = CUDA_expansionFunction[10]*N;
		E5 = CUDA_expansionFunction[11]*N;
		break;
	case 2: 
		E0 = CUDA_expansionFunction[24]*N;
		E1 = CUDA_expansionFunction[25]*N;
		E2 = CUDA_expansionFunction[26]*N;
		E3 = CUDA_expansionFunction[27]*N;
		E4 = CUDA_expansionFunction[28]*N;
		E5 = CUDA_expansionFunction[29]*N;
		break;
	case 3: 
		E0 = CUDA_expansionFunction[30]*N;
		E1 = CUDA_expansionFunction[31]*N;
		E2 = CUDA_expansionFunction[32]*N;
		E3 = CUDA_expansionFunction[33]*N;
		E4 = CUDA_expansionFunction[34]*N;
		E5 = CUDA_expansionFunction[35]*N;
		break;
	}
	
#define K00 ((keyFrom00To27 & (0x1U << 0)) ? 0xffffffffU : 0x0)
#define K01 ((keyFrom00To27 & (0x1U << 1)) ? 0xffffffffU : 0x0)
#define K02 ((keyFrom00To27 & (0x1U << 2)) ? 0xffffffffU : 0x0)
#define K03 ((keyFrom00To27 & (0x1U << 3)) ? 0xffffffffU : 0x0)
#define K04 ((keyFrom00To27 & (0x1U << 4)) ? 0xffffffffU : 0x0)
#define K05 ((keyFrom00To27 & (0x1U << 5)) ? 0xffffffffU : 0x0)
#define K06 ((keyFrom00To27 & (0x1U << 6)) ? 0xffffffffU : 0x0)
#define K07 ((keyFrom00To27 & (0x1U << 7)) ? 0xffffffffU : 0x0)
#define K08 ((keyFrom00To27 & (0x1U << 8)) ? 0xffffffffU : 0x0)
#define K09 ((keyFrom00To27 & (0x1U << 9)) ? 0xffffffffU : 0x0)
#define K10 ((keyFrom00To27 & (0x1U << 10)) ? 0xffffffffU : 0x0)
#define K11 ((keyFrom00To27 & (0x1U << 11)) ? 0xffffffffU : 0x0)
#define K12 ((keyFrom00To27 & (0x1U << 12)) ? 0xffffffffU : 0x0)
#define K13 ((keyFrom00To27 & (0x1U << 13)) ? 0xffffffffU : 0x0)
#define K14 ((keyFrom00To27 & (0x1U << 14)) ? 0xffffffffU : 0x0)
#define K15 ((keyFrom00To27 & (0x1U << 15)) ? 0xffffffffU : 0x0)
#define K16 ((keyFrom00To27 & (0x1U << 16)) ? 0xffffffffU : 0x0)
#define K17 ((keyFrom00To27 & (0x1U << 17)) ? 0xffffffffU : 0x0)
#define K18 ((keyFrom00To27 & (0x1U << 18)) ? 0xffffffffU : 0x0)
#define K19 ((keyFrom00To27 & (0x1U << 19)) ? 0xffffffffU : 0x0)
#define K20 ((keyFrom00To27 & (0x1U << 20)) ? 0xffffffffU : 0x0)
#define K21 ((keyFrom00To27 & (0x1U << 21)) ? 0xffffffffU : 0x0)
#define K22 ((keyFrom00To27 & (0x1U << 22)) ? 0xffffffffU : 0x0)
#define K23 ((keyFrom00To27 & (0x1U << 23)) ? 0xffffffffU : 0x0)
#define K24 ((keyFrom00To27 & (0x1U << 24)) ? 0xffffffffU : 0x0)
#define K25 ((keyFrom00To27 & (0x1U << 25)) ? 0xffffffffU : 0x0)
#define K26 ((keyFrom00To27 & (0x1U << 26)) ? 0xffffffffU : 0x0)
#define K27 ((keyFrom00To27 & (0x1U << 27)) ? 0xffffffffU : 0x0)
#define K28 ((keyFrom28To48 & (0x1U << (28 - 28))) ? 0xffffffffU : 0x0)
#define K29 ((keyFrom28To48 & (0x1U << (29 - 28))) ? 0xffffffffU : 0x0)
#define K30 ((keyFrom28To48 & (0x1U << (30 - 28))) ? 0xffffffffU : 0x0)
#define K31 ((keyFrom28To48 & (0x1U << (31 - 28))) ? 0xffffffffU : 0x0)
#define K32 ((keyFrom28To48 & (0x1U << (32 - 28))) ? 0xffffffffU : 0x0)
#define K33 ((keyFrom28To48 & (0x1U << (33 - 28))) ? 0xffffffffU : 0x0)
#define K34 ((keyFrom28To48 & (0x1U << (34 - 28))) ? 0xffffffffU : 0x0)
#define K35 ((keyFrom28To48 & (0x1U << (35 - 28))) ? 0xffffffffU : 0x0)
#define K36 ((keyFrom28To48 & (0x1U << (36 - 28))) ? 0xffffffffU : 0x0)
#define K37 ((keyFrom28To48 & (0x1U << (37 - 28))) ? 0xffffffffU : 0x0)
#define K38 ((keyFrom28To48 & (0x1U << (38 - 28))) ? 0xffffffffU : 0x0)
#define K39 ((keyFrom28To48 & (0x1U << (39 - 28))) ? 0xffffffffU : 0x0)
#define K40 ((keyFrom28To48 & (0x1U << (40 - 28))) ? 0xffffffffU : 0x0)
#define K41 ((keyFrom28To48 & (0x1U << (41 - 28))) ? 0xffffffffU : 0x0)
#define K42 ((keyFrom28To48 & (0x1U << (42 - 28))) ? 0xffffffffU : 0x0)
#define K43 ((keyFrom28To48 & (0x1U << (43 - 28))) ? 0xffffffffU : 0x0)
#define K44 ((keyFrom28To48 & (0x1U << (44 - 28))) ? 0xffffffffU : 0x0)
#define K45 ((keyFrom28To48 & (0x1U << (45 - 28))) ? 0xffffffffU : 0x0)
#define K46 ((keyFrom28To48 & (0x1U << (46 - 28))) ? 0xffffffffU : 0x0)
#define K47 ((keyFrom28To48 & (0x1U << (47 - 28))) ? 0xffffffffU : 0x0)
#define K48 ((keyFrom28To48 & (0x1U << (48 - 28))) ? 0xffffffffU : 0x0)

#define K00XOR(val) ((keyFrom00To27 & (0x1U << 0)) ? ~(val) : (val))
#define K01XOR(val) ((keyFrom00To27 & (0x1U << 1)) ? ~(val) : (val))
#define K02XOR(val) ((keyFrom00To27 & (0x1U << 2)) ? ~(val) : (val))
#define K03XOR(val) ((keyFrom00To27 & (0x1U << 3)) ? ~(val) : (val))
#define K04XOR(val) ((keyFrom00To27 & (0x1U << 4)) ? ~(val) : (val))
#define K05XOR(val) ((keyFrom00To27 & (0x1U << 5)) ? ~(val) : (val))
#define K06XOR(val) ((keyFrom00To27 & (0x1U << 6)) ? ~(val) : (val))
#define K07XOR(val) ((keyFrom00To27 & (0x1U << 7)) ? ~(val) : (val))
#define K08XOR(val) ((keyFrom00To27 & (0x1U << 8)) ? ~(val) : (val))
#define K09XOR(val) ((keyFrom00To27 & (0x1U << 9)) ? ~(val) : (val))
#define K10XOR(val) ((keyFrom00To27 & (0x1U << 10)) ? ~(val) : (val))
#define K11XOR(val) ((keyFrom00To27 & (0x1U << 11)) ? ~(val) : (val))
#define K12XOR(val) ((keyFrom00To27 & (0x1U << 12)) ? ~(val) : (val))
#define K13XOR(val) ((keyFrom00To27 & (0x1U << 13)) ? ~(val) : (val))
#define K14XOR(val) ((keyFrom00To27 & (0x1U << 14)) ? ~(val) : (val))
#define K15XOR(val) ((keyFrom00To27 & (0x1U << 15)) ? ~(val) : (val))
#define K16XOR(val) ((keyFrom00To27 & (0x1U << 16)) ? ~(val) : (val))
#define K17XOR(val) ((keyFrom00To27 & (0x1U << 17)) ? ~(val) : (val))
#define K18XOR(val) ((keyFrom00To27 & (0x1U << 18)) ? ~(val) : (val))
#define K19XOR(val) ((keyFrom00To27 & (0x1U << 19)) ? ~(val) : (val))
#define K20XOR(val) ((keyFrom00To27 & (0x1U << 20)) ? ~(val) : (val))
#define K21XOR(val) ((keyFrom00To27 & (0x1U << 21)) ? ~(val) : (val))
#define K22XOR(val) ((keyFrom00To27 & (0x1U << 22)) ? ~(val) : (val))
#define K23XOR(val) ((keyFrom00To27 & (0x1U << 23)) ? ~(val) : (val))
#define K24XOR(val) ((keyFrom00To27 & (0x1U << 24)) ? ~(val) : (val))
#define K25XOR(val) ((keyFrom00To27 & (0x1U << 25)) ? ~(val) : (val))
#define K26XOR(val) ((keyFrom00To27 & (0x1U << 26)) ? ~(val) : (val))
#define K27XOR(val) ((keyFrom00To27 & (0x1U << 27)) ? ~(val) : (val))
#define K28XOR(val) ((keyFrom28To48 & (0x1U << (28 - 28))) ? ~(val) : (val))
#define K29XOR(val) ((keyFrom28To48 & (0x1U << (29 - 28))) ? ~(val) : (val))
#define K30XOR(val) ((keyFrom28To48 & (0x1U << (30 - 28))) ? ~(val) : (val))
#define K31XOR(val) ((keyFrom28To48 & (0x1U << (31 - 28))) ? ~(val) : (val))
#define K32XOR(val) ((keyFrom28To48 & (0x1U << (32 - 28))) ? ~(val) : (val))
#define K33XOR(val) ((keyFrom28To48 & (0x1U << (33 - 28))) ? ~(val) : (val))
#define K34XOR(val) ((keyFrom28To48 & (0x1U << (34 - 28))) ? ~(val) : (val))
#define K35XOR(val) ((keyFrom28To48 & (0x1U << (35 - 28))) ? ~(val) : (val))
#define K36XOR(val) ((keyFrom28To48 & (0x1U << (36 - 28))) ? ~(val) : (val))
#define K37XOR(val) ((keyFrom28To48 & (0x1U << (37 - 28))) ? ~(val) : (val))
#define K38XOR(val) ((keyFrom28To48 & (0x1U << (38 - 28))) ? ~(val) : (val))
#define K39XOR(val) ((keyFrom28To48 & (0x1U << (39 - 28))) ? ~(val) : (val))
#define K40XOR(val) ((keyFrom28To48 & (0x1U << (40 - 28))) ? ~(val) : (val))
#define K41XOR(val) ((keyFrom28To48 & (0x1U << (41 - 28))) ? ~(val) : (val))
#define K42XOR(val) ((keyFrom28To48 & (0x1U << (42 - 28))) ? ~(val) : (val))
#define K43XOR(val) ((keyFrom28To48 & (0x1U << (43 - 28))) ? ~(val) : (val))
#define K44XOR(val) ((keyFrom28To48 & (0x1U << (44 - 28))) ? ~(val) : (val))
#define K45XOR(val) ((keyFrom28To48 & (0x1U << (45 - 28))) ? ~(val) : (val))
#define K46XOR(val) ((keyFrom28To48 & (0x1U << (46 - 28))) ? ~(val) : (val))
#define K47XOR(val) ((keyFrom28To48 & (0x1U << (47 - 28))) ? ~(val) : (val))
#define K48XOR(val) ((keyFrom28To48 & (0x1U << (48 - 28))) ? ~(val) : (val))
#define K49XOR(val) ((val) ^ CUDA_keyFrom49To55Array[0])
#define K50XOR(val) ((val) ^ CUDA_keyFrom49To55Array[1])
#define K51XOR(val) ((val) ^ CUDA_keyFrom49To55Array[2])
#define K52XOR(val) ((val) ^ CUDA_keyFrom49To55Array[3])
#define K53XOR(val) ((val) ^ CUDA_keyFrom49To55Array[4])
#define K54XOR(val) ((val) ^ CUDA_keyFrom49To55Array[5])
#define K55XOR(val) ((val) ^ CUDA_keyFrom49To55Array[6])

#if FALSE

#pragma unroll 1 // Do not unroll.
	for (int i = 0; i < 13; ++i) {
		// ROUND_A(0);
		switch (threadIdx.y) {
		case 0: s1(K12XOR(db[E0]), K46XOR(db[E1]), K33XOR(db[E2]), K52XOR(db[E3]), K48XOR(db[E4]), K20XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K53XOR(db[11*N]), K06XOR(db[12*N]), K31XOR(db[13*N]), K25XOR(db[14*N]), K19XOR(db[15*N]), K41XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K04XOR(db[ 7*N]), K32XOR(db[ 8*N]), K26XOR(db[ 9*N]), K27XOR(db[10*N]), K38XOR(db[11*N]), K54XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K34XOR(db[E0]), K55XOR(db[E1]), K05XOR(db[E2]), K13XOR(db[E3]), K18XOR(db[E4]), K40XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K15XOR(db[E0]), K24XOR(db[E1]), K28XOR(db[E2]), K43XOR(db[E3]), K30XOR(db[E4]), K03XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K37XOR(db[27*N]), K08XOR(db[28*N]), K09XOR(db[29*N]), K50XOR(db[30*N]), K42XOR(db[31*N]), K21XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K51XOR(db[23*N]), K16XOR(db[24*N]), K29XOR(db[25*N]), K49XOR(db[26*N]), K07XOR(db[27*N]), K17XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K35XOR(db[E0]), K22XOR(db[E1]), K02XOR(db[E2]), K44XOR(db[E3]), K14XOR(db[E4]), K23XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(0);
		switch (threadIdx.y) {
		case 0: s1(K05XOR(db[(E0)+(32*N)]), K39XOR(db[(E1)+(32*N)]), K26XOR(db[(E2)+(32*N)]), K45XOR(db[(E3)+(32*N)]), K41XOR(db[(E4)+(32*N)]), K13XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K46XOR(db[43*N]), K54XOR(db[44*N]), K55XOR(db[45*N]), K18XOR(db[46*N]), K12XOR(db[47*N]), K34XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K52XOR(db[39*N]), K25XOR(db[40*N]), K19XOR(db[41*N]), K20XOR(db[42*N]), K31XOR(db[43*N]), K47XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K27XOR(db[(E0)+(32*N)]), K48XOR(db[(E1)+(32*N)]), K53XOR(db[(E2)+(32*N)]), K06XOR(db[(E3)+(32*N)]), K11XOR(db[(E4)+(32*N)]), K33XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K08XOR(db[(E0)+(32*N)]), K17XOR(db[(E1)+(32*N)]), K21XOR(db[(E2)+(32*N)]), K36XOR(db[(E3)+(32*N)]), K23XOR(db[(E4)+(32*N)]), K49XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K30XOR(db[59*N]), K01XOR(db[60*N]), K02XOR(db[61*N]), K43XOR(db[62*N]), K35XOR(db[63*N]), K14XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K44XOR(db[55*N]), K09XOR(db[56*N]), K22XOR(db[57*N]), K42XOR(db[58*N]), K00XOR(db[59*N]), K10XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K28XOR(db[(E0)+(32*N)]), K15XOR(db[(E1)+(32*N)]), K24XOR(db[(E2)+(32*N)]), K37XOR(db[(E3)+(32*N)]), K07XOR(db[(E4)+(32*N)]), K16XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(96);
		switch (threadIdx.y) {
		case 0: s1(K46XOR(db[E0]), K25XOR(db[E1]), K12XOR(db[E2]), K31XOR(db[E3]), K27XOR(db[E4]), K54XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K32XOR(db[11*N]), K40XOR(db[12*N]), K41XOR(db[13*N]), K04XOR(db[14*N]), K53XOR(db[15*N]), K20XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K38XOR(db[ 7*N]), K11XOR(db[ 8*N]), K05XOR(db[ 9*N]), K06XOR(db[10*N]), K48XOR(db[11*N]), K33XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K13XOR(db[E0]), K34XOR(db[E1]), K39XOR(db[E2]), K47XOR(db[E3]), K52XOR(db[E4]), K19XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K51XOR(db[E0]), K03XOR(db[E1]), K07XOR(db[E2]), K22XOR(db[E3]), K09XOR(db[E4]), K35XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K16XOR(db[27*N]), K44XOR(db[28*N]), K17XOR(db[29*N]), K29XOR(db[30*N]), K21XOR(db[31*N]), K00XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K30XOR(db[23*N]), K24XOR(db[24*N]), K08XOR(db[25*N]), K28XOR(db[26*N]), K43XOR(db[27*N]), K49XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K14XOR(db[E0]), K01XOR(db[E1]), K10XOR(db[E2]), K23XOR(db[E3]), K50XOR(db[E4]), K02XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(96);
		switch (threadIdx.y) {
		case 0: s1(K32XOR(db[(E0)+(32*N)]), K11XOR(db[(E1)+(32*N)]), K53XOR(db[(E2)+(32*N)]), K48XOR(db[(E3)+(32*N)]), K13XOR(db[(E4)+(32*N)]), K40XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K18XOR(db[43*N]), K26XOR(db[44*N]), K27XOR(db[45*N]), K45XOR(db[46*N]), K39XOR(db[47*N]), K06XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K55XOR(db[39*N]), K52XOR(db[40*N]), K46XOR(db[41*N]), K47XOR(db[42*N]), K34XOR(db[43*N]), K19XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K54XOR(db[(E0)+(32*N)]), K20XOR(db[(E1)+(32*N)]), K25XOR(db[(E2)+(32*N)]), K33XOR(db[(E3)+(32*N)]), K38XOR(db[(E4)+(32*N)]), K05XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K37XOR(db[(E0)+(32*N)]), K42XOR(db[(E1)+(32*N)]), K50XOR(db[(E2)+(32*N)]), K08XOR(db[(E3)+(32*N)]), K24XOR(db[(E4)+(32*N)]), K21XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K02XOR(db[59*N]), K30XOR(db[60*N]), K03XOR(db[61*N]), K15XOR(db[62*N]), K07XOR(db[63*N]), K43XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K16XOR(db[55*N]), K10XOR(db[56*N]), K51XOR(db[57*N]), K14XOR(db[58*N]), K29XOR(db[59*N]), K35XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K00XOR(db[(E0)+(32*N)]), K44XOR(db[(E1)+(32*N)]), K49XOR(db[(E2)+(32*N)]), K09XOR(db[(E3)+(32*N)]), K36XOR(db[(E4)+(32*N)]), K17XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(192);
		switch (threadIdx.y) {
		case 0: s1(K18XOR(db[E0]), K52XOR(db[E1]), K39XOR(db[E2]), K34XOR(db[E3]), K54XOR(db[E4]), K26XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K04XOR(db[11*N]), K12XOR(db[12*N]), K13XOR(db[13*N]), K31XOR(db[14*N]), K25XOR(db[15*N]), K47XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K41XOR(db[ 7*N]), K38XOR(db[ 8*N]), K32XOR(db[ 9*N]), K33XOR(db[10*N]), K20XOR(db[11*N]), K05XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K40XOR(db[E0]), K06XOR(db[E1]), K11XOR(db[E2]), K19XOR(db[E3]), K55XOR(db[E4]), K46XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K23XOR(db[E0]), K28XOR(db[E1]), K36XOR(db[E2]), K51XOR(db[E3]), K10XOR(db[E4]), K07XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K17XOR(db[27*N]), K16XOR(db[28*N]), K42XOR(db[29*N]), K01XOR(db[30*N]), K50XOR(db[31*N]), K29XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K02XOR(db[23*N]), K49XOR(db[24*N]), K37XOR(db[25*N]), K00XOR(db[26*N]), K15XOR(db[27*N]), K21XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K43XOR(db[E0]), K30XOR(db[E1]), K35XOR(db[E2]), K24XOR(db[E3]), K22XOR(db[E4]), K03XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(192);
		switch (threadIdx.y) {
		case 0: s1(K04XOR(db[(E0)+(32*N)]), K38XOR(db[(E1)+(32*N)]), K25XOR(db[(E2)+(32*N)]), K20XOR(db[(E3)+(32*N)]), K40XOR(db[(E4)+(32*N)]), K12XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K45XOR(db[43*N]), K53XOR(db[44*N]), K54XOR(db[45*N]), K48XOR(db[46*N]), K11XOR(db[47*N]), K33XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K27XOR(db[39*N]), K55XOR(db[40*N]), K18XOR(db[41*N]), K19XOR(db[42*N]), K06XOR(db[43*N]), K46XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K26XOR(db[(E0)+(32*N)]), K47XOR(db[(E1)+(32*N)]), K52XOR(db[(E2)+(32*N)]), K05XOR(db[(E3)+(32*N)]), K41XOR(db[(E4)+(32*N)]), K32XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K09XOR(db[(E0)+(32*N)]), K14XOR(db[(E1)+(32*N)]), K22XOR(db[(E2)+(32*N)]), K37XOR(db[(E3)+(32*N)]), K49XOR(db[(E4)+(32*N)]), K50XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K03XOR(db[59*N]), K02XOR(db[60*N]), K28XOR(db[61*N]), K44XOR(db[62*N]), K36XOR(db[63*N]), K15XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K17XOR(db[55*N]), K35XOR(db[56*N]), K23XOR(db[57*N]), K43XOR(db[58*N]), K01XOR(db[59*N]), K07XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K29XOR(db[(E0)+(32*N)]), K16XOR(db[(E1)+(32*N)]), K21XOR(db[(E2)+(32*N)]), K10XOR(db[(E3)+(32*N)]), K08XOR(db[(E4)+(32*N)]), K42XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(288);
		switch (threadIdx.y) {
		case 0: s1(K45XOR(db[E0]), K55XOR(db[E1]), K11XOR(db[E2]), K06XOR(db[E3]), K26XOR(db[E4]), K53XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K31XOR(db[11*N]), K39XOR(db[12*N]), K40XOR(db[13*N]), K34XOR(db[14*N]), K52XOR(db[15*N]), K19XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K13XOR(db[ 7*N]), K41XOR(db[ 8*N]), K04XOR(db[ 9*N]), K05XOR(db[10*N]), K47XOR(db[11*N]), K32XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K12XOR(db[E0]), K33XOR(db[E1]), K38XOR(db[E2]), K46XOR(db[E3]), K27XOR(db[E4]), K18XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K24XOR(db[E0]), K00XOR(db[E1]), K08XOR(db[E2]), K23XOR(db[E3]), K35XOR(db[E4]), K36XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K42XOR(db[27*N]), K17XOR(db[28*N]), K14XOR(db[29*N]), K30XOR(db[30*N]), K22XOR(db[31*N]), K01XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K03XOR(db[23*N]), K21XOR(db[24*N]), K09XOR(db[25*N]), K29XOR(db[26*N]), K44XOR(db[27*N]), K50XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K15XOR(db[E0]), K02XOR(db[E1]), K07XOR(db[E2]), K49XOR(db[E3]), K51XOR(db[E4]), K28XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(288);
		switch (threadIdx.y) {
		case 0: s1(K31XOR(db[(E0)+(32*N)]), K41XOR(db[(E1)+(32*N)]), K52XOR(db[(E2)+(32*N)]), K47XOR(db[(E3)+(32*N)]), K12XOR(db[(E4)+(32*N)]), K39XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K48XOR(db[43*N]), K25XOR(db[44*N]), K26XOR(db[45*N]), K20XOR(db[46*N]), K38XOR(db[47*N]), K05XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K54XOR(db[39*N]), K27XOR(db[40*N]), K45XOR(db[41*N]), K46XOR(db[42*N]), K33XOR(db[43*N]), K18XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K53XOR(db[(E0)+(32*N)]), K19XOR(db[(E1)+(32*N)]), K55XOR(db[(E2)+(32*N)]), K32XOR(db[(E3)+(32*N)]), K13XOR(db[(E4)+(32*N)]), K04XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K10XOR(db[(E0)+(32*N)]), K43XOR(db[(E1)+(32*N)]), K51XOR(db[(E2)+(32*N)]), K09XOR(db[(E3)+(32*N)]), K21XOR(db[(E4)+(32*N)]), K22XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K28XOR(db[59*N]), K03XOR(db[60*N]), K00XOR(db[61*N]), K16XOR(db[62*N]), K08XOR(db[63*N]), K44XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K42XOR(db[55*N]), K07XOR(db[56*N]), K24XOR(db[57*N]), K15XOR(db[58*N]), K30XOR(db[59*N]), K36XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K01XOR(db[(E0)+(32*N)]), K17XOR(db[(E1)+(32*N)]), K50XOR(db[(E2)+(32*N)]), K35XOR(db[(E3)+(32*N)]), K37XOR(db[(E4)+(32*N)]), K14XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(384);
		switch (threadIdx.y) {
		case 0: s1(K55XOR(db[E0]), K34XOR(db[E1]), K45XOR(db[E2]), K40XOR(db[E3]), K05XOR(db[E4]), K32XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K41XOR(db[11*N]), K18XOR(db[12*N]), K19XOR(db[13*N]), K13XOR(db[14*N]), K31XOR(db[15*N]), K53XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K47XOR(db[ 7*N]), K20XOR(db[ 8*N]), K38XOR(db[ 9*N]), K39XOR(db[10*N]), K26XOR(db[11*N]), K11XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K46XOR(db[E0]), K12XOR(db[E1]), K48XOR(db[E2]), K25XOR(db[E3]), K06XOR(db[E4]), K52XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K03XOR(db[E0]), K36XOR(db[E1]), K44XOR(db[E2]), K02XOR(db[E3]), K14XOR(db[E4]), K15XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K21XOR(db[27*N]), K49XOR(db[28*N]), K50XOR(db[29*N]), K09XOR(db[30*N]), K01XOR(db[31*N]), K37XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K35XOR(db[23*N]), K00XOR(db[24*N]), K17XOR(db[25*N]), K08XOR(db[26*N]), K23XOR(db[27*N]), K29XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K51XOR(db[E0]), K10XOR(db[E1]), K43XOR(db[E2]), K28XOR(db[E3]), K30XOR(db[E4]), K07XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(384);
		switch (threadIdx.y) {
		case 0: s1(K41XOR(db[(E0)+(32*N)]), K20XOR(db[(E1)+(32*N)]), K31XOR(db[(E2)+(32*N)]), K26XOR(db[(E3)+(32*N)]), K46XOR(db[(E4)+(32*N)]), K18XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K27XOR(db[43*N]), K04XOR(db[44*N]), K05XOR(db[45*N]), K54XOR(db[46*N]), K48XOR(db[47*N]), K39XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K33XOR(db[39*N]), K06XOR(db[40*N]), K55XOR(db[41*N]), K25XOR(db[42*N]), K12XOR(db[43*N]), K52XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K32XOR(db[(E0)+(32*N)]), K53XOR(db[(E1)+(32*N)]), K34XOR(db[(E2)+(32*N)]), K11XOR(db[(E3)+(32*N)]), K47XOR(db[(E4)+(32*N)]), K38XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K42XOR(db[(E0)+(32*N)]), K22XOR(db[(E1)+(32*N)]), K30XOR(db[(E2)+(32*N)]), K17XOR(db[(E3)+(32*N)]), K00XOR(db[(E4)+(32*N)]), K01XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K07XOR(db[59*N]), K35XOR(db[60*N]), K36XOR(db[61*N]), K24XOR(db[62*N]), K44XOR(db[63*N]), K23XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K21XOR(db[55*N]), K43XOR(db[56*N]), K03XOR(db[57*N]), K51XOR(db[58*N]), K09XOR(db[59*N]), K15XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K37XOR(db[(E0)+(32*N)]), K49XOR(db[(E1)+(32*N)]), K29XOR(db[(E2)+(32*N)]), K14XOR(db[(E3)+(32*N)]), K16XOR(db[(E4)+(32*N)]), K50XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(480);
		switch (threadIdx.y) {
		case 0: s1(K27XOR(db[E0]), K06XOR(db[E1]), K48XOR(db[E2]), K12XOR(db[E3]), K32XOR(db[E4]), K04XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K13XOR(db[11*N]), K45XOR(db[12*N]), K46XOR(db[13*N]), K40XOR(db[14*N]), K34XOR(db[15*N]), K25XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K19XOR(db[ 7*N]), K47XOR(db[ 8*N]), K41XOR(db[ 9*N]), K11XOR(db[10*N]), K53XOR(db[11*N]), K38XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K18XOR(db[E0]), K39XOR(db[E1]), K20XOR(db[E2]), K52XOR(db[E3]), K33XOR(db[E4]), K55XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K28XOR(db[E0]), K08XOR(db[E1]), K16XOR(db[E2]), K03XOR(db[E3]), K43XOR(db[E4]), K44XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K50XOR(db[27*N]), K21XOR(db[28*N]), K22XOR(db[29*N]), K10XOR(db[30*N]), K30XOR(db[31*N]), K09XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K07XOR(db[23*N]), K29XOR(db[24*N]), K42XOR(db[25*N]), K37XOR(db[26*N]), K24XOR(db[27*N]), K01XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K23XOR(db[E0]), K35XOR(db[E1]), K15XOR(db[E2]), K00XOR(db[E3]), K02XOR(db[E4]), K36XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(480);
		switch (threadIdx.y) {
		case 0: s1(K13XOR(db[(E0)+(32*N)]), K47XOR(db[(E1)+(32*N)]), K34XOR(db[(E2)+(32*N)]), K53XOR(db[(E3)+(32*N)]), K18XOR(db[(E4)+(32*N)]), K45XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K54XOR(db[43*N]), K31XOR(db[44*N]), K32XOR(db[45*N]), K26XOR(db[46*N]), K20XOR(db[47*N]), K11XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K05XOR(db[39*N]), K33XOR(db[40*N]), K27XOR(db[41*N]), K52XOR(db[42*N]), K39XOR(db[43*N]), K55XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K04XOR(db[(E0)+(32*N)]), K25XOR(db[(E1)+(32*N)]), K06XOR(db[(E2)+(32*N)]), K38XOR(db[(E3)+(32*N)]), K19XOR(db[(E4)+(32*N)]), K41XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K14XOR(db[(E0)+(32*N)]), K51XOR(db[(E1)+(32*N)]), K02XOR(db[(E2)+(32*N)]), K42XOR(db[(E3)+(32*N)]), K29XOR(db[(E4)+(32*N)]), K30XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K36XOR(db[59*N]), K07XOR(db[60*N]), K08XOR(db[61*N]), K49XOR(db[62*N]), K16XOR(db[63*N]), K24XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K50XOR(db[55*N]), K15XOR(db[56*N]), K28XOR(db[57*N]), K23XOR(db[58*N]), K10XOR(db[59*N]), K44XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K09XOR(db[(E0)+(32*N)]), K21XOR(db[(E1)+(32*N)]), K01XOR(db[(E2)+(32*N)]), K43XOR(db[(E3)+(32*N)]), K17XOR(db[(E4)+(32*N)]), K22XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(576);
		switch (threadIdx.y) {
		case 0: s1(K54XOR(db[E0]), K33XOR(db[E1]), K20XOR(db[E2]), K39XOR(db[E3]), K04XOR(db[E4]), K31XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K40XOR(db[11*N]), K48XOR(db[12*N]), K18XOR(db[13*N]), K12XOR(db[14*N]), K06XOR(db[15*N]), K52XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K46XOR(db[ 7*N]), K19XOR(db[ 8*N]), K13XOR(db[ 9*N]), K38XOR(db[10*N]), K25XOR(db[11*N]), K41XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K45XOR(db[E0]), K11XOR(db[E1]), K47XOR(db[E2]), K55XOR(db[E3]), K05XOR(db[E4]), K27XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K00XOR(db[E0]), K37XOR(db[E1]), K17XOR(db[E2]), K28XOR(db[E3]), K15XOR(db[E4]), K16XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K22XOR(db[27*N]), K50XOR(db[28*N]), K51XOR(db[29*N]), K35XOR(db[30*N]), K02XOR(db[31*N]), K10XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K36XOR(db[23*N]), K01XOR(db[24*N]), K14XOR(db[25*N]), K09XOR(db[26*N]), K49XOR(db[27*N]), K30XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K24XOR(db[E0]), K07XOR(db[E1]), K44XOR(db[E2]), K29XOR(db[E3]), K03XOR(db[E4]), K08XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(576);
		switch (threadIdx.y) {
		case 0: s1(K40XOR(db[(E0)+(32*N)]), K19XOR(db[(E1)+(32*N)]), K06XOR(db[(E2)+(32*N)]), K25XOR(db[(E3)+(32*N)]), K45XOR(db[(E4)+(32*N)]), K48XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K26XOR(db[43*N]), K34XOR(db[44*N]), K04XOR(db[45*N]), K53XOR(db[46*N]), K47XOR(db[47*N]), K38XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K32XOR(db[39*N]), K05XOR(db[40*N]), K54XOR(db[41*N]), K55XOR(db[42*N]), K11XOR(db[43*N]), K27XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K31XOR(db[(E0)+(32*N)]), K52XOR(db[(E1)+(32*N)]), K33XOR(db[(E2)+(32*N)]), K41XOR(db[(E3)+(32*N)]), K46XOR(db[(E4)+(32*N)]), K13XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K43XOR(db[(E0)+(32*N)]), K23XOR(db[(E1)+(32*N)]), K03XOR(db[(E2)+(32*N)]), K14XOR(db[(E3)+(32*N)]), K01XOR(db[(E4)+(32*N)]), K02XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K08XOR(db[59*N]), K36XOR(db[60*N]), K37XOR(db[61*N]), K21XOR(db[62*N]), K17XOR(db[63*N]), K49XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K22XOR(db[55*N]), K44XOR(db[56*N]), K00XOR(db[57*N]), K24XOR(db[58*N]), K35XOR(db[59*N]), K16XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K10XOR(db[(E0)+(32*N)]), K50XOR(db[(E1)+(32*N)]), K30XOR(db[(E2)+(32*N)]), K15XOR(db[(E3)+(32*N)]), K42XOR(db[(E4)+(32*N)]), K51XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(672);
		switch (threadIdx.y) {
		case 0: s1(K26XOR(db[E0]), K05XOR(db[E1]), K47XOR(db[E2]), K11XOR(db[E3]), K31XOR(db[E4]), K34XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K12XOR(db[11*N]), K20XOR(db[12*N]), K45XOR(db[13*N]), K39XOR(db[14*N]), K33XOR(db[15*N]), K55XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K18XOR(db[ 7*N]), K46XOR(db[ 8*N]), K40XOR(db[ 9*N]), K41XOR(db[10*N]), K52XOR(db[11*N]), K13XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K48XOR(db[E0]), K38XOR(db[E1]), K19XOR(db[E2]), K27XOR(db[E3]), K32XOR(db[E4]), K54XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K29XOR(db[E0]), K09XOR(db[E1]), K42XOR(db[E2]), K00XOR(db[E3]), K44XOR(db[E4]), K17XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K51XOR(db[27*N]), K22XOR(db[28*N]), K23XOR(db[29*N]), K07XOR(db[30*N]), K03XOR(db[31*N]), K35XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K08XOR(db[23*N]), K30XOR(db[24*N]), K43XOR(db[25*N]), K10XOR(db[26*N]), K21XOR(db[27*N]), K02XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K49XOR(db[E0]), K36XOR(db[E1]), K16XOR(db[E2]), K01XOR(db[E3]), K28XOR(db[E4]), K37XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(672);
		switch (threadIdx.y) {
		case 0: s1(K19XOR(db[(E0)+(32*N)]), K53XOR(db[(E1)+(32*N)]), K40XOR(db[(E2)+(32*N)]), K04XOR(db[(E3)+(32*N)]), K55XOR(db[(E4)+(32*N)]), K27XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K05XOR(db[43*N]), K13XOR(db[44*N]), K38XOR(db[45*N]), K32XOR(db[46*N]), K26XOR(db[47*N]), K48XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K11XOR(db[39*N]), K39XOR(db[40*N]), K33XOR(db[41*N]), K34XOR(db[42*N]), K45XOR(db[43*N]), K06XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K41XOR(db[(E0)+(32*N)]), K31XOR(db[(E1)+(32*N)]), K12XOR(db[(E2)+(32*N)]), K20XOR(db[(E3)+(32*N)]), K25XOR(db[(E4)+(32*N)]), K47XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K22XOR(db[(E0)+(32*N)]), K02XOR(db[(E1)+(32*N)]), K35XOR(db[(E2)+(32*N)]), K50XOR(db[(E3)+(32*N)]), K37XOR(db[(E4)+(32*N)]), K10XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K44XOR(db[59*N]), K15XOR(db[60*N]), K16XOR(db[61*N]), K00XOR(db[62*N]), K49XOR(db[63*N]), K28XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K01XOR(db[55*N]), K23XOR(db[56*N]), K36XOR(db[57*N]), K03XOR(db[58*N]), K14XOR(db[59*N]), K24XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K42XOR(db[(E0)+(32*N)]), K29XOR(db[(E1)+(32*N)]), K09XOR(db[(E2)+(32*N)]), K51XOR(db[(E3)+(32*N)]), K21XOR(db[(E4)+(32*N)]), K30XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		if (i >= 12)
			break;

		// ROUND_B(-48);
		switch (threadIdx.y) {
		case 0: s1(K12XOR(db[(E0)+(32*N)]), K46XOR(db[(E1)+(32*N)]), K33XOR(db[(E2)+(32*N)]), K52XOR(db[(E3)+(32*N)]), K48XOR(db[(E4)+(32*N)]), K20XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K53XOR(db[43*N]), K06XOR(db[44*N]), K31XOR(db[45*N]), K25XOR(db[46*N]), K19XOR(db[47*N]), K41XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K04XOR(db[39*N]), K32XOR(db[40*N]), K26XOR(db[41*N]), K27XOR(db[42*N]), K38XOR(db[43*N]), K54XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K34XOR(db[(E0)+(32*N)]), K55XOR(db[(E1)+(32*N)]), K05XOR(db[(E2)+(32*N)]), K13XOR(db[(E3)+(32*N)]), K18XOR(db[(E4)+(32*N)]), K40XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K15XOR(db[(E0)+(32*N)]), K24XOR(db[(E1)+(32*N)]), K28XOR(db[(E2)+(32*N)]), K43XOR(db[(E3)+(32*N)]), K30XOR(db[(E4)+(32*N)]), K03XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K37XOR(db[59*N]), K08XOR(db[60*N]), K09XOR(db[61*N]), K50XOR(db[62*N]), K42XOR(db[63*N]), K21XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K51XOR(db[55*N]), K16XOR(db[56*N]), K29XOR(db[57*N]), K49XOR(db[58*N]), K07XOR(db[59*N]), K17XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K35XOR(db[(E0)+(32*N)]), K22XOR(db[(E1)+(32*N)]), K02XOR(db[(E2)+(32*N)]), K44XOR(db[(E3)+(32*N)]), K14XOR(db[(E4)+(32*N)]), K23XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(48);
		switch (threadIdx.y) {
		case 0: s1(K05XOR(db[E0]), K39XOR(db[E1]), K26XOR(db[E2]), K45XOR(db[E3]), K41XOR(db[E4]), K13XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K46XOR(db[11*N]), K54XOR(db[12*N]), K55XOR(db[13*N]), K18XOR(db[14*N]), K12XOR(db[15*N]), K34XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K52XOR(db[ 7*N]), K25XOR(db[ 8*N]), K19XOR(db[ 9*N]), K20XOR(db[10*N]), K31XOR(db[11*N]), K47XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K27XOR(db[E0]), K48XOR(db[E1]), K53XOR(db[E2]), K06XOR(db[E3]), K11XOR(db[E4]), K33XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K08XOR(db[E0]), K17XOR(db[E1]), K21XOR(db[E2]), K36XOR(db[E3]), K23XOR(db[E4]), K49XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K30XOR(db[27*N]), K01XOR(db[28*N]), K02XOR(db[29*N]), K43XOR(db[30*N]), K35XOR(db[31*N]), K14XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K44XOR(db[23*N]), K09XOR(db[24*N]), K22XOR(db[25*N]), K42XOR(db[26*N]), K00XOR(db[27*N]), K10XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K28XOR(db[E0]), K15XOR(db[E1]), K24XOR(db[E2]), K37XOR(db[E3]), K07XOR(db[E4]), K16XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(48);
		switch (threadIdx.y) {
		case 0: s1(K46XOR(db[(E0)+(32*N)]), K25XOR(db[(E1)+(32*N)]), K12XOR(db[(E2)+(32*N)]), K31XOR(db[(E3)+(32*N)]), K27XOR(db[(E4)+(32*N)]), K54XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K32XOR(db[43*N]), K40XOR(db[44*N]), K41XOR(db[45*N]), K04XOR(db[46*N]), K53XOR(db[47*N]), K20XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K38XOR(db[39*N]), K11XOR(db[40*N]), K05XOR(db[41*N]), K06XOR(db[42*N]), K48XOR(db[43*N]), K33XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K13XOR(db[(E0)+(32*N)]), K34XOR(db[(E1)+(32*N)]), K39XOR(db[(E2)+(32*N)]), K47XOR(db[(E3)+(32*N)]), K52XOR(db[(E4)+(32*N)]), K19XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K51XOR(db[(E0)+(32*N)]), K03XOR(db[(E1)+(32*N)]), K07XOR(db[(E2)+(32*N)]), K22XOR(db[(E3)+(32*N)]), K09XOR(db[(E4)+(32*N)]), K35XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K16XOR(db[59*N]), K44XOR(db[60*N]), K17XOR(db[61*N]), K29XOR(db[62*N]), K21XOR(db[63*N]), K00XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K30XOR(db[55*N]), K24XOR(db[56*N]), K08XOR(db[57*N]), K28XOR(db[58*N]), K43XOR(db[59*N]), K49XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K14XOR(db[(E0)+(32*N)]), K01XOR(db[(E1)+(32*N)]), K10XOR(db[(E2)+(32*N)]), K23XOR(db[(E3)+(32*N)]), K50XOR(db[(E4)+(32*N)]), K02XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(144);
		switch (threadIdx.y) {
		case 0: s1(K32XOR(db[E0]), K11XOR(db[E1]), K53XOR(db[E2]), K48XOR(db[E3]), K13XOR(db[E4]), K40XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K18XOR(db[11*N]), K26XOR(db[12*N]), K27XOR(db[13*N]), K45XOR(db[14*N]), K39XOR(db[15*N]), K06XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K55XOR(db[ 7*N]), K52XOR(db[ 8*N]), K46XOR(db[ 9*N]), K47XOR(db[10*N]), K34XOR(db[11*N]), K19XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K54XOR(db[E0]), K20XOR(db[E1]), K25XOR(db[E2]), K33XOR(db[E3]), K38XOR(db[E4]), K05XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K37XOR(db[E0]), K42XOR(db[E1]), K50XOR(db[E2]), K08XOR(db[E3]), K24XOR(db[E4]), K21XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K02XOR(db[27*N]), K30XOR(db[28*N]), K03XOR(db[29*N]), K15XOR(db[30*N]), K07XOR(db[31*N]), K43XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K16XOR(db[23*N]), K10XOR(db[24*N]), K51XOR(db[25*N]), K14XOR(db[26*N]), K29XOR(db[27*N]), K35XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K00XOR(db[E0]), K44XOR(db[E1]), K49XOR(db[E2]), K09XOR(db[E3]), K36XOR(db[E4]), K17XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(144);
		switch (threadIdx.y) {
		case 0: s1(K18XOR(db[(E0)+(32*N)]), K52XOR(db[(E1)+(32*N)]), K39XOR(db[(E2)+(32*N)]), K34XOR(db[(E3)+(32*N)]), K54XOR(db[(E4)+(32*N)]), K26XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K04XOR(db[43*N]), K12XOR(db[44*N]), K13XOR(db[45*N]), K31XOR(db[46*N]), K25XOR(db[47*N]), K47XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K41XOR(db[39*N]), K38XOR(db[40*N]), K32XOR(db[41*N]), K33XOR(db[42*N]), K20XOR(db[43*N]), K05XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K40XOR(db[(E0)+(32*N)]), K06XOR(db[(E1)+(32*N)]), K11XOR(db[(E2)+(32*N)]), K19XOR(db[(E3)+(32*N)]), K55XOR(db[(E4)+(32*N)]), K46XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K23XOR(db[(E0)+(32*N)]), K28XOR(db[(E1)+(32*N)]), K36XOR(db[(E2)+(32*N)]), K51XOR(db[(E3)+(32*N)]), K10XOR(db[(E4)+(32*N)]), K07XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K17XOR(db[59*N]), K16XOR(db[60*N]), K42XOR(db[61*N]), K01XOR(db[62*N]), K50XOR(db[63*N]), K29XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K02XOR(db[55*N]), K49XOR(db[56*N]), K37XOR(db[57*N]), K00XOR(db[58*N]), K15XOR(db[59*N]), K21XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K43XOR(db[(E0)+(32*N)]), K30XOR(db[(E1)+(32*N)]), K35XOR(db[(E2)+(32*N)]), K24XOR(db[(E3)+(32*N)]), K22XOR(db[(E4)+(32*N)]), K03XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(240);
		switch (threadIdx.y) {
		case 0: s1(K04XOR(db[E0]), K38XOR(db[E1]), K25XOR(db[E2]), K20XOR(db[E3]), K40XOR(db[E4]), K12XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K45XOR(db[11*N]), K53XOR(db[12*N]), K54XOR(db[13*N]), K48XOR(db[14*N]), K11XOR(db[15*N]), K33XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K27XOR(db[ 7*N]), K55XOR(db[ 8*N]), K18XOR(db[ 9*N]), K19XOR(db[10*N]), K06XOR(db[11*N]), K46XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K26XOR(db[E0]), K47XOR(db[E1]), K52XOR(db[E2]), K05XOR(db[E3]), K41XOR(db[E4]), K32XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K09XOR(db[E0]), K14XOR(db[E1]), K22XOR(db[E2]), K37XOR(db[E3]), K49XOR(db[E4]), K50XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K03XOR(db[27*N]), K02XOR(db[28*N]), K28XOR(db[29*N]), K44XOR(db[30*N]), K36XOR(db[31*N]), K15XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K17XOR(db[23*N]), K35XOR(db[24*N]), K23XOR(db[25*N]), K43XOR(db[26*N]), K01XOR(db[27*N]), K07XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K29XOR(db[E0]), K16XOR(db[E1]), K21XOR(db[E2]), K10XOR(db[E3]), K08XOR(db[E4]), K42XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(240);
		switch (threadIdx.y) {
		case 0: s1(K45XOR(db[(E0)+(32*N)]), K55XOR(db[(E1)+(32*N)]), K11XOR(db[(E2)+(32*N)]), K06XOR(db[(E3)+(32*N)]), K26XOR(db[(E4)+(32*N)]), K53XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K31XOR(db[43*N]), K39XOR(db[44*N]), K40XOR(db[45*N]), K34XOR(db[46*N]), K52XOR(db[47*N]), K19XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K13XOR(db[39*N]), K41XOR(db[40*N]), K04XOR(db[41*N]), K05XOR(db[42*N]), K47XOR(db[43*N]), K32XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K12XOR(db[(E0)+(32*N)]), K33XOR(db[(E1)+(32*N)]), K38XOR(db[(E2)+(32*N)]), K46XOR(db[(E3)+(32*N)]), K27XOR(db[(E4)+(32*N)]), K18XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K24XOR(db[(E0)+(32*N)]), K00XOR(db[(E1)+(32*N)]), K08XOR(db[(E2)+(32*N)]), K23XOR(db[(E3)+(32*N)]), K35XOR(db[(E4)+(32*N)]), K36XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K42XOR(db[59*N]), K17XOR(db[60*N]), K14XOR(db[61*N]), K30XOR(db[62*N]), K22XOR(db[63*N]), K01XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K03XOR(db[55*N]), K21XOR(db[56*N]), K09XOR(db[57*N]), K29XOR(db[58*N]), K44XOR(db[59*N]), K50XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K15XOR(db[(E0)+(32*N)]), K02XOR(db[(E1)+(32*N)]), K07XOR(db[(E2)+(32*N)]), K49XOR(db[(E3)+(32*N)]), K51XOR(db[(E4)+(32*N)]), K28XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(336);
		switch (threadIdx.y) {
		case 0: s1(K31XOR(db[E0]), K41XOR(db[E1]), K52XOR(db[E2]), K47XOR(db[E3]), K12XOR(db[E4]), K39XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K48XOR(db[11*N]), K25XOR(db[12*N]), K26XOR(db[13*N]), K20XOR(db[14*N]), K38XOR(db[15*N]), K05XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K54XOR(db[ 7*N]), K27XOR(db[ 8*N]), K45XOR(db[ 9*N]), K46XOR(db[10*N]), K33XOR(db[11*N]), K18XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K53XOR(db[E0]), K19XOR(db[E1]), K55XOR(db[E2]), K32XOR(db[E3]), K13XOR(db[E4]), K04XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K10XOR(db[E0]), K43XOR(db[E1]), K51XOR(db[E2]), K09XOR(db[E3]), K21XOR(db[E4]), K22XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K28XOR(db[27*N]), K03XOR(db[28*N]), K00XOR(db[29*N]), K16XOR(db[30*N]), K08XOR(db[31*N]), K44XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K42XOR(db[23*N]), K07XOR(db[24*N]), K24XOR(db[25*N]), K15XOR(db[26*N]), K30XOR(db[27*N]), K36XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K01XOR(db[E0]), K17XOR(db[E1]), K50XOR(db[E2]), K35XOR(db[E3]), K37XOR(db[E4]), K14XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(336);
		switch (threadIdx.y) {
		case 0: s1(K55XOR(db[(E0)+(32*N)]), K34XOR(db[(E1)+(32*N)]), K45XOR(db[(E2)+(32*N)]), K40XOR(db[(E3)+(32*N)]), K05XOR(db[(E4)+(32*N)]), K32XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K41XOR(db[43*N]), K18XOR(db[44*N]), K19XOR(db[45*N]), K13XOR(db[46*N]), K31XOR(db[47*N]), K53XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K47XOR(db[39*N]), K20XOR(db[40*N]), K38XOR(db[41*N]), K39XOR(db[42*N]), K26XOR(db[43*N]), K11XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K46XOR(db[(E0)+(32*N)]), K12XOR(db[(E1)+(32*N)]), K48XOR(db[(E2)+(32*N)]), K25XOR(db[(E3)+(32*N)]), K06XOR(db[(E4)+(32*N)]), K52XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K03XOR(db[(E0)+(32*N)]), K36XOR(db[(E1)+(32*N)]), K44XOR(db[(E2)+(32*N)]), K02XOR(db[(E3)+(32*N)]), K14XOR(db[(E4)+(32*N)]), K15XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K21XOR(db[59*N]), K49XOR(db[60*N]), K50XOR(db[61*N]), K09XOR(db[62*N]), K01XOR(db[63*N]), K37XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K35XOR(db[55*N]), K00XOR(db[56*N]), K17XOR(db[57*N]), K08XOR(db[58*N]), K23XOR(db[59*N]), K29XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K51XOR(db[(E0)+(32*N)]), K10XOR(db[(E1)+(32*N)]), K43XOR(db[(E2)+(32*N)]), K28XOR(db[(E3)+(32*N)]), K30XOR(db[(E4)+(32*N)]), K07XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(432);
		switch (threadIdx.y) {
		case 0: s1(K41XOR(db[E0]), K20XOR(db[E1]), K31XOR(db[E2]), K26XOR(db[E3]), K46XOR(db[E4]), K18XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K27XOR(db[11*N]), K04XOR(db[12*N]), K05XOR(db[13*N]), K54XOR(db[14*N]), K48XOR(db[15*N]), K39XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K33XOR(db[ 7*N]), K06XOR(db[ 8*N]), K55XOR(db[ 9*N]), K25XOR(db[10*N]), K12XOR(db[11*N]), K52XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K32XOR(db[E0]), K53XOR(db[E1]), K34XOR(db[E2]), K11XOR(db[E3]), K47XOR(db[E4]), K38XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K42XOR(db[E0]), K22XOR(db[E1]), K30XOR(db[E2]), K17XOR(db[E3]), K00XOR(db[E4]), K01XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K07XOR(db[27*N]), K35XOR(db[28*N]), K36XOR(db[29*N]), K24XOR(db[30*N]), K44XOR(db[31*N]), K23XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K21XOR(db[23*N]), K43XOR(db[24*N]), K03XOR(db[25*N]), K51XOR(db[26*N]), K09XOR(db[27*N]), K15XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K37XOR(db[E0]), K49XOR(db[E1]), K29XOR(db[E2]), K14XOR(db[E3]), K16XOR(db[E4]), K50XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(432);
		switch (threadIdx.y) {
		case 0: s1(K27XOR(db[(E0)+(32*N)]), K06XOR(db[(E1)+(32*N)]), K48XOR(db[(E2)+(32*N)]), K12XOR(db[(E3)+(32*N)]), K32XOR(db[(E4)+(32*N)]), K04XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K13XOR(db[43*N]), K45XOR(db[44*N]), K46XOR(db[45*N]), K40XOR(db[46*N]), K34XOR(db[47*N]), K25XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K19XOR(db[39*N]), K47XOR(db[40*N]), K41XOR(db[41*N]), K11XOR(db[42*N]), K53XOR(db[43*N]), K38XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K18XOR(db[(E0)+(32*N)]), K39XOR(db[(E1)+(32*N)]), K20XOR(db[(E2)+(32*N)]), K52XOR(db[(E3)+(32*N)]), K33XOR(db[(E4)+(32*N)]), K55XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K28XOR(db[(E0)+(32*N)]), K08XOR(db[(E1)+(32*N)]), K16XOR(db[(E2)+(32*N)]), K03XOR(db[(E3)+(32*N)]), K43XOR(db[(E4)+(32*N)]), K44XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K50XOR(db[59*N]), K21XOR(db[60*N]), K22XOR(db[61*N]), K10XOR(db[62*N]), K30XOR(db[63*N]), K09XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K07XOR(db[55*N]), K29XOR(db[56*N]), K42XOR(db[57*N]), K37XOR(db[58*N]), K24XOR(db[59*N]), K01XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K23XOR(db[(E0)+(32*N)]), K35XOR(db[(E1)+(32*N)]), K15XOR(db[(E2)+(32*N)]), K00XOR(db[(E3)+(32*N)]), K02XOR(db[(E4)+(32*N)]), K36XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(528);
		switch (threadIdx.y) {
		case 0: s1(K13XOR(db[E0]), K47XOR(db[E1]), K34XOR(db[E2]), K53XOR(db[E3]), K18XOR(db[E4]), K45XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K54XOR(db[11*N]), K31XOR(db[12*N]), K32XOR(db[13*N]), K26XOR(db[14*N]), K20XOR(db[15*N]), K11XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K05XOR(db[ 7*N]), K33XOR(db[ 8*N]), K27XOR(db[ 9*N]), K52XOR(db[10*N]), K39XOR(db[11*N]), K55XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K04XOR(db[E0]), K25XOR(db[E1]), K06XOR(db[E2]), K38XOR(db[E3]), K19XOR(db[E4]), K41XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K14XOR(db[E0]), K51XOR(db[E1]), K02XOR(db[E2]), K42XOR(db[E3]), K29XOR(db[E4]), K30XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K36XOR(db[27*N]), K07XOR(db[28*N]), K08XOR(db[29*N]), K49XOR(db[30*N]), K16XOR(db[31*N]), K24XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K50XOR(db[23*N]), K15XOR(db[24*N]), K28XOR(db[25*N]), K23XOR(db[26*N]), K10XOR(db[27*N]), K44XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K09XOR(db[E0]), K21XOR(db[E1]), K01XOR(db[E2]), K43XOR(db[E3]), K17XOR(db[E4]), K22XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(528);
		switch (threadIdx.y) {
		case 0: s1(K54XOR(db[(E0)+(32*N)]), K33XOR(db[(E1)+(32*N)]), K20XOR(db[(E2)+(32*N)]), K39XOR(db[(E3)+(32*N)]), K04XOR(db[(E4)+(32*N)]), K31XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K40XOR(db[43*N]), K48XOR(db[44*N]), K18XOR(db[45*N]), K12XOR(db[46*N]), K06XOR(db[47*N]), K52XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K46XOR(db[39*N]), K19XOR(db[40*N]), K13XOR(db[41*N]), K38XOR(db[42*N]), K25XOR(db[43*N]), K41XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K45XOR(db[(E0)+(32*N)]), K11XOR(db[(E1)+(32*N)]), K47XOR(db[(E2)+(32*N)]), K55XOR(db[(E3)+(32*N)]), K05XOR(db[(E4)+(32*N)]), K27XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K00XOR(db[(E0)+(32*N)]), K37XOR(db[(E1)+(32*N)]), K17XOR(db[(E2)+(32*N)]), K28XOR(db[(E3)+(32*N)]), K15XOR(db[(E4)+(32*N)]), K16XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K22XOR(db[59*N]), K50XOR(db[60*N]), K51XOR(db[61*N]), K35XOR(db[62*N]), K02XOR(db[63*N]), K10XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K36XOR(db[55*N]), K01XOR(db[56*N]), K14XOR(db[57*N]), K09XOR(db[58*N]), K49XOR(db[59*N]), K30XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K24XOR(db[(E0)+(32*N)]), K07XOR(db[(E1)+(32*N)]), K44XOR(db[(E2)+(32*N)]), K29XOR(db[(E3)+(32*N)]), K03XOR(db[(E4)+(32*N)]), K08XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(624);
		switch (threadIdx.y) {
		case 0: s1(K40XOR(db[E0]), K19XOR(db[E1]), K06XOR(db[E2]), K25XOR(db[E3]), K45XOR(db[E4]), K48XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K26XOR(db[11*N]), K34XOR(db[12*N]), K04XOR(db[13*N]), K53XOR(db[14*N]), K47XOR(db[15*N]), K38XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K32XOR(db[ 7*N]), K05XOR(db[ 8*N]), K54XOR(db[ 9*N]), K55XOR(db[10*N]), K11XOR(db[11*N]), K27XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K31XOR(db[E0]), K52XOR(db[E1]), K33XOR(db[E2]), K41XOR(db[E3]), K46XOR(db[E4]), K13XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K43XOR(db[E0]), K23XOR(db[E1]), K03XOR(db[E2]), K14XOR(db[E3]), K01XOR(db[E4]), K02XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K08XOR(db[27*N]), K36XOR(db[28*N]), K37XOR(db[29*N]), K21XOR(db[30*N]), K17XOR(db[31*N]), K49XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K22XOR(db[23*N]), K44XOR(db[24*N]), K00XOR(db[25*N]), K24XOR(db[26*N]), K35XOR(db[27*N]), K16XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K10XOR(db[E0]), K50XOR(db[E1]), K30XOR(db[E2]), K15XOR(db[E3]), K42XOR(db[E4]), K51XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();

		// ROUND_B(624);
		switch (threadIdx.y) {
		case 0: s1(K26XOR(db[(E0)+(32*N)]), K05XOR(db[(E1)+(32*N)]), K47XOR(db[(E2)+(32*N)]), K11XOR(db[(E3)+(32*N)]), K31XOR(db[(E4)+(32*N)]), K34XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		        s4(K12XOR(db[43*N]), K20XOR(db[44*N]), K45XOR(db[45*N]), K39XOR(db[46*N]), K33XOR(db[47*N]), K55XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); break;
		case 1: s3(K18XOR(db[39*N]), K46XOR(db[40*N]), K40XOR(db[41*N]), K41XOR(db[42*N]), K52XOR(db[43*N]), K13XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		        s2(K48XOR(db[(E0)+(32*N)]), K38XOR(db[(E1)+(32*N)]), K19XOR(db[(E2)+(32*N)]), K27XOR(db[(E3)+(32*N)]), K32XOR(db[(E4)+(32*N)]), K54XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); break;
		case 2: s5(K29XOR(db[(E0)+(32*N)]), K09XOR(db[(E1)+(32*N)]), K42XOR(db[(E2)+(32*N)]), K00XOR(db[(E3)+(32*N)]), K44XOR(db[(E4)+(32*N)]), K17XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		        s8(K51XOR(db[59*N]), K22XOR(db[60*N]), K23XOR(db[61*N]), K07XOR(db[62*N]), K03XOR(db[63*N]), K35XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); break;
		case 3: s7(K08XOR(db[55*N]), K30XOR(db[56*N]), K43XOR(db[57*N]), K10XOR(db[58*N]), K21XOR(db[59*N]), K02XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
		        s6(K49XOR(db[(E0)+(32*N)]), K36XOR(db[(E1)+(32*N)]), K16XOR(db[(E2)+(32*N)]), K01XOR(db[(E3)+(32*N)]), K28XOR(db[(E4)+(32*N)]), K37XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); break;
		}
		__syncthreads();

		// ROUND_A(720);
		switch (threadIdx.y) {
		case 0: s1(K19XOR(db[E0]), K53XOR(db[E1]), K40XOR(db[E2]), K04XOR(db[E3]), K55XOR(db[E4]), K27XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		        s4(K05XOR(db[11*N]), K13XOR(db[12*N]), K38XOR(db[13*N]), K32XOR(db[14*N]), K26XOR(db[15*N]), K48XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); break;
		case 1: s3(K11XOR(db[ 7*N]), K39XOR(db[ 8*N]), K33XOR(db[ 9*N]), K34XOR(db[10*N]), K45XOR(db[11*N]), K06XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		        s2(K41XOR(db[E0]), K31XOR(db[E1]), K12XOR(db[E2]), K20XOR(db[E3]), K25XOR(db[E4]), K47XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); break;
		case 2: s5(K22XOR(db[E0]), K02XOR(db[E1]), K35XOR(db[E2]), K50XOR(db[E3]), K37XOR(db[E4]), K10XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		        s8(K44XOR(db[27*N]), K15XOR(db[28*N]), K16XOR(db[29*N]), K00XOR(db[30*N]), K49XOR(db[31*N]), K28XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); break;
		case 3: s7(K01XOR(db[23*N]), K23XOR(db[24*N]), K36XOR(db[25*N]), K03XOR(db[26*N]), K14XOR(db[27*N]), K24XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		        s6(K42XOR(db[E0]), K29XOR(db[E1]), K09XOR(db[E2]), K51XOR(db[E3]), K21XOR(db[E4]), K30XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); break;
		}
		__syncthreads();
	}

#else

	// For some reason, this routine works better on GTX580.
#pragma unroll 1 // Do not unroll.
	for (int i = 0; i < 13; ++i) {
		switch (threadIdx.y) {
		case 0: 
			s1(K12XOR(db[E0]), K46XOR(db[E1]), K33XOR(db[E2]), K52XOR(db[E3]), K48XOR(db[E4]), K20XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		    s4(K53XOR(db[11*N]), K06XOR(db[12*N]), K31XOR(db[13*N]), K25XOR(db[14*N]), K19XOR(db[15*N]), K41XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K05XOR(db[(E0)+(32*N)]), K39XOR(db[(E1)+(32*N)]), K26XOR(db[(E2)+(32*N)]), K45XOR(db[(E3)+(32*N)]), K41XOR(db[(E4)+(32*N)]), K13XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		    s4(K46XOR(db[43*N]), K54XOR(db[44*N]), K55XOR(db[45*N]), K18XOR(db[46*N]), K12XOR(db[47*N]), K34XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]);
			__syncthreads();
			s1(K46XOR(db[E0]), K25XOR(db[E1]), K12XOR(db[E2]), K31XOR(db[E3]), K27XOR(db[E4]), K54XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
	        s4(K32XOR(db[11*N]), K40XOR(db[12*N]), K41XOR(db[13*N]), K04XOR(db[14*N]), K53XOR(db[15*N]), K20XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]);
			__syncthreads();
			s1(K32XOR(db[(E0)+(32*N)]), K11XOR(db[(E1)+(32*N)]), K53XOR(db[(E2)+(32*N)]), K48XOR(db[(E3)+(32*N)]), K13XOR(db[(E4)+(32*N)]), K40XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
		    s4(K18XOR(db[43*N]), K26XOR(db[44*N]), K27XOR(db[45*N]), K45XOR(db[46*N]), K39XOR(db[47*N]), K06XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]);
			__syncthreads();
			s1(K18XOR(db[E0]), K52XOR(db[E1]), K39XOR(db[E2]), K34XOR(db[E3]), K54XOR(db[E4]), K26XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
		    s4(K04XOR(db[11*N]), K12XOR(db[12*N]), K13XOR(db[13*N]), K31XOR(db[14*N]), K25XOR(db[15*N]), K47XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]);
			__syncthreads();
			s1(K04XOR(db[(E0)+(32*N)]), K38XOR(db[(E1)+(32*N)]), K25XOR(db[(E2)+(32*N)]), K20XOR(db[(E3)+(32*N)]), K40XOR(db[(E4)+(32*N)]), K12XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K45XOR(db[43*N]), K53XOR(db[44*N]), K54XOR(db[45*N]), K48XOR(db[46*N]), K11XOR(db[47*N]), K33XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K45XOR(db[E0]), K55XOR(db[E1]), K11XOR(db[E2]), K06XOR(db[E3]), K26XOR(db[E4]), K53XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K31XOR(db[11*N]), K39XOR(db[12*N]), K40XOR(db[13*N]), K34XOR(db[14*N]), K52XOR(db[15*N]), K19XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K31XOR(db[(E0)+(32*N)]), K41XOR(db[(E1)+(32*N)]), K52XOR(db[(E2)+(32*N)]), K47XOR(db[(E3)+(32*N)]), K12XOR(db[(E4)+(32*N)]), K39XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K48XOR(db[43*N]), K25XOR(db[44*N]), K26XOR(db[45*N]), K20XOR(db[46*N]), K38XOR(db[47*N]), K05XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K55XOR(db[E0]), K34XOR(db[E1]), K45XOR(db[E2]), K40XOR(db[E3]), K05XOR(db[E4]), K32XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K41XOR(db[11*N]), K18XOR(db[12*N]), K19XOR(db[13*N]), K13XOR(db[14*N]), K31XOR(db[15*N]), K53XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K41XOR(db[(E0)+(32*N)]), K20XOR(db[(E1)+(32*N)]), K31XOR(db[(E2)+(32*N)]), K26XOR(db[(E3)+(32*N)]), K46XOR(db[(E4)+(32*N)]), K18XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K27XOR(db[43*N]), K04XOR(db[44*N]), K05XOR(db[45*N]), K54XOR(db[46*N]), K48XOR(db[47*N]), K39XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K27XOR(db[E0]), K06XOR(db[E1]), K48XOR(db[E2]), K12XOR(db[E3]), K32XOR(db[E4]), K04XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K13XOR(db[11*N]), K45XOR(db[12*N]), K46XOR(db[13*N]), K40XOR(db[14*N]), K34XOR(db[15*N]), K25XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K13XOR(db[(E0)+(32*N)]), K47XOR(db[(E1)+(32*N)]), K34XOR(db[(E2)+(32*N)]), K53XOR(db[(E3)+(32*N)]), K18XOR(db[(E4)+(32*N)]), K45XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K54XOR(db[43*N]), K31XOR(db[44*N]), K32XOR(db[45*N]), K26XOR(db[46*N]), K20XOR(db[47*N]), K11XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K54XOR(db[E0]), K33XOR(db[E1]), K20XOR(db[E2]), K39XOR(db[E3]), K04XOR(db[E4]), K31XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K40XOR(db[11*N]), K48XOR(db[12*N]), K18XOR(db[13*N]), K12XOR(db[14*N]), K06XOR(db[15*N]), K52XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K40XOR(db[(E0)+(32*N)]), K19XOR(db[(E1)+(32*N)]), K06XOR(db[(E2)+(32*N)]), K25XOR(db[(E3)+(32*N)]), K45XOR(db[(E4)+(32*N)]), K48XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K26XOR(db[43*N]), K34XOR(db[44*N]), K04XOR(db[45*N]), K53XOR(db[46*N]), K47XOR(db[47*N]), K38XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K26XOR(db[E0]), K05XOR(db[E1]), K47XOR(db[E2]), K11XOR(db[E3]), K31XOR(db[E4]), K34XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K12XOR(db[11*N]), K20XOR(db[12*N]), K45XOR(db[13*N]), K39XOR(db[14*N]), K33XOR(db[15*N]), K55XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K19XOR(db[(E0)+(32*N)]), K53XOR(db[(E1)+(32*N)]), K40XOR(db[(E2)+(32*N)]), K04XOR(db[(E3)+(32*N)]), K55XOR(db[(E4)+(32*N)]), K27XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K05XOR(db[43*N]), K13XOR(db[44*N]), K38XOR(db[45*N]), K32XOR(db[46*N]), K26XOR(db[47*N]), K48XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			break;
		case 1: 
			s3(K04XOR(db[ 7*N]), K32XOR(db[ 8*N]), K26XOR(db[ 9*N]), K27XOR(db[10*N]), K38XOR(db[11*N]), K54XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		    s2(K34XOR(db[E0]), K55XOR(db[E1]), K05XOR(db[E2]), K13XOR(db[E3]), K18XOR(db[E4]), K40XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K52XOR(db[39*N]), K25XOR(db[40*N]), K19XOR(db[41*N]), K20XOR(db[42*N]), K31XOR(db[43*N]), K47XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		    s2(K27XOR(db[(E0)+(32*N)]), K48XOR(db[(E1)+(32*N)]), K53XOR(db[(E2)+(32*N)]), K06XOR(db[(E3)+(32*N)]), K11XOR(db[(E4)+(32*N)]), K33XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K38XOR(db[ 7*N]), K11XOR(db[ 8*N]), K05XOR(db[ 9*N]), K06XOR(db[10*N]), K48XOR(db[11*N]), K33XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
	        s2(K13XOR(db[E0]), K34XOR(db[E1]), K39XOR(db[E2]), K47XOR(db[E3]), K52XOR(db[E4]), K19XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]);
			__syncthreads();
			s3(K55XOR(db[39*N]), K52XOR(db[40*N]), K46XOR(db[41*N]), K47XOR(db[42*N]), K34XOR(db[43*N]), K19XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
		    s2(K54XOR(db[(E0)+(32*N)]), K20XOR(db[(E1)+(32*N)]), K25XOR(db[(E2)+(32*N)]), K33XOR(db[(E3)+(32*N)]), K38XOR(db[(E4)+(32*N)]), K05XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]);
			__syncthreads();
			s3(K41XOR(db[ 7*N]), K38XOR(db[ 8*N]), K32XOR(db[ 9*N]), K33XOR(db[10*N]), K20XOR(db[11*N]), K05XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
		    s2(K40XOR(db[E0]), K06XOR(db[E1]), K11XOR(db[E2]), K19XOR(db[E3]), K55XOR(db[E4]), K46XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]);
			__syncthreads();
			s3(K27XOR(db[39*N]), K55XOR(db[40*N]), K18XOR(db[41*N]), K19XOR(db[42*N]), K06XOR(db[43*N]), K46XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K26XOR(db[(E0)+(32*N)]), K47XOR(db[(E1)+(32*N)]), K52XOR(db[(E2)+(32*N)]), K05XOR(db[(E3)+(32*N)]), K41XOR(db[(E4)+(32*N)]), K32XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K13XOR(db[ 7*N]), K41XOR(db[ 8*N]), K04XOR(db[ 9*N]), K05XOR(db[10*N]), K47XOR(db[11*N]), K32XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K12XOR(db[E0]), K33XOR(db[E1]), K38XOR(db[E2]), K46XOR(db[E3]), K27XOR(db[E4]), K18XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K54XOR(db[39*N]), K27XOR(db[40*N]), K45XOR(db[41*N]), K46XOR(db[42*N]), K33XOR(db[43*N]), K18XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K53XOR(db[(E0)+(32*N)]), K19XOR(db[(E1)+(32*N)]), K55XOR(db[(E2)+(32*N)]), K32XOR(db[(E3)+(32*N)]), K13XOR(db[(E4)+(32*N)]), K04XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K47XOR(db[ 7*N]), K20XOR(db[ 8*N]), K38XOR(db[ 9*N]), K39XOR(db[10*N]), K26XOR(db[11*N]), K11XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K46XOR(db[E0]), K12XOR(db[E1]), K48XOR(db[E2]), K25XOR(db[E3]), K06XOR(db[E4]), K52XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K33XOR(db[39*N]), K06XOR(db[40*N]), K55XOR(db[41*N]), K25XOR(db[42*N]), K12XOR(db[43*N]), K52XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K32XOR(db[(E0)+(32*N)]), K53XOR(db[(E1)+(32*N)]), K34XOR(db[(E2)+(32*N)]), K11XOR(db[(E3)+(32*N)]), K47XOR(db[(E4)+(32*N)]), K38XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K19XOR(db[ 7*N]), K47XOR(db[ 8*N]), K41XOR(db[ 9*N]), K11XOR(db[10*N]), K53XOR(db[11*N]), K38XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K18XOR(db[E0]), K39XOR(db[E1]), K20XOR(db[E2]), K52XOR(db[E3]), K33XOR(db[E4]), K55XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K05XOR(db[39*N]), K33XOR(db[40*N]), K27XOR(db[41*N]), K52XOR(db[42*N]), K39XOR(db[43*N]), K55XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K04XOR(db[(E0)+(32*N)]), K25XOR(db[(E1)+(32*N)]), K06XOR(db[(E2)+(32*N)]), K38XOR(db[(E3)+(32*N)]), K19XOR(db[(E4)+(32*N)]), K41XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K46XOR(db[ 7*N]), K19XOR(db[ 8*N]), K13XOR(db[ 9*N]), K38XOR(db[10*N]), K25XOR(db[11*N]), K41XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K45XOR(db[E0]), K11XOR(db[E1]), K47XOR(db[E2]), K55XOR(db[E3]), K05XOR(db[E4]), K27XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K32XOR(db[39*N]), K05XOR(db[40*N]), K54XOR(db[41*N]), K55XOR(db[42*N]), K11XOR(db[43*N]), K27XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K31XOR(db[(E0)+(32*N)]), K52XOR(db[(E1)+(32*N)]), K33XOR(db[(E2)+(32*N)]), K41XOR(db[(E3)+(32*N)]), K46XOR(db[(E4)+(32*N)]), K13XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K18XOR(db[ 7*N]), K46XOR(db[ 8*N]), K40XOR(db[ 9*N]), K41XOR(db[10*N]), K52XOR(db[11*N]), K13XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K48XOR(db[E0]), K38XOR(db[E1]), K19XOR(db[E2]), K27XOR(db[E3]), K32XOR(db[E4]), K54XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K11XOR(db[39*N]), K39XOR(db[40*N]), K33XOR(db[41*N]), K34XOR(db[42*N]), K45XOR(db[43*N]), K06XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K41XOR(db[(E0)+(32*N)]), K31XOR(db[(E1)+(32*N)]), K12XOR(db[(E2)+(32*N)]), K20XOR(db[(E3)+(32*N)]), K25XOR(db[(E4)+(32*N)]), K47XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			break;
		case 2: 
			s5(K15XOR(db[E0]), K24XOR(db[E1]), K28XOR(db[E2]), K43XOR(db[E3]), K30XOR(db[E4]), K03XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K37XOR(db[27*N]), K08XOR(db[28*N]), K09XOR(db[29*N]), K50XOR(db[30*N]), K42XOR(db[31*N]), K21XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]);
			__syncthreads();
			s5(K08XOR(db[(E0)+(32*N)]), K17XOR(db[(E1)+(32*N)]), K21XOR(db[(E2)+(32*N)]), K36XOR(db[(E3)+(32*N)]), K23XOR(db[(E4)+(32*N)]), K49XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K30XOR(db[59*N]), K01XOR(db[60*N]), K02XOR(db[61*N]), K43XOR(db[62*N]), K35XOR(db[63*N]), K14XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]);
			__syncthreads();
			s5(K51XOR(db[E0]), K03XOR(db[E1]), K07XOR(db[E2]), K22XOR(db[E3]), K09XOR(db[E4]), K35XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
	        s8(K16XOR(db[27*N]), K44XOR(db[28*N]), K17XOR(db[29*N]), K29XOR(db[30*N]), K21XOR(db[31*N]), K00XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]);
			__syncthreads();
			s5(K37XOR(db[(E0)+(32*N)]), K42XOR(db[(E1)+(32*N)]), K50XOR(db[(E2)+(32*N)]), K08XOR(db[(E3)+(32*N)]), K24XOR(db[(E4)+(32*N)]), K21XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
		    s8(K02XOR(db[59*N]), K30XOR(db[60*N]), K03XOR(db[61*N]), K15XOR(db[62*N]), K07XOR(db[63*N]), K43XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]);
			__syncthreads();
			s5(K23XOR(db[E0]), K28XOR(db[E1]), K36XOR(db[E2]), K51XOR(db[E3]), K10XOR(db[E4]), K07XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
		    s8(K17XOR(db[27*N]), K16XOR(db[28*N]), K42XOR(db[29*N]), K01XOR(db[30*N]), K50XOR(db[31*N]), K29XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]);
			__syncthreads();
			s5(K09XOR(db[(E0)+(32*N)]), K14XOR(db[(E1)+(32*N)]), K22XOR(db[(E2)+(32*N)]), K37XOR(db[(E3)+(32*N)]), K49XOR(db[(E4)+(32*N)]), K50XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K03XOR(db[59*N]), K02XOR(db[60*N]), K28XOR(db[61*N]), K44XOR(db[62*N]), K36XOR(db[63*N]), K15XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K24XOR(db[E0]), K00XOR(db[E1]), K08XOR(db[E2]), K23XOR(db[E3]), K35XOR(db[E4]), K36XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K42XOR(db[27*N]), K17XOR(db[28*N]), K14XOR(db[29*N]), K30XOR(db[30*N]), K22XOR(db[31*N]), K01XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K10XOR(db[(E0)+(32*N)]), K43XOR(db[(E1)+(32*N)]), K51XOR(db[(E2)+(32*N)]), K09XOR(db[(E3)+(32*N)]), K21XOR(db[(E4)+(32*N)]), K22XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K28XOR(db[59*N]), K03XOR(db[60*N]), K00XOR(db[61*N]), K16XOR(db[62*N]), K08XOR(db[63*N]), K44XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K03XOR(db[E0]), K36XOR(db[E1]), K44XOR(db[E2]), K02XOR(db[E3]), K14XOR(db[E4]), K15XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K21XOR(db[27*N]), K49XOR(db[28*N]), K50XOR(db[29*N]), K09XOR(db[30*N]), K01XOR(db[31*N]), K37XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K42XOR(db[(E0)+(32*N)]), K22XOR(db[(E1)+(32*N)]), K30XOR(db[(E2)+(32*N)]), K17XOR(db[(E3)+(32*N)]), K00XOR(db[(E4)+(32*N)]), K01XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K07XOR(db[59*N]), K35XOR(db[60*N]), K36XOR(db[61*N]), K24XOR(db[62*N]), K44XOR(db[63*N]), K23XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K28XOR(db[E0]), K08XOR(db[E1]), K16XOR(db[E2]), K03XOR(db[E3]), K43XOR(db[E4]), K44XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K50XOR(db[27*N]), K21XOR(db[28*N]), K22XOR(db[29*N]), K10XOR(db[30*N]), K30XOR(db[31*N]), K09XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K14XOR(db[(E0)+(32*N)]), K51XOR(db[(E1)+(32*N)]), K02XOR(db[(E2)+(32*N)]), K42XOR(db[(E3)+(32*N)]), K29XOR(db[(E4)+(32*N)]), K30XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K36XOR(db[59*N]), K07XOR(db[60*N]), K08XOR(db[61*N]), K49XOR(db[62*N]), K16XOR(db[63*N]), K24XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K00XOR(db[E0]), K37XOR(db[E1]), K17XOR(db[E2]), K28XOR(db[E3]), K15XOR(db[E4]), K16XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K22XOR(db[27*N]), K50XOR(db[28*N]), K51XOR(db[29*N]), K35XOR(db[30*N]), K02XOR(db[31*N]), K10XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K43XOR(db[(E0)+(32*N)]), K23XOR(db[(E1)+(32*N)]), K03XOR(db[(E2)+(32*N)]), K14XOR(db[(E3)+(32*N)]), K01XOR(db[(E4)+(32*N)]), K02XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K08XOR(db[59*N]), K36XOR(db[60*N]), K37XOR(db[61*N]), K21XOR(db[62*N]), K17XOR(db[63*N]), K49XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K29XOR(db[E0]), K09XOR(db[E1]), K42XOR(db[E2]), K00XOR(db[E3]), K44XOR(db[E4]), K17XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K51XOR(db[27*N]), K22XOR(db[28*N]), K23XOR(db[29*N]), K07XOR(db[30*N]), K03XOR(db[31*N]), K35XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K22XOR(db[(E0)+(32*N)]), K02XOR(db[(E1)+(32*N)]), K35XOR(db[(E2)+(32*N)]), K50XOR(db[(E3)+(32*N)]), K37XOR(db[(E4)+(32*N)]), K10XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K44XOR(db[59*N]), K15XOR(db[60*N]), K16XOR(db[61*N]), K00XOR(db[62*N]), K49XOR(db[63*N]), K28XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			break;
		case 3: 
			s7(K51XOR(db[23*N]), K16XOR(db[24*N]), K29XOR(db[25*N]), K49XOR(db[26*N]), K07XOR(db[27*N]), K17XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K35XOR(db[E0]), K22XOR(db[E1]), K02XOR(db[E2]), K44XOR(db[E3]), K14XOR(db[E4]), K23XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K44XOR(db[55*N]), K09XOR(db[56*N]), K22XOR(db[57*N]), K42XOR(db[58*N]), K00XOR(db[59*N]), K10XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K28XOR(db[(E0)+(32*N)]), K15XOR(db[(E1)+(32*N)]), K24XOR(db[(E2)+(32*N)]), K37XOR(db[(E3)+(32*N)]), K07XOR(db[(E4)+(32*N)]), K16XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]);
			__syncthreads();
			s7(K30XOR(db[23*N]), K24XOR(db[24*N]), K08XOR(db[25*N]), K28XOR(db[26*N]), K43XOR(db[27*N]), K49XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
	        s6(K14XOR(db[E0]), K01XOR(db[E1]), K10XOR(db[E2]), K23XOR(db[E3]), K50XOR(db[E4]), K02XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]);
			__syncthreads();
			s7(K16XOR(db[55*N]), K10XOR(db[56*N]), K51XOR(db[57*N]), K14XOR(db[58*N]), K29XOR(db[59*N]), K35XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K00XOR(db[(E0)+(32*N)]), K44XOR(db[(E1)+(32*N)]), K49XOR(db[(E2)+(32*N)]), K09XOR(db[(E3)+(32*N)]), K36XOR(db[(E4)+(32*N)]), K17XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]);
			__syncthreads();
			s7(K02XOR(db[23*N]), K49XOR(db[24*N]), K37XOR(db[25*N]), K00XOR(db[26*N]), K15XOR(db[27*N]), K21XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
		    s6(K43XOR(db[E0]), K30XOR(db[E1]), K35XOR(db[E2]), K24XOR(db[E3]), K22XOR(db[E4]), K03XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]);
			__syncthreads();
			s7(K17XOR(db[55*N]), K35XOR(db[56*N]), K23XOR(db[57*N]), K43XOR(db[58*N]), K01XOR(db[59*N]), K07XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K29XOR(db[(E0)+(32*N)]), K16XOR(db[(E1)+(32*N)]), K21XOR(db[(E2)+(32*N)]), K10XOR(db[(E3)+(32*N)]), K08XOR(db[(E4)+(32*N)]), K42XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K03XOR(db[23*N]), K21XOR(db[24*N]), K09XOR(db[25*N]), K29XOR(db[26*N]), K44XOR(db[27*N]), K50XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K15XOR(db[E0]), K02XOR(db[E1]), K07XOR(db[E2]), K49XOR(db[E3]), K51XOR(db[E4]), K28XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K42XOR(db[55*N]), K07XOR(db[56*N]), K24XOR(db[57*N]), K15XOR(db[58*N]), K30XOR(db[59*N]), K36XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K01XOR(db[(E0)+(32*N)]), K17XOR(db[(E1)+(32*N)]), K50XOR(db[(E2)+(32*N)]), K35XOR(db[(E3)+(32*N)]), K37XOR(db[(E4)+(32*N)]), K14XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K35XOR(db[23*N]), K00XOR(db[24*N]), K17XOR(db[25*N]), K08XOR(db[26*N]), K23XOR(db[27*N]), K29XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K51XOR(db[E0]), K10XOR(db[E1]), K43XOR(db[E2]), K28XOR(db[E3]), K30XOR(db[E4]), K07XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K21XOR(db[55*N]), K43XOR(db[56*N]), K03XOR(db[57*N]), K51XOR(db[58*N]), K09XOR(db[59*N]), K15XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K37XOR(db[(E0)+(32*N)]), K49XOR(db[(E1)+(32*N)]), K29XOR(db[(E2)+(32*N)]), K14XOR(db[(E3)+(32*N)]), K16XOR(db[(E4)+(32*N)]), K50XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K07XOR(db[23*N]), K29XOR(db[24*N]), K42XOR(db[25*N]), K37XOR(db[26*N]), K24XOR(db[27*N]), K01XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K23XOR(db[E0]), K35XOR(db[E1]), K15XOR(db[E2]), K00XOR(db[E3]), K02XOR(db[E4]), K36XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K50XOR(db[55*N]), K15XOR(db[56*N]), K28XOR(db[57*N]), K23XOR(db[58*N]), K10XOR(db[59*N]), K44XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K09XOR(db[(E0)+(32*N)]), K21XOR(db[(E1)+(32*N)]), K01XOR(db[(E2)+(32*N)]), K43XOR(db[(E3)+(32*N)]), K17XOR(db[(E4)+(32*N)]), K22XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K36XOR(db[23*N]), K01XOR(db[24*N]), K14XOR(db[25*N]), K09XOR(db[26*N]), K49XOR(db[27*N]), K30XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K24XOR(db[E0]), K07XOR(db[E1]), K44XOR(db[E2]), K29XOR(db[E3]), K03XOR(db[E4]), K08XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K22XOR(db[55*N]), K44XOR(db[56*N]), K00XOR(db[57*N]), K24XOR(db[58*N]), K35XOR(db[59*N]), K16XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K10XOR(db[(E0)+(32*N)]), K50XOR(db[(E1)+(32*N)]), K30XOR(db[(E2)+(32*N)]), K15XOR(db[(E3)+(32*N)]), K42XOR(db[(E4)+(32*N)]), K51XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K08XOR(db[23*N]), K30XOR(db[24*N]), K43XOR(db[25*N]), K10XOR(db[26*N]), K21XOR(db[27*N]), K02XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K49XOR(db[E0]), K36XOR(db[E1]), K16XOR(db[E2]), K01XOR(db[E3]), K28XOR(db[E4]), K37XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K01XOR(db[55*N]), K23XOR(db[56*N]), K36XOR(db[57*N]), K03XOR(db[58*N]), K14XOR(db[59*N]), K24XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K42XOR(db[(E0)+(32*N)]), K29XOR(db[(E1)+(32*N)]), K09XOR(db[(E2)+(32*N)]), K51XOR(db[(E3)+(32*N)]), K21XOR(db[(E4)+(32*N)]), K30XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			break;
		}
		__syncthreads();

		if (i >= 12)
			break;

		// ROUND_B(-48);
		switch (threadIdx.y) {
		case 0:
			s1(K12XOR(db[(E0)+(32*N)]), K46XOR(db[(E1)+(32*N)]), K33XOR(db[(E2)+(32*N)]), K52XOR(db[(E3)+(32*N)]), K48XOR(db[(E4)+(32*N)]), K20XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K53XOR(db[43*N]), K06XOR(db[44*N]), K31XOR(db[45*N]), K25XOR(db[46*N]), K19XOR(db[47*N]), K41XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K05XOR(db[E0]), K39XOR(db[E1]), K26XOR(db[E2]), K45XOR(db[E3]), K41XOR(db[E4]), K13XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K46XOR(db[11*N]), K54XOR(db[12*N]), K55XOR(db[13*N]), K18XOR(db[14*N]), K12XOR(db[15*N]), K34XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K46XOR(db[(E0)+(32*N)]), K25XOR(db[(E1)+(32*N)]), K12XOR(db[(E2)+(32*N)]), K31XOR(db[(E3)+(32*N)]), K27XOR(db[(E4)+(32*N)]), K54XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K32XOR(db[43*N]), K40XOR(db[44*N]), K41XOR(db[45*N]), K04XOR(db[46*N]), K53XOR(db[47*N]), K20XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K32XOR(db[E0]), K11XOR(db[E1]), K53XOR(db[E2]), K48XOR(db[E3]), K13XOR(db[E4]), K40XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K18XOR(db[11*N]), K26XOR(db[12*N]), K27XOR(db[13*N]), K45XOR(db[14*N]), K39XOR(db[15*N]), K06XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K18XOR(db[(E0)+(32*N)]), K52XOR(db[(E1)+(32*N)]), K39XOR(db[(E2)+(32*N)]), K34XOR(db[(E3)+(32*N)]), K54XOR(db[(E4)+(32*N)]), K26XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K04XOR(db[43*N]), K12XOR(db[44*N]), K13XOR(db[45*N]), K31XOR(db[46*N]), K25XOR(db[47*N]), K47XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K04XOR(db[E0]), K38XOR(db[E1]), K25XOR(db[E2]), K20XOR(db[E3]), K40XOR(db[E4]), K12XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K45XOR(db[11*N]), K53XOR(db[12*N]), K54XOR(db[13*N]), K48XOR(db[14*N]), K11XOR(db[15*N]), K33XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K45XOR(db[(E0)+(32*N)]), K55XOR(db[(E1)+(32*N)]), K11XOR(db[(E2)+(32*N)]), K06XOR(db[(E3)+(32*N)]), K26XOR(db[(E4)+(32*N)]), K53XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K31XOR(db[43*N]), K39XOR(db[44*N]), K40XOR(db[45*N]), K34XOR(db[46*N]), K52XOR(db[47*N]), K19XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K31XOR(db[E0]), K41XOR(db[E1]), K52XOR(db[E2]), K47XOR(db[E3]), K12XOR(db[E4]), K39XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K48XOR(db[11*N]), K25XOR(db[12*N]), K26XOR(db[13*N]), K20XOR(db[14*N]), K38XOR(db[15*N]), K05XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K55XOR(db[(E0)+(32*N)]), K34XOR(db[(E1)+(32*N)]), K45XOR(db[(E2)+(32*N)]), K40XOR(db[(E3)+(32*N)]), K05XOR(db[(E4)+(32*N)]), K32XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K41XOR(db[43*N]), K18XOR(db[44*N]), K19XOR(db[45*N]), K13XOR(db[46*N]), K31XOR(db[47*N]), K53XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K41XOR(db[E0]), K20XOR(db[E1]), K31XOR(db[E2]), K26XOR(db[E3]), K46XOR(db[E4]), K18XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K27XOR(db[11*N]), K04XOR(db[12*N]), K05XOR(db[13*N]), K54XOR(db[14*N]), K48XOR(db[15*N]), K39XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K27XOR(db[(E0)+(32*N)]), K06XOR(db[(E1)+(32*N)]), K48XOR(db[(E2)+(32*N)]), K12XOR(db[(E3)+(32*N)]), K32XOR(db[(E4)+(32*N)]), K04XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K13XOR(db[43*N]), K45XOR(db[44*N]), K46XOR(db[45*N]), K40XOR(db[46*N]), K34XOR(db[47*N]), K25XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K13XOR(db[E0]), K47XOR(db[E1]), K34XOR(db[E2]), K53XOR(db[E3]), K18XOR(db[E4]), K45XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K54XOR(db[11*N]), K31XOR(db[12*N]), K32XOR(db[13*N]), K26XOR(db[14*N]), K20XOR(db[15*N]), K11XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K54XOR(db[(E0)+(32*N)]), K33XOR(db[(E1)+(32*N)]), K20XOR(db[(E2)+(32*N)]), K39XOR(db[(E3)+(32*N)]), K04XOR(db[(E4)+(32*N)]), K31XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K40XOR(db[43*N]), K48XOR(db[44*N]), K18XOR(db[45*N]), K12XOR(db[46*N]), K06XOR(db[47*N]), K52XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K40XOR(db[E0]), K19XOR(db[E1]), K06XOR(db[E2]), K25XOR(db[E3]), K45XOR(db[E4]), K48XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K26XOR(db[11*N]), K34XOR(db[12*N]), K04XOR(db[13*N]), K53XOR(db[14*N]), K47XOR(db[15*N]), K38XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			__syncthreads();
			s1(K26XOR(db[(E0)+(32*N)]), K05XOR(db[(E1)+(32*N)]), K47XOR(db[(E2)+(32*N)]), K11XOR(db[(E3)+(32*N)]), K31XOR(db[(E4)+(32*N)]), K34XOR(db[(E5)+(32*N)]), &db[ 8*N], &db[16*N], &db[22*N], &db[30*N]);
			s4(K12XOR(db[43*N]), K20XOR(db[44*N]), K45XOR(db[45*N]), K39XOR(db[46*N]), K33XOR(db[47*N]), K55XOR(db[48*N]), &db[25*N], &db[19*N], &db[ 9*N], &db[ 0*N]); 
			__syncthreads();
			s1(K19XOR(db[E0]), K53XOR(db[E1]), K40XOR(db[E2]), K04XOR(db[E3]), K55XOR(db[E4]), K27XOR(db[E5]), &db[40*N], &db[48*N], &db[54*N], &db[62*N]);
			s4(K05XOR(db[11*N]), K13XOR(db[12*N]), K38XOR(db[13*N]), K32XOR(db[14*N]), K26XOR(db[15*N]), K48XOR(db[16*N]), &db[57*N], &db[51*N], &db[41*N], &db[32*N]); 
			break;
		case 1:
			s3(K04XOR(db[39*N]), K32XOR(db[40*N]), K26XOR(db[41*N]), K27XOR(db[42*N]), K38XOR(db[43*N]), K54XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K34XOR(db[(E0)+(32*N)]), K55XOR(db[(E1)+(32*N)]), K05XOR(db[(E2)+(32*N)]), K13XOR(db[(E3)+(32*N)]), K18XOR(db[(E4)+(32*N)]), K40XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K52XOR(db[ 7*N]), K25XOR(db[ 8*N]), K19XOR(db[ 9*N]), K20XOR(db[10*N]), K31XOR(db[11*N]), K47XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K27XOR(db[E0]), K48XOR(db[E1]), K53XOR(db[E2]), K06XOR(db[E3]), K11XOR(db[E4]), K33XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K38XOR(db[39*N]), K11XOR(db[40*N]), K05XOR(db[41*N]), K06XOR(db[42*N]), K48XOR(db[43*N]), K33XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K13XOR(db[(E0)+(32*N)]), K34XOR(db[(E1)+(32*N)]), K39XOR(db[(E2)+(32*N)]), K47XOR(db[(E3)+(32*N)]), K52XOR(db[(E4)+(32*N)]), K19XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K55XOR(db[ 7*N]), K52XOR(db[ 8*N]), K46XOR(db[ 9*N]), K47XOR(db[10*N]), K34XOR(db[11*N]), K19XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K54XOR(db[E0]), K20XOR(db[E1]), K25XOR(db[E2]), K33XOR(db[E3]), K38XOR(db[E4]), K05XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K41XOR(db[39*N]), K38XOR(db[40*N]), K32XOR(db[41*N]), K33XOR(db[42*N]), K20XOR(db[43*N]), K05XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K40XOR(db[(E0)+(32*N)]), K06XOR(db[(E1)+(32*N)]), K11XOR(db[(E2)+(32*N)]), K19XOR(db[(E3)+(32*N)]), K55XOR(db[(E4)+(32*N)]), K46XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K27XOR(db[ 7*N]), K55XOR(db[ 8*N]), K18XOR(db[ 9*N]), K19XOR(db[10*N]), K06XOR(db[11*N]), K46XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K26XOR(db[E0]), K47XOR(db[E1]), K52XOR(db[E2]), K05XOR(db[E3]), K41XOR(db[E4]), K32XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K13XOR(db[39*N]), K41XOR(db[40*N]), K04XOR(db[41*N]), K05XOR(db[42*N]), K47XOR(db[43*N]), K32XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K12XOR(db[(E0)+(32*N)]), K33XOR(db[(E1)+(32*N)]), K38XOR(db[(E2)+(32*N)]), K46XOR(db[(E3)+(32*N)]), K27XOR(db[(E4)+(32*N)]), K18XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K54XOR(db[ 7*N]), K27XOR(db[ 8*N]), K45XOR(db[ 9*N]), K46XOR(db[10*N]), K33XOR(db[11*N]), K18XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K53XOR(db[E0]), K19XOR(db[E1]), K55XOR(db[E2]), K32XOR(db[E3]), K13XOR(db[E4]), K04XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K47XOR(db[39*N]), K20XOR(db[40*N]), K38XOR(db[41*N]), K39XOR(db[42*N]), K26XOR(db[43*N]), K11XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K46XOR(db[(E0)+(32*N)]), K12XOR(db[(E1)+(32*N)]), K48XOR(db[(E2)+(32*N)]), K25XOR(db[(E3)+(32*N)]), K06XOR(db[(E4)+(32*N)]), K52XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K33XOR(db[ 7*N]), K06XOR(db[ 8*N]), K55XOR(db[ 9*N]), K25XOR(db[10*N]), K12XOR(db[11*N]), K52XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K32XOR(db[E0]), K53XOR(db[E1]), K34XOR(db[E2]), K11XOR(db[E3]), K47XOR(db[E4]), K38XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K19XOR(db[39*N]), K47XOR(db[40*N]), K41XOR(db[41*N]), K11XOR(db[42*N]), K53XOR(db[43*N]), K38XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K18XOR(db[(E0)+(32*N)]), K39XOR(db[(E1)+(32*N)]), K20XOR(db[(E2)+(32*N)]), K52XOR(db[(E3)+(32*N)]), K33XOR(db[(E4)+(32*N)]), K55XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K05XOR(db[ 7*N]), K33XOR(db[ 8*N]), K27XOR(db[ 9*N]), K52XOR(db[10*N]), K39XOR(db[11*N]), K55XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K04XOR(db[E0]), K25XOR(db[E1]), K06XOR(db[E2]), K38XOR(db[E3]), K19XOR(db[E4]), K41XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K46XOR(db[39*N]), K19XOR(db[40*N]), K13XOR(db[41*N]), K38XOR(db[42*N]), K25XOR(db[43*N]), K41XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K45XOR(db[(E0)+(32*N)]), K11XOR(db[(E1)+(32*N)]), K47XOR(db[(E2)+(32*N)]), K55XOR(db[(E3)+(32*N)]), K05XOR(db[(E4)+(32*N)]), K27XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K32XOR(db[ 7*N]), K05XOR(db[ 8*N]), K54XOR(db[ 9*N]), K55XOR(db[10*N]), K11XOR(db[11*N]), K27XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K31XOR(db[E0]), K52XOR(db[E1]), K33XOR(db[E2]), K41XOR(db[E3]), K46XOR(db[E4]), K13XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			__syncthreads();
			s3(K18XOR(db[39*N]), K46XOR(db[40*N]), K40XOR(db[41*N]), K41XOR(db[42*N]), K52XOR(db[43*N]), K13XOR(db[44*N]), &db[23*N], &db[15*N], &db[29*N], &db[ 5*N]);
			s2(K48XOR(db[(E0)+(32*N)]), K38XOR(db[(E1)+(32*N)]), K19XOR(db[(E2)+(32*N)]), K27XOR(db[(E3)+(32*N)]), K32XOR(db[(E4)+(32*N)]), K54XOR(db[(E5)+(32*N)]), &db[12*N], &db[27*N], &db[ 1*N], &db[17*N]); 
			__syncthreads();
			s3(K11XOR(db[ 7*N]), K39XOR(db[ 8*N]), K33XOR(db[ 9*N]), K34XOR(db[10*N]), K45XOR(db[11*N]), K06XOR(db[12*N]), &db[55*N], &db[47*N], &db[61*N], &db[37*N]);
			s2(K41XOR(db[E0]), K31XOR(db[E1]), K12XOR(db[E2]), K20XOR(db[E3]), K25XOR(db[E4]), K47XOR(db[E5]), &db[44*N], &db[59*N], &db[33*N], &db[49*N]); 
			break;
		case 2:
			s5(K15XOR(db[(E0)+(32*N)]), K24XOR(db[(E1)+(32*N)]), K28XOR(db[(E2)+(32*N)]), K43XOR(db[(E3)+(32*N)]), K30XOR(db[(E4)+(32*N)]), K03XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K37XOR(db[59*N]), K08XOR(db[60*N]), K09XOR(db[61*N]), K50XOR(db[62*N]), K42XOR(db[63*N]), K21XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K08XOR(db[E0]), K17XOR(db[E1]), K21XOR(db[E2]), K36XOR(db[E3]), K23XOR(db[E4]), K49XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K30XOR(db[27*N]), K01XOR(db[28*N]), K02XOR(db[29*N]), K43XOR(db[30*N]), K35XOR(db[31*N]), K14XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K51XOR(db[(E0)+(32*N)]), K03XOR(db[(E1)+(32*N)]), K07XOR(db[(E2)+(32*N)]), K22XOR(db[(E3)+(32*N)]), K09XOR(db[(E4)+(32*N)]), K35XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K16XOR(db[59*N]), K44XOR(db[60*N]), K17XOR(db[61*N]), K29XOR(db[62*N]), K21XOR(db[63*N]), K00XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K37XOR(db[E0]), K42XOR(db[E1]), K50XOR(db[E2]), K08XOR(db[E3]), K24XOR(db[E4]), K21XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K02XOR(db[27*N]), K30XOR(db[28*N]), K03XOR(db[29*N]), K15XOR(db[30*N]), K07XOR(db[31*N]), K43XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K23XOR(db[(E0)+(32*N)]), K28XOR(db[(E1)+(32*N)]), K36XOR(db[(E2)+(32*N)]), K51XOR(db[(E3)+(32*N)]), K10XOR(db[(E4)+(32*N)]), K07XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K17XOR(db[59*N]), K16XOR(db[60*N]), K42XOR(db[61*N]), K01XOR(db[62*N]), K50XOR(db[63*N]), K29XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K09XOR(db[E0]), K14XOR(db[E1]), K22XOR(db[E2]), K37XOR(db[E3]), K49XOR(db[E4]), K50XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K03XOR(db[27*N]), K02XOR(db[28*N]), K28XOR(db[29*N]), K44XOR(db[30*N]), K36XOR(db[31*N]), K15XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K24XOR(db[(E0)+(32*N)]), K00XOR(db[(E1)+(32*N)]), K08XOR(db[(E2)+(32*N)]), K23XOR(db[(E3)+(32*N)]), K35XOR(db[(E4)+(32*N)]), K36XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K42XOR(db[59*N]), K17XOR(db[60*N]), K14XOR(db[61*N]), K30XOR(db[62*N]), K22XOR(db[63*N]), K01XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K10XOR(db[E0]), K43XOR(db[E1]), K51XOR(db[E2]), K09XOR(db[E3]), K21XOR(db[E4]), K22XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K28XOR(db[27*N]), K03XOR(db[28*N]), K00XOR(db[29*N]), K16XOR(db[30*N]), K08XOR(db[31*N]), K44XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K03XOR(db[(E0)+(32*N)]), K36XOR(db[(E1)+(32*N)]), K44XOR(db[(E2)+(32*N)]), K02XOR(db[(E3)+(32*N)]), K14XOR(db[(E4)+(32*N)]), K15XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K21XOR(db[59*N]), K49XOR(db[60*N]), K50XOR(db[61*N]), K09XOR(db[62*N]), K01XOR(db[63*N]), K37XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K42XOR(db[E0]), K22XOR(db[E1]), K30XOR(db[E2]), K17XOR(db[E3]), K00XOR(db[E4]), K01XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K07XOR(db[27*N]), K35XOR(db[28*N]), K36XOR(db[29*N]), K24XOR(db[30*N]), K44XOR(db[31*N]), K23XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K28XOR(db[(E0)+(32*N)]), K08XOR(db[(E1)+(32*N)]), K16XOR(db[(E2)+(32*N)]), K03XOR(db[(E3)+(32*N)]), K43XOR(db[(E4)+(32*N)]), K44XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K50XOR(db[59*N]), K21XOR(db[60*N]), K22XOR(db[61*N]), K10XOR(db[62*N]), K30XOR(db[63*N]), K09XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K14XOR(db[E0]), K51XOR(db[E1]), K02XOR(db[E2]), K42XOR(db[E3]), K29XOR(db[E4]), K30XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K36XOR(db[27*N]), K07XOR(db[28*N]), K08XOR(db[29*N]), K49XOR(db[30*N]), K16XOR(db[31*N]), K24XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K00XOR(db[(E0)+(32*N)]), K37XOR(db[(E1)+(32*N)]), K17XOR(db[(E2)+(32*N)]), K28XOR(db[(E3)+(32*N)]), K15XOR(db[(E4)+(32*N)]), K16XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K22XOR(db[59*N]), K50XOR(db[60*N]), K51XOR(db[61*N]), K35XOR(db[62*N]), K02XOR(db[63*N]), K10XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K43XOR(db[E0]), K23XOR(db[E1]), K03XOR(db[E2]), K14XOR(db[E3]), K01XOR(db[E4]), K02XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K08XOR(db[27*N]), K36XOR(db[28*N]), K37XOR(db[29*N]), K21XOR(db[30*N]), K17XOR(db[31*N]), K49XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			__syncthreads();
			s5(K29XOR(db[(E0)+(32*N)]), K09XOR(db[(E1)+(32*N)]), K42XOR(db[(E2)+(32*N)]), K00XOR(db[(E3)+(32*N)]), K44XOR(db[(E4)+(32*N)]), K17XOR(db[(E5)+(32*N)]), &db[ 7*N], &db[13*N], &db[24*N], &db[ 2*N]);
			s8(K51XOR(db[59*N]), K22XOR(db[60*N]), K23XOR(db[61*N]), K07XOR(db[62*N]), K03XOR(db[63*N]), K35XOR(db[32*N]), &db[ 4*N], &db[26*N], &db[14*N], &db[20*N]); 
			__syncthreads();
			s5(K22XOR(db[E0]), K02XOR(db[E1]), K35XOR(db[E2]), K50XOR(db[E3]), K37XOR(db[E4]), K10XOR(db[E5]), &db[39*N], &db[45*N], &db[56*N], &db[34*N]);
			s8(K44XOR(db[27*N]), K15XOR(db[28*N]), K16XOR(db[29*N]), K00XOR(db[30*N]), K49XOR(db[31*N]), K28XOR(db[ 0*N]), &db[36*N], &db[58*N], &db[46*N], &db[52*N]); 
			break;
		case 3: 
			s7(K51XOR(db[55*N]), K16XOR(db[56*N]), K29XOR(db[57*N]), K49XOR(db[58*N]), K07XOR(db[59*N]), K17XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K35XOR(db[(E0)+(32*N)]), K22XOR(db[(E1)+(32*N)]), K02XOR(db[(E2)+(32*N)]), K44XOR(db[(E3)+(32*N)]), K14XOR(db[(E4)+(32*N)]), K23XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K44XOR(db[23*N]), K09XOR(db[24*N]), K22XOR(db[25*N]), K42XOR(db[26*N]), K00XOR(db[27*N]), K10XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K28XOR(db[E0]), K15XOR(db[E1]), K24XOR(db[E2]), K37XOR(db[E3]), K07XOR(db[E4]), K16XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K30XOR(db[55*N]), K24XOR(db[56*N]), K08XOR(db[57*N]), K28XOR(db[58*N]), K43XOR(db[59*N]), K49XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K14XOR(db[(E0)+(32*N)]), K01XOR(db[(E1)+(32*N)]), K10XOR(db[(E2)+(32*N)]), K23XOR(db[(E3)+(32*N)]), K50XOR(db[(E4)+(32*N)]), K02XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K16XOR(db[23*N]), K10XOR(db[24*N]), K51XOR(db[25*N]), K14XOR(db[26*N]), K29XOR(db[27*N]), K35XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K00XOR(db[E0]), K44XOR(db[E1]), K49XOR(db[E2]), K09XOR(db[E3]), K36XOR(db[E4]), K17XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K02XOR(db[55*N]), K49XOR(db[56*N]), K37XOR(db[57*N]), K00XOR(db[58*N]), K15XOR(db[59*N]), K21XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K43XOR(db[(E0)+(32*N)]), K30XOR(db[(E1)+(32*N)]), K35XOR(db[(E2)+(32*N)]), K24XOR(db[(E3)+(32*N)]), K22XOR(db[(E4)+(32*N)]), K03XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K17XOR(db[23*N]), K35XOR(db[24*N]), K23XOR(db[25*N]), K43XOR(db[26*N]), K01XOR(db[27*N]), K07XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K29XOR(db[E0]), K16XOR(db[E1]), K21XOR(db[E2]), K10XOR(db[E3]), K08XOR(db[E4]), K42XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K03XOR(db[55*N]), K21XOR(db[56*N]), K09XOR(db[57*N]), K29XOR(db[58*N]), K44XOR(db[59*N]), K50XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K15XOR(db[(E0)+(32*N)]), K02XOR(db[(E1)+(32*N)]), K07XOR(db[(E2)+(32*N)]), K49XOR(db[(E3)+(32*N)]), K51XOR(db[(E4)+(32*N)]), K28XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K42XOR(db[23*N]), K07XOR(db[24*N]), K24XOR(db[25*N]), K15XOR(db[26*N]), K30XOR(db[27*N]), K36XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K01XOR(db[E0]), K17XOR(db[E1]), K50XOR(db[E2]), K35XOR(db[E3]), K37XOR(db[E4]), K14XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K35XOR(db[55*N]), K00XOR(db[56*N]), K17XOR(db[57*N]), K08XOR(db[58*N]), K23XOR(db[59*N]), K29XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K51XOR(db[(E0)+(32*N)]), K10XOR(db[(E1)+(32*N)]), K43XOR(db[(E2)+(32*N)]), K28XOR(db[(E3)+(32*N)]), K30XOR(db[(E4)+(32*N)]), K07XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K21XOR(db[23*N]), K43XOR(db[24*N]), K03XOR(db[25*N]), K51XOR(db[26*N]), K09XOR(db[27*N]), K15XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K37XOR(db[E0]), K49XOR(db[E1]), K29XOR(db[E2]), K14XOR(db[E3]), K16XOR(db[E4]), K50XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K07XOR(db[55*N]), K29XOR(db[56*N]), K42XOR(db[57*N]), K37XOR(db[58*N]), K24XOR(db[59*N]), K01XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K23XOR(db[(E0)+(32*N)]), K35XOR(db[(E1)+(32*N)]), K15XOR(db[(E2)+(32*N)]), K00XOR(db[(E3)+(32*N)]), K02XOR(db[(E4)+(32*N)]), K36XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K50XOR(db[23*N]), K15XOR(db[24*N]), K28XOR(db[25*N]), K23XOR(db[26*N]), K10XOR(db[27*N]), K44XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K09XOR(db[E0]), K21XOR(db[E1]), K01XOR(db[E2]), K43XOR(db[E3]), K17XOR(db[E4]), K22XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K36XOR(db[55*N]), K01XOR(db[56*N]), K14XOR(db[57*N]), K09XOR(db[58*N]), K49XOR(db[59*N]), K30XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K24XOR(db[(E0)+(32*N)]), K07XOR(db[(E1)+(32*N)]), K44XOR(db[(E2)+(32*N)]), K29XOR(db[(E3)+(32*N)]), K03XOR(db[(E4)+(32*N)]), K08XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K22XOR(db[23*N]), K44XOR(db[24*N]), K00XOR(db[25*N]), K24XOR(db[26*N]), K35XOR(db[27*N]), K16XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K10XOR(db[E0]), K50XOR(db[E1]), K30XOR(db[E2]), K15XOR(db[E3]), K42XOR(db[E4]), K51XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			__syncthreads();
			s7(K08XOR(db[55*N]), K30XOR(db[56*N]), K43XOR(db[57*N]), K10XOR(db[58*N]), K21XOR(db[59*N]), K02XOR(db[60*N]), &db[31*N], &db[11*N], &db[21*N], &db[ 6*N]);
			s6(K49XOR(db[(E0)+(32*N)]), K36XOR(db[(E1)+(32*N)]), K16XOR(db[(E2)+(32*N)]), K01XOR(db[(E3)+(32*N)]), K28XOR(db[(E4)+(32*N)]), K37XOR(db[(E5)+(32*N)]), &db[ 3*N], &db[28*N], &db[10*N], &db[18*N]); 
			__syncthreads();
			s7(K01XOR(db[23*N]), K23XOR(db[24*N]), K36XOR(db[25*N]), K03XOR(db[26*N]), K14XOR(db[27*N]), K24XOR(db[28*N]), &db[63*N], &db[43*N], &db[53*N], &db[38*N]);
			s6(K42XOR(db[E0]), K29XOR(db[E1]), K09XOR(db[E2]), K51XOR(db[E3]), K21XOR(db[E4]), K30XOR(db[E5]), &db[35*N], &db[60*N], &db[42*N], &db[50*N]); 
			break;
		}
		__syncthreads();
	}

#endif
}

#define GET_TRIPCODE_CHAR_INDEX(r, t, i0, i1, i2, i3, i4, i5, pos)  \
		(  ((((r)[threadIdx.x + (i0*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (5 + ((pos) * 6)))  \
	 	 | ((((r)[threadIdx.x + (i1*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (4 + ((pos) * 6)))  \
		 | ((((r)[threadIdx.x + (i2*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (3 + ((pos) * 6)))  \
		 | ((((r)[threadIdx.x + (i3*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (2 + ((pos) * 6)))  \
		 | ((((r)[threadIdx.x + (i4*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (1 + ((pos) * 6)))  \
		 | ((((r)[threadIdx.x + (i5*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << (0 + ((pos) * 6)))) \

#define GET_TRIPCODE_CHAR_INDEX_LAST(r, t, i0, i1, i2, i3)     \
		(  ((((r)[threadIdx.x + (i0*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << 5)  \
	 	 | ((((r)[threadIdx.x + (i1*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << 4)  \
		 | ((((r)[threadIdx.x + (i2*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << 3)  \
		 | ((((r)[threadIdx.x + (i3*N)] & (0x01 << (t))) ? (0x1) : (0x0)) << 2)) \

DES_FUNCTION_QUALIFIERS void
DES_GetTripcodeChunks(int tripcodeIndex, unsigned int *tripcodeChunkArray, int searchMode)
{
	// Perform the final permutation here.
	if (searchMode == SEARCH_MODE_FORWARD_MATCHING) {
		tripcodeChunkArray[0] =   GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
	} else if (searchMode == SEARCH_MODE_BACKWARD_MATCHING) {
		tripcodeChunkArray[0] =   GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
		                        | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
		                        | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
		                        | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
		                        | GET_TRIPCODE_CHAR_INDEX_LAST(dataBlocks, tripcodeIndex, 48, 16, 56, 24);
	} else if (searchMode == SEARCH_MODE_FORWARD_AND_BACKWARD_MATCHING) {
		tripcodeChunkArray[0] =   GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		tripcodeChunkArray[1] =   GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
								| GET_TRIPCODE_CHAR_INDEX_LAST(dataBlocks, tripcodeIndex, 48, 16, 56, 24);
	} else {
		tripcodeChunkArray[0] =   GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
								| GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		tripcodeChunkArray[1] = ((tripcodeChunkArray[0] << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 0);
		tripcodeChunkArray[2] = ((tripcodeChunkArray[1] << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 0);
		tripcodeChunkArray[3] = ((tripcodeChunkArray[2] << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 0);
		tripcodeChunkArray[4] = ((tripcodeChunkArray[3] << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 0);
		tripcodeChunkArray[5] = ((tripcodeChunkArray[4] << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX_LAST(dataBlocks, tripcodeIndex, 48, 16, 56, 24);
	}
}

DES_FUNCTION_QUALIFIERS
unsigned char *DES_GetTripcode(int tripcodeIndex, unsigned char *tripcode)
{
	// Perform the final permutation as necessary.
  	tripcode[0] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 0)];
  	tripcode[1] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 0)];
  	tripcode[2] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 0)];
  	tripcode[3] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 0)];
  	tripcode[4] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0)];
  	tripcode[5] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 0)];
  	tripcode[6] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 0)];
  	tripcode[7] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 0)];
  	tripcode[8] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 0)];
	tripcode[9] = CUDA_DES_indexToCharTable[GET_TRIPCODE_CHAR_INDEX_LAST(dataBlocks, tripcodeIndex, 48, 16, 56, 24)];
 	tripcode[10] = '\0';

	return tripcode;
}

#define SET_KEY_CHAR(var, flag, table, value)             \
	if (!(flag)) {                                        \
		var = (table)[(value)];                           \
		isSecondByte = IS_FIRST_BYTE_SJIS(var);           \
	} else {                                              \
		var = CUDA_keyCharTable_SecondByte[(value)];          \
		isSecondByte = FALSE;                             \
	}

#define CUDA_DES_DEFINE_SEARCH_FUNCTION(functionName) \
__global__ void functionName(\
	GPUOutput *outputArray,\
	unsigned char      *keyBitmap,\
	unsigned int     *tripcodeChunkArray,\
	unsigned int      numTripcodeChunk,\
	int         searchMode) {

#define CUDA_DES_BEFORE_SEARCHING \
	GPUOutput  *output = &outputArray[blockIdx.x * blockDim.x + threadIdx.x];\
	unsigned char        key[8];\
	BOOL         isSecondByte;\
	unsigned char        tripcodeIndex;\
	unsigned char        passCount = 0;\
	BOOL found = FALSE;\
	\
	if (threadIdx.y == 0) {\
		output->numMatchingTripcodes = 0;\
	}\
	key[0] = CUDA_key[0];\
	key[1] = CUDA_key[1];\
	key[2] = CUDA_key[2];\
	\
	for (passCount = 0; passCount < 10; ++passCount) {\
		isSecondByte = IS_FIRST_BYTE_SJIS(CUDA_key[2]);\
		SET_KEY_CHAR(key[3], isSecondByte, CUDA_keyCharTable_FirstByte, CUDA_key[3] + (((threadIdx.x >> 6) &  3) | ((passCount & 15) << 2)));\
		SET_KEY_CHAR(key[4], isSecondByte, CUDA_keyCharTable_FirstByte, CUDA_key[4] + ( (blockIdx.x  >> 6) & 63));\
		SET_KEY_CHAR(key[5], isSecondByte, CUDA_keyCharTable_FirstByte, CUDA_key[5] + (  blockIdx.x        & 63));\
		SET_KEY_CHAR(key[6], isSecondByte, CUDA_keyCharTable_FirstByte, CUDA_key[6] + (  threadIdx.x       & 63));\
		unsigned int keyFrom00To27 = (((unsigned int)key[3] & 0x7f) << 21) | (((unsigned int)key[2] & 0x7f) << 14) | (((unsigned int)key[1] & 0x7f) <<  7) | (((unsigned int)key[0] & 0x7f) << 0); \
		unsigned int keyFrom28To48 = (((unsigned int)key[6] & 0x7f) << 14) | (((unsigned int)key[5] & 0x7f) <<  7) | (((unsigned int)key[4] & 0x7f) << 0); \
		__syncthreads();\
		DES_Crypt(keyFrom00To27, keyFrom28To48);\
		\
		__syncthreads();\
		if (threadIdx.y == 0) {\
			for (tripcodeIndex = 0; tripcodeIndex < CUDA_DES_BS_DEPTH; ++tripcodeIndex) {

#define CUDA_DES_END_OF_SEAERCH_FUNCTION \
			}\
		}\
	}\
quit_loops:\
	if (found == TRUE) {\
		output->numMatchingTripcodes  = 1;\
		output->pair.key.c[0] = key[0];\
		output->pair.key.c[1] = key[1];\
		output->pair.key.c[2] = key[2];\
		output->pair.key.c[3] = key[3];\
		output->pair.key.c[4] = key[4];\
		output->pair.key.c[5] = key[5];\
		output->pair.key.c[6] = key[6];\
		output->pair.key.c[7] = CUDA_key7Array[tripcodeIndex];\
	}\
	if (threadIdx.y == 0)\
		output->numGeneratedTripcodes = CUDA_DES_BS_DEPTH * passCount;\
}

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_ForwardOrBackwardMatching_Simple)
	unsigned int tripcodeChunk;
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, &tripcodeChunk, searchMode);
	if (CUDA_smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)])
		continue;
	for (int j = 0; j < numTripcodeChunk; ++j){
		if (tripcodeChunkArray[j] == tripcodeChunk) {
			found = TRUE;
			goto quit_loops;
		}
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_ForwardOrBackwardMatching)
	unsigned int tripcodeChunk;
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, &tripcodeChunk, searchMode);
	if (CUDA_smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)] || keyBitmap[tripcodeChunk >> ((5 - KEY_BITMAP_LEN_STRING) * 6)])
		continue;
	int lower = 0, upper = numTripcodeChunk - 1, middle = lower;
	while (tripcodeChunk != tripcodeChunkArray[middle] && lower <= upper) {
		middle = (lower + upper) >> 1;
		if (tripcodeChunk > tripcodeChunkArray[middle]) {
			lower = middle + 1;
		} else {
			upper = middle - 1;
		}
	}
	if (tripcodeChunk == tripcodeChunkArray[middle]) {
		found = TRUE;
		goto quit_loops;
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_ForwardMatching_1Chunk)
	unsigned int tripcodeChunk0 = tripcodeChunkArray[0];
CUDA_DES_BEFORE_SEARCHING
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 0) != ((tripcodeChunk0 >> (6 * 4)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 0) != ((tripcodeChunk0 >> (6 * 3)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 0) != ((tripcodeChunk0 >> (6 * 2)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 0) != ((tripcodeChunk0 >> (6 * 1)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0) != ((tripcodeChunk0 >> (6 * 0)) & 0x3f))
		goto skip_final_permutation;
	found = TRUE;
	goto quit_loops;
skip_final_permutation:
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_BackwardMatching_1Chunk)
	unsigned int tripcodeChunk0 = tripcodeChunkArray[0];
CUDA_DES_BEFORE_SEARCHING
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 0) != ((tripcodeChunk0 >> (6 * 4)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 0) != ((tripcodeChunk0 >> (6 * 3)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 0) != ((tripcodeChunk0 >> (6 * 2)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX(dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 0) != ((tripcodeChunk0 >> (6 * 1)) & 0x3f))
		goto skip_final_permutation;
	if (GET_TRIPCODE_CHAR_INDEX_LAST(dataBlocks, tripcodeIndex, 48, 16, 56, 24) != ((tripcodeChunk0 >> (6 * 0)) & 0x3f))
		goto skip_final_permutation;
	found = TRUE;
	goto quit_loops;
skip_final_permutation:
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_Flexible_Simple)
	unsigned int generatedTripcodeChunkArray[6];
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, generatedTripcodeChunkArray, searchMode);
	for (int pos = 0; pos < 6; ++pos) {
		if (CUDA_smallKeyBitmap[generatedTripcodeChunkArray[pos] >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)])
			continue;
		for (int j = 0; j < numTripcodeChunk; ++j){
			if (tripcodeChunkArray[j] == generatedTripcodeChunkArray[pos]) {
				found = TRUE;
				goto quit_loops;
			}
		}
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_Flexible)
	unsigned int generatedTripcodeChunkArray[6];
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, generatedTripcodeChunkArray, searchMode);
	for (int pos = 0; pos < 6; ++pos) {
		unsigned int generatedTripcodeChunk = generatedTripcodeChunkArray[pos];
		if (   CUDA_smallKeyBitmap[generatedTripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)] 
		    || keyBitmap[generatedTripcodeChunk >> ((5 - KEY_BITMAP_LEN_STRING) * 6)])
			continue;
		int lower = 0, upper = numTripcodeChunk - 1, middle = lower;
		while (generatedTripcodeChunk != tripcodeChunkArray[middle] && lower <= upper) {
			middle = (lower + upper) >> 1;
			if (generatedTripcodeChunk > tripcodeChunkArray[middle]) {
				lower = middle + 1;
			} else {
				upper = middle - 1;
			}
		}
		if (generatedTripcodeChunk == tripcodeChunkArray[middle]) {
			found = TRUE;
			goto quit_loops;
		}
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_ForwardAndBackwardMatching_Simple)
	unsigned int generatedTripcodeChunkArray[6];
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, generatedTripcodeChunkArray, searchMode);
	//
	if (!CUDA_smallKeyBitmap[generatedTripcodeChunkArray[0] >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) {
		for (int j = 0; j < numTripcodeChunk; ++j){
			if (tripcodeChunkArray[j] == generatedTripcodeChunkArray[0]) {
				found = TRUE;
				goto quit_loops;
			}
		}
	}
	//
	if (!CUDA_smallKeyBitmap[generatedTripcodeChunkArray[1] >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) {
		for (int j = 0; j < numTripcodeChunk; ++j){
			if (tripcodeChunkArray[j] == generatedTripcodeChunkArray[1]) {
				found = TRUE;
				goto quit_loops;
			}
		}
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION

CUDA_DES_DEFINE_SEARCH_FUNCTION(CUDA_PerformSearching_DES_ForwardAndBackwardMatching)
	unsigned int generatedTripcodeChunkArray[6];
	unsigned int generatedTripcodeChunk;
CUDA_DES_BEFORE_SEARCHING
	DES_GetTripcodeChunks(tripcodeIndex, generatedTripcodeChunkArray, searchMode);
	//
	generatedTripcodeChunk = generatedTripcodeChunkArray[0];
	if (!CUDA_smallKeyBitmap[generatedTripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)] && !keyBitmap[generatedTripcodeChunk >> ((5 - KEY_BITMAP_LEN_STRING) * 6)]) {
		int lower = 0, upper = numTripcodeChunk - 1, middle = lower;
		while (generatedTripcodeChunk != tripcodeChunkArray[middle] && lower <= upper) {
			middle = (lower + upper) >> 1;
			if (generatedTripcodeChunk > tripcodeChunkArray[middle]) {
				lower = middle + 1;
			} else {
				upper = middle - 1;
			}
		}
		if (generatedTripcodeChunk == tripcodeChunkArray[middle]) {
			found = TRUE;
			goto quit_loops;
		}
	}
	//
	generatedTripcodeChunk = generatedTripcodeChunkArray[1];
	if (!CUDA_smallKeyBitmap[generatedTripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)] && !keyBitmap[generatedTripcodeChunk >> ((5 - KEY_BITMAP_LEN_STRING) * 6)]) {
		int lower = 0, upper = numTripcodeChunk - 1, middle = lower;
		while (generatedTripcodeChunk != tripcodeChunkArray[middle] && lower <= upper) {
			middle = (lower + upper) >> 1;
			if (generatedTripcodeChunk > tripcodeChunkArray[middle]) {
				lower = middle + 1;
			} else {
				upper = middle - 1;
			}
		}
		if (generatedTripcodeChunk == tripcodeChunkArray[middle]) {
			found = TRUE;
			goto quit_loops;
		}
	}
CUDA_DES_END_OF_SEAERCH_FUNCTION



///////////////////////////////////////////////////////////////////////////////
// CUDA SEARCH THREAD FOR 10 CHARACTER TRIPCODES                             //
///////////////////////////////////////////////////////////////////////////////

#define SET_BIT_FOR_KEY7(var, k) if (key7 & (0x1 << (k))) (var) |= 0x1 << tripcodeIndex

unsigned WINAPI Thread_SearchForDESTripcodesOnCUDADevice(LPVOID info)
{
	cudaError_t     cudaError;
	cudaDeviceProp  CUDADeviceProperties;
	unsigned int    numBlocksPerSM;
	unsigned int    numBlocksPerGrid;
	GPUOutput      *outputArray = NULL;
	GPUOutput      *CUDA_outputArray = NULL;
	unsigned int   *CUDA_tripcodeChunkArray = NULL;
	unsigned char  *CUDA_keyBitmap = NULL;
	unsigned int    sizeOutputArray;
	unsigned char   key[MAX_LEN_TRIPCODE + 1];
	unsigned char   salt[3];
	unsigned char   expansionFunction[96];
	char            status[LEN_LINE_BUFFER_FOR_SCREEN] = "";
	int             optimizationPhase    = CUDA_OPTIMIZATION_PHASE_NUM_BLOCKS;
	int             optimizationSubphase = 0;
	double          timeElapsedInOptimizationSubphase = 0;
	static int      numBlocksTableForOptimization[] = {8, 16, 32, 48, 64, 96, 128, 160, 192, 224, 256, 0};
	double          numGeneratedTripcodes = 0;
	double          speedInPreviousSubphase = 0;
	double          speedInCurrentSubphase = 0;
	DWORD           startingTime;
	DWORD           endingTime;
	double          deltaTime;
	int          salt0NonDotCounter = 0;
	int          salt1NonDotCounter = 0;

	key[lenTripcode] = '\0';
	salt[2]          = '\0';
	
	CUDA_ERROR(cudaSetDevice(((CUDADeviceSearchThreadInfo *)info)->CUDADeviceIndex));
	CUDA_ERROR(cudaGetDeviceProperties(&CUDADeviceProperties, ((CUDADeviceSearchThreadInfo *)info)->CUDADeviceIndex));
	if (CUDADeviceProperties.computeMode == cudaComputeModeProhibited) {
		sprintf(status, "[disabled]");
		UpdateCUDADeviceStatus(((CUDADeviceSearchThreadInfo *)info), FALSE, status);
		return 0;
	}
	int numThreadsPerBlock = (CUDADeviceProperties.major == 3 && CUDADeviceProperties.minor == 7) ? 448 :
		                     (CUDADeviceProperties.major == 2                                   ) ? 768 :
		                     (CUDADeviceProperties.major == 3                                   ) ? 768 :
		                     (CUDADeviceProperties.major == 5                                   ) ? 512 :
		                                                                                            512;
	int numBitsliceDESPerBlock = numThreadsPerBlock / NUM_THREADS_PER_BITSICE_DES;

	if (options.CUDANumBlocksPerSM == CUDA_NUM_BLOCKS_PER_SM_NIL) {
		numBlocksPerSM = numBlocksTableForOptimization[optimizationSubphase];
	} else {
		numBlocksPerSM = options.CUDANumBlocksPerSM;
	}
	numBlocksPerGrid = numBlocksPerSM * CUDADeviceProperties.multiProcessorCount;
	sizeOutputArray = numBitsliceDESPerBlock * numBlocksPerGrid;
	outputArray = (GPUOutput *)malloc(sizeof(GPUOutput) * sizeOutputArray);
	ERROR0(outputArray == NULL, ERROR_NO_MEMORY, "Not enough memory.");
	cudaError = cudaMalloc((void **)&CUDA_outputArray, sizeof(GPUOutput) * sizeOutputArray);
	ERROR0(cudaError == cudaErrorMemoryAllocation, ERROR_NO_MEMORY, "Not enough memory.");
	CUDA_ERROR(cudaError);
	cudaError = cudaMalloc((void **)&CUDA_keyBitmap, KEY_BITMAP_SIZE);
	ERROR0(cudaError == cudaErrorMemoryAllocation, ERROR_NO_MEMORY, "Not enough memory.");
	CUDA_ERROR(cudaError);
	cudaError = cudaMalloc((void **)&CUDA_tripcodeChunkArray, sizeof(unsigned int) * numTripcodeChunk); 
	ERROR0(cudaError == cudaErrorMemoryAllocation, ERROR_NO_MEMORY, "Not enough memory.");
	CUDA_ERROR(cudaError);

	CUDA_ERROR(cudaMemcpy(CUDA_tripcodeChunkArray, tripcodeChunkArray, sizeof(unsigned int) * numTripcodeChunk, cudaMemcpyHostToDevice));
	CUDA_ERROR(cudaMemcpy(CUDA_keyBitmap, keyBitmap, KEY_BITMAP_SIZE, cudaMemcpyHostToDevice));
	CUDA_ERROR(cudaMemcpyToSymbol(CUDA_base64CharTable,      base64CharTable,      sizeof(base64CharTable)));
	CUDA_ERROR(cudaMemcpyToSymbol(CUDA_keyCharTable_OneByte, keyCharTable_OneByte, SIZE_KEY_CHAR_TABLE));
	CUDA_ERROR(cudaMemcpyToSymbol(CUDA_keyCharTable_FirstByte,   keyCharTable_FirstByte,   SIZE_KEY_CHAR_TABLE));
	CUDA_ERROR(cudaMemcpyToSymbol(CUDA_keyCharTable_SecondByte,  keyCharTable_SecondByte,  SIZE_KEY_CHAR_TABLE));
	CUDA_ERROR(cudaMemcpyToSymbol(CUDA_smallKeyBitmap, smallKeyBitmap, SMALL_KEY_BITMAP_SIZE));
	
	startingTime = timeGetTime();

	while (!GetTerminationState()) {
		// Choose the first 3 characters of the key.
		do {
			SetCharactersInTripcodeKey(key, 3);
			unsigned char  salt[2];
			salt[0] = CONVERT_CHAR_FOR_SALT(key[1]);
			salt[1] = CONVERT_CHAR_FOR_SALT(key[2]);
			if (   (salt[0] == '.' && salt0NonDotCounter < 64)
				|| (salt[1] == '.' && salt1NonDotCounter < 64))
				continue;
			if (salt[0] == '.') {
				salt0NonDotCounter -= 63;
			} else {
				++salt0NonDotCounter;
			}
			if (salt[1] == '.') {
				salt1NonDotCounter -= 63;
			} else {
				++salt1NonDotCounter;
			}
			break;
		} while (TRUE);
		
		// Generate random bytes for the key to ensure the randomness of them.
		unsigned char randomByteForKey6 = RandomByte();
		for (int i = 3; i < lenTripcode; ++i)
			key[i] = RandomByte();
		unsigned char key7Array[CUDA_DES_BS_DEPTH];
		DES_Vector  keyFrom49To55Array[7] = {0, 0, 0, 0, 0, 0, 0};
		for (int tripcodeIndex = 0; tripcodeIndex < CUDA_DES_BS_DEPTH; ++tripcodeIndex) {
			unsigned char key7 = key7Array[tripcodeIndex] = keyCharTable_SecondByteAndOneByte[key[7] + tripcodeIndex];
			SET_BIT_FOR_KEY7(keyFrom49To55Array[0], 0);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[1], 1);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[2], 2);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[3], 3);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[4], 4);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[5], 5);
			SET_BIT_FOR_KEY7(keyFrom49To55Array[6], 6);
		}

		// Create an expansion function based on the salt.
		salt[0] = CONVERT_CHAR_FOR_SALT(key[1]);
		salt[1] = CONVERT_CHAR_FOR_SALT(key[2]);
		DES_CreateExpansionFunction((char *)salt, expansionFunction);

		// Call an appropriate CUDA kernel.
		CUDA_ERROR(cudaMemcpyToSymbol(CUDA_key,               key,               lenTripcode));
		CUDA_ERROR(cudaMemcpyToSymbol(CUDA_expansionFunction, expansionFunction, sizeof(expansionFunction)));
		CUDA_ERROR(cudaMemcpyToSymbol(CUDA_key7Array,         key7Array,         sizeof(key7Array)));
		CUDA_ERROR(cudaMemcpyToSymbol(CUDA_keyFrom49To55Array, keyFrom49To55Array, sizeof(keyFrom49To55Array)));
		dim3 dimBlock(numBitsliceDESPerBlock, NUM_THREADS_PER_BITSICE_DES);
		dim3 dimGrid(numBlocksPerGrid);
		if (searchMode == SEARCH_MODE_FLEXIBLE) {
			if (numTripcodeChunk <= CUDA_SIMPLE_SEARCH_THRESHOLD) {
				CUDA_PerformSearching_DES_Flexible_Simple<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			} else {
				CUDA_PerformSearching_DES_Flexible<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			}
		} else if (searchMode == SEARCH_MODE_FORWARD_AND_BACKWARD_MATCHING) {
			if (numTripcodeChunk <= CUDA_SIMPLE_SEARCH_THRESHOLD) {
				CUDA_PerformSearching_DES_ForwardAndBackwardMatching_Simple<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			} else {
				CUDA_PerformSearching_DES_ForwardAndBackwardMatching<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			}
		} else {
			if (numTripcodeChunk == 1) {
				if (searchMode == SEARCH_MODE_FORWARD_MATCHING) {
					CUDA_PerformSearching_DES_ForwardMatching_1Chunk<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
						CUDA_outputArray,
						CUDA_keyBitmap,
						CUDA_tripcodeChunkArray,
						numTripcodeChunk,
						searchMode);
				} else {
					CUDA_PerformSearching_DES_BackwardMatching_1Chunk<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
						CUDA_outputArray,
						CUDA_keyBitmap,
						CUDA_tripcodeChunkArray,
						numTripcodeChunk,
						searchMode);
				}
			} else if (numTripcodeChunk <= CUDA_SIMPLE_SEARCH_THRESHOLD) {
				CUDA_PerformSearching_DES_ForwardOrBackwardMatching_Simple<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			} else {
				CUDA_PerformSearching_DES_ForwardOrBackwardMatching<<<dimGrid, dimBlock, CUDADeviceProperties.sharedMemPerBlock>>>(
					CUDA_outputArray,
					CUDA_keyBitmap,
					CUDA_tripcodeChunkArray,
					numTripcodeChunk,
					searchMode);
			}
		}
		CUDA_ERROR(cudaGetLastError());
		// CUDA_ERROR(cudaDeviceSynchronize()); // Check errors at kernel launch.

		// Process the output array.
		CUDA_ERROR(cudaMemcpy(outputArray, CUDA_outputArray, sizeof(GPUOutput) * sizeOutputArray, cudaMemcpyDeviceToHost));
		// We can save registers this way. Not particularly safe, though.
		for (unsigned int indexOutput = 0; indexOutput < sizeOutputArray; indexOutput++){
			GPUOutput *output = &outputArray[indexOutput];
			if (output->numMatchingTripcodes > 0)
				GenerateDESTripcode(output->pair.tripcode.c, output->pair.key.c);
		}
		numGeneratedTripcodes += ProcessGPUOutput(key, outputArray, sizeOutputArray, FALSE);
		
		// Optimization
		endingTime = timeGetTime();
		deltaTime = (endingTime >= startingTime)
						? ((double)endingTime - (double)startingTime                     ) * 0.001
						: ((double)endingTime - (double)startingTime + (double)0xffffffff) * 0.001;
		while (GetPauseState() && !GetTerminationState())
			Sleep(PAUSE_INTERVAL);
		startingTime = timeGetTime();
		timeElapsedInOptimizationSubphase += deltaTime;
		speedInCurrentSubphase = numGeneratedTripcodes / timeElapsedInOptimizationSubphase;
		//
		if (optimizationPhase == CUDA_OPTIMIZATION_PHASE_NUM_BLOCKS) {
			if (options.CUDANumBlocksPerSM != CUDA_NUM_BLOCKS_PER_SM_NIL) {
				optimizationPhase     = CUDA_OPTIMIZATION_PHASE_COMPLETED;
				optimizationSubphase  = 0;
				numGeneratedTripcodes = 0;
				timeElapsedInOptimizationSubphase = 0;
			} else if (timeElapsedInOptimizationSubphase >= CUDA_OPTIMIZATION_SUBPHASE_DURATION) {
				if (   optimizationSubphase > 0
				    && (   speedInPreviousSubphase > speedInCurrentSubphase
					    || fabs(speedInPreviousSubphase - speedInCurrentSubphase) / speedInPreviousSubphase < CUDA_OPTIMIZATION_THRESHOLD)) {
					numBlocksPerSM = numBlocksTableForOptimization[(speedInPreviousSubphase > speedInCurrentSubphase) ? (optimizationSubphase - 1) : (optimizationSubphase)];
					optimizationPhase = CUDA_OPTIMIZATION_PHASE_COMPLETED;
					optimizationSubphase = 0;
					numGeneratedTripcodes = 0;
				} else if (numBlocksTableForOptimization[optimizationSubphase + 1] > 0) {
					numBlocksPerSM = numBlocksTableForOptimization[++optimizationSubphase];
					timeElapsedInOptimizationSubphase = 0;
					numGeneratedTripcodes = 0;
					speedInPreviousSubphase = speedInCurrentSubphase;
				} else {
					optimizationPhase = CUDA_OPTIMIZATION_PHASE_COMPLETED;
					optimizationSubphase = 0;
					numGeneratedTripcodes = 0;
				}
				timeElapsedInOptimizationSubphase = 0;
				numGeneratedTripcodes = 0;
				numBlocksPerGrid = numBlocksPerSM * CUDADeviceProperties.multiProcessorCount;
				sizeOutputArray = numBitsliceDESPerBlock * numBlocksPerGrid;
				free(outputArray);
				outputArray = (GPUOutput *)malloc(sizeof(GPUOutput) * sizeOutputArray);
				ERROR0(outputArray == NULL, ERROR_NO_MEMORY, "Not enough memory.");
				CUDA_ERROR(cudaFree(CUDA_outputArray));
				cudaError = cudaMalloc((void **)&CUDA_outputArray, sizeof(GPUOutput) * sizeOutputArray);
				ERROR0(cudaError == cudaErrorMemoryAllocation, ERROR_NO_MEMORY, "Not enough memory.");
				CUDA_ERROR(cudaError);
			}
		}
		//
		sprintf(status,
			    "%s%.1lfM TPS, %d blocks/SM",
				(optimizationPhase != CUDA_OPTIMIZATION_PHASE_COMPLETED) ? "[optimizing...] " : "",
				speedInCurrentSubphase / 1000000,
				numBlocksPerSM);
		UpdateCUDADeviceStatus(((CUDADeviceSearchThreadInfo *)info), (optimizationPhase != CUDA_OPTIMIZATION_PHASE_COMPLETED), status);
	}

	RELEASE_AND_SET_TO_NULL(CUDA_outputArray,        cudaFree);
	RELEASE_AND_SET_TO_NULL(CUDA_tripcodeChunkArray, cudaFree);
	RELEASE_AND_SET_TO_NULL(CUDA_keyBitmap,          cudaFree);
	RELEASE_AND_SET_TO_NULL(outputArray,             free);
}
