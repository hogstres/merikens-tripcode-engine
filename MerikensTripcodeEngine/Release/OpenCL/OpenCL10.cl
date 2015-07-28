// Meriken's Tripcode Engine 2.0.0
// Copyright (c) 2011-2015 Meriken.Z. <meriken.2ch@gmail.com>
//
// The initial versions of this software were based on:
// CUDA SHA-1 Tripper 0.2.1
// Copyright (c) 2009 Horo/.IBXjcg
// 
// A potion of the code that deals with DES decryption is adopted from:
// John the Ripper password cracker
// Copyright (c) 1996-2002, 2005, 2010 by Solar Designer
//
// A potion of the code that deals with SHA-1 hash generation is adopted from:
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



///////////////////////////////////////////////////////////////////////////////
// CONSTANTS AND TYPES                                                       //
///////////////////////////////////////////////////////////////////////////////

typedef unsigned char BOOL;
#define TRUE  (1)
#define FALSE (0)

#define MAX_LEN_TRIPCODE            12
#define MAX_LEN_TRIPCODE_KEY        12
#define MAX_LEN_EXPANDED_PATTERN    MAX_LEN_TRIPCODE
#define SMALL_KEY_BITMAP_LEN_STRING 2
#define SMALL_KEY_BITMAP_SIZE       (64 * 64)
#define MEDIUM_KEY_BITMAP_LEN_STRING 3
#define KEY_BITMAP_LEN_STRING       4
#define DES_SIZE_EXPANSION_FUNCTION 96
#define OPENCL_DES_BS_DEPTH         32

#ifdef MAXIMIZE_KEY_SPACE

#define IS_FIRST_BYTE_SJIS(c)         \
	(   (0x81 <= (c) && (c) <= 0x84)  \
	 || (0x88 <= (c) && (c) <= 0x9f)  \
	 || (0xe0 <= (c) && (c) <= 0xea)) \

#else

#define IS_FIRST_BYTE_SJIS(c)         \
	(   (0x89 <= (c) && (c) <= 0x97)  \
	 || (0x99 <= (c) && (c) <= 0x9f)  \
 	 || (0xe0 <= (c) && (c) <= 0xe9)) \

#endif

#define IS_ONE_BYTE_KEY_CHAR(c)       \
	(   (0x21 <= (c) && (c) <= 0x24)  \
	 || (0x26 <= (c) && (c) <= 0x2a)  \
	 || (0x2d <= (c) && (c) <= 0x7e)  \
	 || (0xa1 <= (c) && (c) <= 0xdf)) \

typedef struct {
	// unsigned int length;
	unsigned char c[MAX_LEN_TRIPCODE];
} Tripcode;

typedef struct {
	// unsigned int length;
	unsigned char c[MAX_LEN_TRIPCODE_KEY];
} TripcodeKey;

typedef struct {
	Tripcode    tripcode;
	TripcodeKey key;
} TripcodeKeyPair;

typedef struct {
	unsigned char pos;
	unsigned char c[MAX_LEN_EXPANDED_PATTERN + 1];
} ExpandedPattern;

typedef struct {
	unsigned int  numGeneratedTripcodes;
	unsigned char numMatchingTripcodes;
	TripcodeKeyPair pair;
} GPUOutput;

typedef struct KeyInfo {
	unsigned char partialKeyAndRandomBytes[10];
	unsigned char expansioinFunction[DES_SIZE_EXPANSION_FUNCTION];
} KeyInfo;

typedef struct PartialKeyFrom3To6 {
	unsigned char partialKeyFrom3To6[4];
} PartialKeyFrom3To6;

__constant const char base64CharTable[64] = {
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
	'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
	'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
	'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '/',
};

__constant const char indexToCharTable[64] =
//	"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz";
{
	/* 00 */ '.', '/',
	/* 02 */ '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 
	/* 12 */ 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 
	/* 28 */ 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	/* 38 */ 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p',
	/* 54 */ 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 
};

typedef unsigned long vtype;

#define vnot(dst, a)     (dst) =  (~(a))
#define vand(dst, a, b)  (dst) =  ((a) & (b))
#define vor(dst, a, b)   (dst) =  ((a) | (b))
#define vxor(dst, a, b)  (dst) =  ((a) ^ (b))
#define vandn(dst, a, b) (dst) =  (~(b) & (a))
#define vsel(x, y, z, w) (x) = bitselect((y), (z), (w))

#define DES_NUM_BITS_IN_KEY 56

#define DES_DATA_BLOCKS_SPACE __private
#define DES_KEYS_SPACE        __local



///////////////////////////////////////////////////////////////////////////////
// DES                                                                       //
///////////////////////////////////////////////////////////////////////////////

void s1(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16;
	
	vsel(var6, var2, var1, var4); 
	vxor(var7, var1, var2); 
	vor(var8, var0, var3); 
	vxor(var9, var7, var8); 
	vsel(var10, var4, var6, var9); 
	vxor(var11, var3, var10); 
	vxor(var12, var0, var11); 
	vsel(var0, var12, var8, var6); 
	vsel(var13, var7, var9, var4); 
	vxor(var14, var0, var13); 
	vsel(var0, var8, var12, var14); 
	vsel(var8, var11, var12, var4); 
	vsel(var15, var0, var14, var8); 
	vxor(var16, var6, var15); 
	vsel(var15, var9, var11, var0); 
	vsel(var0, var6, var9, var12); 
	vsel(var11, var4, var0, var16); 
	vxor(var4, var15, var11); 
	vsel(var15, var12, var0, var2); 
	vsel(var0, var3, var6, var16); 
	vsel(var6, var4, var15, var0); 
	vnot(var0, var6); 
	vsel(var6, var0, var4, var5); 
	vxor(*out1, *out1, var6); 
	vsel(var4, var0, var2, var11); 
	vsel(var0, var15, var1, var9); 
	vsel(var1, var4, var3, var0); 
	vxor(var3, var16, var1); 
	vsel(var4, var3, var12, var5); 
	vxor(*out2, *out2, var4); 
	vsel(var4, var8, var13, var1); 
	vsel(var6, var0, var12, var10); 
	vxor(var0, var4, var6); 
	vsel(var4, var0, var16, var5); 
	vxor(*out4, *out4, var4); 
	vxor(var0, var12, var3); 
	vsel(var3, var2, var0, var1); 
	vsel(var0, var3, var7, var6); 
	vsel(var1, var0, var14, var5); 
	vxor(*out3, *out3, var1); 
}

void s2(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16; 
	vtype var17; 

	vsel(var6, var0, var2, var5); 
	vsel(var7, var5, var6, var4); 
	vsel(var8, var2, var3, var7); 
	vxor(var9, var0, var8); 
	vxor(var8, var4, var5); 
	vxor(var10, var9, var8); 
	vsel(var11, var3, var9, var5); 
	vnot(var12, var11); 
	vxor(var13, var6, var12); 
	vxor(var6, var8, var13); 
	vsel(var14, var6, var10, var1); 
	vxor(*out2, *out2, var14); 
	vxor(var6, var3, var7); 
	vsel(var14, var9, var5, var8); 
	vsel(var15, var13, var6, var14); 
	vsel(var16, var13, var6, var4); 
	vxor(var17, var2, var6); 
	vsel(var6, var16, var17, var0); 
	vsel(var16, var9, var10, var13); 
	vsel(var9, var3, var6, var4); 
	vxor(var3, var16, var9); 
	vxor(var17, var12, var3); 
	vsel(var3, var17, var6, var1); 
	vxor(*out1, *out1, var3); 
	vsel(var3, var6, var17, var8); 
	vsel(var8, var10, var13, var0); 
	vsel(var0, var3, var8, var14); 
	vsel(var3, var16, var17, var6); 
	vsel(var6, var8, var2, var7); 
	vsel(var2, var3, var6, var4); 
	vsel(var3, var15, var2, var1); 
	vxor(*out4, *out4, var3); 
	vsel(var2, var8, var9, var5); 
	vsel(var3, var11, var0, var2); 
	vxor(var2, var6, var3); 
	vsel(var3, var0, var2, var1); 
	vxor(*out3, *out3, var3); 
}                      

void s3(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16;

	vsel(var6, var3, var2, var4); 
	vxor(var7, var5, var6); 
	vxor(var6, var1, var7); 
	vsel(var8, var2, var5, var6); 
	vsel(var9, var4, var2, var7); 
	vsel(var10, var4, var7, var1); 
	vsel(var11, var9, var3, var10); 
	vxor(var12, var8, var11); 
	vsel(var8, var6, var10, var3); 
	vsel(var13, var8, var12, var2); 
	vnot(var2, var13); 
	vsel(var14, var12, var2, var0); 
	vxor(*out2, *out2, var14); 
	vxor(var14, var9, var12); 
	vsel(var12, var1, var7, var11); 
	vsel(var11, var13, var1, var4); 
	vsel(var13, var14, var12, var11); 
	vxor(var14, var9, var2); 
	vsel(var2, var14, var8, var6); 
	vxor(var8, var12, var2); 
	vxor(var15, var11, var8); 
	vsel(var16, var3, var5, var7); 
	vsel(var7, var14, var16, var10); 
	vsel(var10, var8, var5, var14); 
	vsel(var14, var7, var11, var10); 
	vsel(var7, var14, var15, var0); 
	vxor(*out1, *out1, var7); 
	vsel(var7, var2, var8, var4); 
	vsel(var4, var16, var9, var3); 
	vsel(var3, var7, var14, var4); 
	vsel(var7, var6, var3, var0); 
	vxor(*out4, *out4, var7); 
	vsel(var3, var2, var1, var12); 
	vsel(var1, var3, var4, var5); 
	vxor(var2, var11, var1); 
	vsel(var1, var2, var13, var0); 
	vxor(*out3, *out3, var1); 
} 

void s4(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13;
	
	vsel(var6, var4, var2, var0); 
	vsel(var7, var6, var0, var3); 
	vxor(var8, var2, var7); 
	vsel(var9, var0, var8, var1); 
	vsel(var8, var2, var4, var0); 
	vxor(var10, var3, var8); 
	vsel(var11, var10, var2, var4); 
	vxor(var2, var9, var11); 
	vnot(var4, var2); 
	vsel(var9, var3, var1, var7); 
	vxor(var7, var0, var6); 
	vsel(var0, var4, var9, var7); 
	vxor(var6, var8, var0); 
	vnot(var0, var6); 
	vsel(var12, var7, var0, var3); 
	vsel(var13, var11, var10, var8); 
	vsel(var8, var4, var13, var1); 
	vxor(var11, var12, var8); 
	vsel(var8, var11, var2, var5); 
	vxor(*out3, *out3, var8); 
	vsel(var2, var4, var11, var5); 
	vxor(*out4, *out4, var2); 
	vsel(var2, var1, var3, var10); 
	vsel(var1, var9, var2, var7); 
	vxor(var2, var0, var1); 
	vxor(var1, var11, var2); 
	vsel(var2, var0, var1, var5); 
	vxor(*out1, *out1, var2); 
	vsel(var0, var1, var6, var5); 
	vxor(*out2, *out2, var0); 
} 

void s5(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16; 
	vtype var17; 
	vtype var18; 
	vtype var19;
	
	vsel(var6, var0, var2, var4); 
	vnot(var7, var6); 
	vsel(var8, var7, var0, var2); 
	vxor(var9, var1, var8); 
	vxor(var10, var4, var5); 
	vxor(var11, var9, var10); 
	vsel(var12, var2, var7, var1); 
	vsel(var2, var1, var11, var9); 
	vsel(var13, var5, var6, var2); 
	vsel(var14, var13, var4, var0); 
	vxor(var15, var12, var14); 
	vsel(var16, var10, var15, var9); 
	vsel(var17, var5, var0, var16); 
	vsel(var18, var2, var5, var17); 
	vxor(var2, var15, var18); 
	vsel(var19, var2, var15, var3); 
	vxor(*out3, *out3, var19); 
	vsel(var15, var7, var13, var16); 
	vsel(var7, var18, var6, var0); 
	vxor(var0, var15, var7); 
	vsel(var6, var0, var11, var3); 
	vxor(*out2, *out2, var6); 
	vsel(var6, var0, var7, var5); 
	vsel(var13, var6, var14, var1); 
	vsel(var14, var12, var1, var11); 
	vsel(var1, var13, var14, var0); 
	vsel(var16, var4, var0, var11); 
	vsel(var0, var9, var2, var15); 
	vsel(var2, var16, var0, var13); 
	vsel(var0, var18, var13, var14); 
	vsel(var4, var7, var10, var16); 
	vxor(var7, var0, var4); 
	vsel(var0, var1, var7, var3); 
	vxor(*out4, *out4, var0); 
	vsel(var0, var12, var8, var5); 
	vsel(var1, var9, var11, var17); 
	vsel(var4, var0, var1, var6); 
	vsel(var0, var4, var2, var3); 
	vxor(*out1, *out1, var0); 
} 

void s6(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16; 

	vsel(var6, var0, var3, var4); 
	vxor(var7, var1, var6); 
	vsel(var8, var7, var3, var2); 
	vxor(var9, var0, var8); 
	vxor(var10, var4, var9); 
	vnot(var11, var10); 
	vsel(var12, var9, var10, var3); 
	vsel(var13, var2, var3, var12); 
	vxor(var14, var7, var13); 
	vxor(var7, var10, var14); 
	vsel(var15, var3, var9, var12); 
	vxor(var12, var2, var15); 
	vsel(var15, var3, var2, var10); 
	vsel(var2, var12, var15, var14); 
	vsel(var3, var11, var15, var14); 
	vsel(var14, var4, var12, var2); 
	vsel(var16, var3, var10, var14); 
	vsel(var14, var11, var16, var5); 
	vxor(*out1, *out1, var14); 
	vsel(var11, var9, var16, var1); 
	vsel(var1, var0, var3, var11); 
	vxor(var0, var7, var1); 
	vsel(var9, var7, var0, var5); 
	vxor(*out4, *out4, var9); 
	vsel(var7, var12, var8, var10); 
	vsel(var9, var7, var15, var13); 
	vxor(var10, var0, var9); 
	vxor(var9, var6, var10); 
	vsel(var6, var4, var16, var3); 
	vsel(var3, var9, var10, var6); 
	vnot(var4, var3); 
	vsel(var3, var4, var9, var5); 
	vxor(*out2, *out2, var3); 
	vsel(var3, var6, var0, var10); 
	vsel(var0, var1, var7, var8); 
	vxor(var1, var3, var0); 
	vsel(var0, var2, var1, var5); 
	vxor(*out3, *out3, var0); 
}                      

void s7(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16; 
	
	vsel(var6, var1, var5, var2); 
	vxor(var7, var3, var6); 
	vsel(var6, var2, var4, var1); 
	vsel(var8, var5, var1, var3); 
	vsel(var9, var6, var8, var4); 
	vxor(var6, var7, var9); 
	vxor(var10, var4, var5); 
	vxor(var11, var1, var2); 
	vsel(var12, var2, var9, var3); 
	vsel(var9, var11, var12, var7); 
	vxor(var13, var10, var9); 
	vsel(var14, var13, var6, var0); 
	vxor(*out1, *out1, var14); 
	vxor(var14, var1, var13); 
	vsel(var15, var14, var4, var11); 
	vsel(var16, var13, var15, var5); 
	vsel(var15, var7, var14, var5); 
	vsel(var5, var15, var11, var10); 
	vxor(var10, var8, var5); 
	vsel(var5, var7, var10, var1); 
	vnot(var1, var4); 
	vsel(var4, var1, var14, var12); 
	vxor(var1, var5, var4); 
	vsel(var7, var1, var16, var0); 
	vxor(*out2, *out2, var7); 
	vxor(var7, var11, var1); 
	vsel(var1, var16, var7, var5); 
	vsel(var5, var1, var6, var4); 
	vsel(var1, var5, var10, var0); 
	vxor(*out3, *out3, var1); 
	vsel(var1, var14, var13, var9); 
	vxor(var4, var14, var7); 
	vsel(var5, var1, var4, var3); 
	vsel(var1, var16, var6, var13); 
	vsel(var3, var5, var2, var1); 
	vnot(var1, var3); 
	vsel(var2, var5, var1, var0); 
	vxor(*out4, *out4, var2); 
}                     

void s8(vtype var0, vtype var1, vtype var2, vtype var3, vtype var4, vtype var5, DES_DATA_BLOCKS_SPACE vtype *out1, DES_DATA_BLOCKS_SPACE vtype *out2, DES_DATA_BLOCKS_SPACE vtype *out3, DES_DATA_BLOCKS_SPACE vtype *out4)
{
	vtype var6; 
	vtype var7; 
	vtype var8; 
	vtype var9; 
	vtype var10; 
	vtype var11; 
	vtype var12; 
	vtype var13; 
	vtype var14; 
	vtype var15; 
	vtype var16; 
	vtype var17; 
	vtype var18; 
	vtype var19;
	
	vsel(var6, var4, var0, var2); 
	vxor(var7, var3, var6); 
	vsel(var6, var2, var3, var4); 
	vsel(var8, var1, var4, var0); 
	vsel(var9, var7, var6, var8); 
	vxor(var6, var1, var9); 
	vsel(var8, var7, var3, var2); 
	vsel(var3, var4, var8, var1); 
	vsel(var10, var0, var6, var3); 
	vsel(var11, var2, var4, var1); 
	vxor(var2, var10, var11); 
	vsel(var12, var6, var4, var7); 
	vsel(var7, var12, var0, var8); 
	vxor(var8, var2, var7); 
	vsel(var12, var8, var2, var5); 
	vxor(*out3, *out3, var12); 
	vsel(var12, var11, var8, var4); 
	vxor(var4, var3, var12); 
	vxor(var3, var6, var4); 
	vnot(var8, var3); 
	vsel(var13, var9, var1, var12); 
	vsel(var12, var8, var13, var7); 
	vxor(var14, var4, var12); 
	vsel(var4, var14, var6, var5); 
	vxor(*out2, *out2, var4); 
	vsel(var4, var10, var11, var13); 
	vsel(var6, var9, var4, var2); 
	vxor(var4, var8, var6); 
	vsel(var6, var8, var4, var5); 
	vxor(*out4, *out4, var6); 
	vsel(var4, var9, var1, var2); 
	vor(var1, var0, var7); 
	vxor(var0, var4, var1); 
	vxor(var1, var12, var0); 
	vsel(var0, var1, var3, var5); 
	vxor(*out1, *out1, var0); 
}

#define z(r) (db + (r))

#define K00XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  0)) ? (~(val)) : (val))
#define K01XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  1)) ? (~(val)) : (val))
#define K02XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  2)) ? (~(val)) : (val))
#define K03XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  3)) ? (~(val)) : (val))
#define K04XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  4)) ? (~(val)) : (val))
#define K05XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  5)) ? (~(val)) : (val))
#define K06XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  6)) ? (~(val)) : (val))

/*
#define K07XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  7)) ? (~(val)) : (val))
#define K08XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  8)) ? (~(val)) : (val))
#define K09XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U <<  9)) ? (~(val)) : (val))
#define K10XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 10)) ? (~(val)) : (val))
#define K11XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 11)) ? (~(val)) : (val))
#define K12XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 12)) ? (~(val)) : (val))
#define K13XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 13)) ? (~(val)) : (val))

#define K14XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 14)) ? (~(val)) : (val))
#define K15XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 15)) ? (~(val)) : (val))
#define K16XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 16)) ? (~(val)) : (val))
#define K17XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 17)) ? (~(val)) : (val))
#define K18XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 18)) ? (~(val)) : (val))
#define K19XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 19)) ? (~(val)) : (val))
#define K20XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 20)) ? (~(val)) : (val))
*/

#define K21XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 21)) ? (~(val)) : (val))
#define K22XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 22)) ? (~(val)) : (val))
#define K23XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 23)) ? (~(val)) : (val))
#define K24XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 24)) ? (~(val)) : (val))
#define K25XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 25)) ? (~(val)) : (val))
#define K26XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 26)) ? (~(val)) : (val))
#define K27XOR(dest, val) (dest) = ((keyFrom00To27 & (0x1U << 27)) ? (~(val)) : (val))

#define K28XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (28 - 28))) ? (~(val)) : (val))
#define K29XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (29 - 28))) ? (~(val)) : (val))
#define K30XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (30 - 28))) ? (~(val)) : (val))
#define K31XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (31 - 28))) ? (~(val)) : (val))
#define K32XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (32 - 28))) ? (~(val)) : (val))
#define K33XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (33 - 28))) ? (~(val)) : (val))
#define K34XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (34 - 28))) ? (~(val)) : (val))

#define K35XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (35 - 28))) ? (~(val)) : (val))
#define K36XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (36 - 28))) ? (~(val)) : (val))
#define K37XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (37 - 28))) ? (~(val)) : (val))
#define K38XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (38 - 28))) ? (~(val)) : (val))
#define K39XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (39 - 28))) ? (~(val)) : (val))
#define K40XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (40 - 28))) ? (~(val)) : (val))
#define K41XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (41 - 28))) ? (~(val)) : (val))

#define K42XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (42 - 28))) ? (~(val)) : (val))
#define K43XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (43 - 28))) ? (~(val)) : (val))
#define K44XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (44 - 28))) ? (~(val)) : (val))
#define K45XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (45 - 28))) ? (~(val)) : (val))
#define K46XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (46 - 28))) ? (~(val)) : (val))
#define K47XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (47 - 28))) ? (~(val)) : (val))
#define K48XOR(dest, val) (dest) = ((keyFrom28To48 & (0x1U << (48 - 28))) ? (~(val)) : (val))

void DES_Crypt(DES_DATA_BLOCKS_SPACE vtype *db, unsigned int keyFrom00To27, unsigned int keyFrom28To48)
{
	for (int i = 0; i < 64; ++i)
		db[i] = 0x00000000;

	int iterations           = 25;
	int roundsAndSwapped     = 8; 
	int round = 0;
	vtype DB00, DB01, DB02, DB03, DB04, DB05;
	vtype DB10, DB11, DB12, DB13, DB14, DB15;

start:
	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K12XOR(DB00, db[EF00]); K46XOR(DB01, db[EF01]); K33XOR(DB02, db[EF02]); K52XOR(DB03, db[EF03]); K48XOR(DB04, db[EF04]); K20XOR(DB05, db[EF05]);
					K34XOR(DB10, db[EF06]); K55XOR(DB11, db[EF07]); K05XOR(DB12, db[EF08]); K13XOR(DB13, db[EF09]); K18XOR(DB14, db[EF10]); K40XOR(DB15, db[EF11]);
				} else {
					K05XOR(DB00, db[EF00]); K39XOR(DB01, db[EF01]); K26XOR(DB02, db[EF02]); K45XOR(DB03, db[EF03]); K41XOR(DB04, db[EF04]); K13XOR(DB05, db[EF05]);
					K27XOR(DB10, db[EF06]); K48XOR(DB11, db[EF07]); K53XOR(DB12, db[EF08]); K06XOR(DB13, db[EF09]); K11XOR(DB14, db[EF10]); K33XOR(DB15, db[EF11]);
				}
			} else {
				if (round == 2) {
					K46XOR(DB00, db[EF00]); K25XOR(DB01, db[EF01]); K12XOR(DB02, db[EF02]); K31XOR(DB03, db[EF03]); K27XOR(DB04, db[EF04]); K54XOR(DB05, db[EF05]);
					K13XOR(DB10, db[EF06]); K34XOR(DB11, db[EF07]); K39XOR(DB12, db[EF08]); K47XOR(DB13, db[EF09]); K52XOR(DB14, db[EF10]); K19XOR(DB15, db[EF11]);
				} else {
					K32XOR(DB00, db[EF00]); K11XOR(DB01, db[EF01]); K53XOR(DB02, db[EF02]); K48XOR(DB03, db[EF03]); K13XOR(DB04, db[EF04]); K40XOR(DB05, db[EF05]);
					K54XOR(DB10, db[EF06]); K20XOR(DB11, db[EF07]); K25XOR(DB12, db[EF08]); K33XOR(DB13, db[EF09]); K38XOR(DB14, db[EF10]); K05XOR(DB15, db[EF11]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K18XOR(DB00, db[EF00]); K52XOR(DB01, db[EF01]); K39XOR(DB02, db[EF02]); K34XOR(DB03, db[EF03]); K54XOR(DB04, db[EF04]); K26XOR(DB05, db[EF05]);
					K40XOR(DB10, db[EF06]); K06XOR(DB11, db[EF07]); K11XOR(DB12, db[EF08]); K19XOR(DB13, db[EF09]); K55XOR(DB14, db[EF10]); K46XOR(DB15, db[EF11]);
				} else {
					K04XOR(DB00, db[EF00]); K38XOR(DB01, db[EF01]); K25XOR(DB02, db[EF02]); K20XOR(DB03, db[EF03]); K40XOR(DB04, db[EF04]); K12XOR(DB05, db[EF05]);
					K26XOR(DB10, db[EF06]); K47XOR(DB11, db[EF07]); K52XOR(DB12, db[EF08]); K05XOR(DB13, db[EF09]); K41XOR(DB14, db[EF10]); K32XOR(DB15, db[EF11]);
				}
			} else {
				if (round == 6) {
					K45XOR(DB00, db[EF00]); K55XOR(DB01, db[EF01]); K11XOR(DB02, db[EF02]); K06XOR(DB03, db[EF03]); K26XOR(DB04, db[EF04]); K53XOR(DB05, db[EF05]);
					K12XOR(DB10, db[EF06]); K33XOR(DB11, db[EF07]); K38XOR(DB12, db[EF08]); K46XOR(DB13, db[EF09]); K27XOR(DB14, db[EF10]); K18XOR(DB15, db[EF11]);
				} else {
					K31XOR(DB00, db[EF00]); K41XOR(DB01, db[EF01]); K52XOR(DB02, db[EF02]); K47XOR(DB03, db[EF03]); K12XOR(DB04, db[EF04]); K39XOR(DB05, db[EF05]);
					K53XOR(DB10, db[EF06]); K19XOR(DB11, db[EF07]); K55XOR(DB12, db[EF08]); K32XOR(DB13, db[EF09]); K13XOR(DB14, db[EF10]); K04XOR(DB15, db[EF11]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K55XOR(DB00, db[EF00]); K34XOR(DB01, db[EF01]); K45XOR(DB02, db[EF02]); K40XOR(DB03, db[EF03]); K05XOR(DB04, db[EF04]); K32XOR(DB05, db[EF05]);
					K46XOR(DB10, db[EF06]); K12XOR(DB11, db[EF07]); K48XOR(DB12, db[EF08]); K25XOR(DB13, db[EF09]); K06XOR(DB14, db[EF10]); K52XOR(DB15, db[EF11]);
				} else {
					K41XOR(DB00, db[EF00]); K20XOR(DB01, db[EF01]); K31XOR(DB02, db[EF02]); K26XOR(DB03, db[EF03]); K46XOR(DB04, db[EF04]); K18XOR(DB05, db[EF05]);
					K32XOR(DB10, db[EF06]); K53XOR(DB11, db[EF07]); K34XOR(DB12, db[EF08]); K11XOR(DB13, db[EF09]); K47XOR(DB14, db[EF10]); K38XOR(DB15, db[EF11]);
				}
			} else {
				if (round == 10) {
					K27XOR(DB00, db[EF00]); K06XOR(DB01, db[EF01]); K48XOR(DB02, db[EF02]); K12XOR(DB03, db[EF03]); K32XOR(DB04, db[EF04]); K04XOR(DB05, db[EF05]);
					K18XOR(DB10, db[EF06]); K39XOR(DB11, db[EF07]); K20XOR(DB12, db[EF08]); K52XOR(DB13, db[EF09]); K33XOR(DB14, db[EF10]); K55XOR(DB15, db[EF11]);
				} else {
					K13XOR(DB00, db[EF00]); K47XOR(DB01, db[EF01]); K34XOR(DB02, db[EF02]); K53XOR(DB03, db[EF03]); K18XOR(DB04, db[EF04]); K45XOR(DB05, db[EF05]);
					K04XOR(DB10, db[EF06]); K25XOR(DB11, db[EF07]); K06XOR(DB12, db[EF08]); K38XOR(DB13, db[EF09]); K19XOR(DB14, db[EF10]); K41XOR(DB15, db[EF11]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K54XOR(DB00, db[EF00]); K33XOR(DB01, db[EF01]); K20XOR(DB02, db[EF02]); K39XOR(DB03, db[EF03]); K04XOR(DB04, db[EF04]); K31XOR(DB05, db[EF05]);
					K45XOR(DB10, db[EF06]); K11XOR(DB11, db[EF07]); K47XOR(DB12, db[EF08]); K55XOR(DB13, db[EF09]); K05XOR(DB14, db[EF10]); K27XOR(DB15, db[EF11]);
				} else {
					K40XOR(DB00, db[EF00]); K19XOR(DB01, db[EF01]); K06XOR(DB02, db[EF02]); K25XOR(DB03, db[EF03]); K45XOR(DB04, db[EF04]); K48XOR(DB05, db[EF05]);
					K31XOR(DB10, db[EF06]); K52XOR(DB11, db[EF07]); K33XOR(DB12, db[EF08]); K41XOR(DB13, db[EF09]); K46XOR(DB14, db[EF10]); K13XOR(DB15, db[EF11]);
				}
			} else {
				if (round == 14) {
					K26XOR(DB00, db[EF00]); K05XOR(DB01, db[EF01]); K47XOR(DB02, db[EF02]); K11XOR(DB03, db[EF03]); K31XOR(DB04, db[EF04]); K34XOR(DB05, db[EF05]);
					K48XOR(DB10, db[EF06]); K38XOR(DB11, db[EF07]); K19XOR(DB12, db[EF08]); K27XOR(DB13, db[EF09]); K32XOR(DB14, db[EF10]); K54XOR(DB15, db[EF11]);
				} else {
					K19XOR(DB00, db[EF00]); K53XOR(DB01, db[EF01]); K40XOR(DB02, db[EF02]); K04XOR(DB03, db[EF03]); K55XOR(DB04, db[EF04]); K27XOR(DB05, db[EF05]);
					K41XOR(DB10, db[EF06]); K31XOR(DB11, db[EF07]); K12XOR(DB12, db[EF08]); K20XOR(DB13, db[EF09]); K25XOR(DB14, db[EF10]); K47XOR(DB15, db[EF11]);
				}
			}
		}	
	}
	s1(DB00, DB01, DB02, DB03, DB04, DB05, z(40), z(48), z(54), z(62));
    s2(DB10, DB11, DB12, DB13, DB14, DB15, z(44), z(59), z(33), z(49)); 

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K04XOR(DB00, db[   7]); K32XOR(DB01, db[   8]); K26XOR(DB02, db[   9]); K27XOR(DB03, db[  10]); K38XOR(DB04, db[  11]); K54XOR(DB05, db[  12]);
					K53XOR(DB10, db[  11]); K06XOR(DB11, db[  12]); K31XOR(DB12, db[  13]); K25XOR(DB13, db[  14]); K19XOR(DB14, db[  15]); K41XOR(DB15, db[  16]);
				} else {
					K52XOR(DB00, db[   7]); K25XOR(DB01, db[   8]); K19XOR(DB02, db[   9]); K20XOR(DB03, db[  10]); K31XOR(DB04, db[  11]); K47XOR(DB05, db[  12]);
					K46XOR(DB10, db[  11]); K54XOR(DB11, db[  12]); K55XOR(DB12, db[  13]); K18XOR(DB13, db[  14]); K12XOR(DB14, db[  15]); K34XOR(DB15, db[  16]);
				}
			} else {
				if (round == 2) {
					K38XOR(DB00, db[   7]); K11XOR(DB01, db[   8]); K05XOR(DB02, db[   9]); K06XOR(DB03, db[  10]); K48XOR(DB04, db[  11]); K33XOR(DB05, db[  12]);
					K32XOR(DB10, db[  11]); K40XOR(DB11, db[  12]); K41XOR(DB12, db[  13]); K04XOR(DB13, db[  14]); K53XOR(DB14, db[  15]); K20XOR(DB15, db[  16]);
				} else {
					K55XOR(DB00, db[   7]); K52XOR(DB01, db[   8]); K46XOR(DB02, db[   9]); K47XOR(DB03, db[  10]); K34XOR(DB04, db[  11]); K19XOR(DB05, db[  12]);
					K18XOR(DB10, db[  11]); K26XOR(DB11, db[  12]); K27XOR(DB12, db[  13]); K45XOR(DB13, db[  14]); K39XOR(DB14, db[  15]); K06XOR(DB15, db[  16]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K41XOR(DB00, db[   7]); K38XOR(DB01, db[   8]); K32XOR(DB02, db[   9]); K33XOR(DB03, db[  10]); K20XOR(DB04, db[  11]); K05XOR(DB05, db[  12]);
					K04XOR(DB10, db[  11]); K12XOR(DB11, db[  12]); K13XOR(DB12, db[  13]); K31XOR(DB13, db[  14]); K25XOR(DB14, db[  15]); K47XOR(DB15, db[  16]);
				} else {
					K27XOR(DB00, db[   7]); K55XOR(DB01, db[   8]); K18XOR(DB02, db[   9]); K19XOR(DB03, db[  10]); K06XOR(DB04, db[  11]); K46XOR(DB05, db[  12]);
					K45XOR(DB10, db[  11]); K53XOR(DB11, db[  12]); K54XOR(DB12, db[  13]); K48XOR(DB13, db[  14]); K11XOR(DB14, db[  15]); K33XOR(DB15, db[  16]);
				}
			} else {
				if (round == 6) {
					K13XOR(DB00, db[   7]); K41XOR(DB01, db[   8]); K04XOR(DB02, db[   9]); K05XOR(DB03, db[  10]); K47XOR(DB04, db[  11]); K32XOR(DB05, db[  12]);
					K31XOR(DB10, db[  11]); K39XOR(DB11, db[  12]); K40XOR(DB12, db[  13]); K34XOR(DB13, db[  14]); K52XOR(DB14, db[  15]); K19XOR(DB15, db[  16]);
				} else {
					K54XOR(DB00, db[   7]); K27XOR(DB01, db[   8]); K45XOR(DB02, db[   9]); K46XOR(DB03, db[  10]); K33XOR(DB04, db[  11]); K18XOR(DB05, db[  12]);
					K48XOR(DB10, db[  11]); K25XOR(DB11, db[  12]); K26XOR(DB12, db[  13]); K20XOR(DB13, db[  14]); K38XOR(DB14, db[  15]); K05XOR(DB15, db[  16]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K47XOR(DB00, db[   7]); K20XOR(DB01, db[   8]); K38XOR(DB02, db[   9]); K39XOR(DB03, db[  10]); K26XOR(DB04, db[  11]); K11XOR(DB05, db[  12]);
					K41XOR(DB10, db[  11]); K18XOR(DB11, db[  12]); K19XOR(DB12, db[  13]); K13XOR(DB13, db[  14]); K31XOR(DB14, db[  15]); K53XOR(DB15, db[  16]);
				} else {
					K33XOR(DB00, db[   7]); K06XOR(DB01, db[   8]); K55XOR(DB02, db[   9]); K25XOR(DB03, db[  10]); K12XOR(DB04, db[  11]); K52XOR(DB05, db[  12]);
					K27XOR(DB10, db[  11]); K04XOR(DB11, db[  12]); K05XOR(DB12, db[  13]); K54XOR(DB13, db[  14]); K48XOR(DB14, db[  15]); K39XOR(DB15, db[  16]);
				}
			} else {
				if (round == 10) {
					K19XOR(DB00, db[   7]); K47XOR(DB01, db[   8]); K41XOR(DB02, db[   9]); K11XOR(DB03, db[  10]); K53XOR(DB04, db[  11]); K38XOR(DB05, db[  12]);
					K13XOR(DB10, db[  11]); K45XOR(DB11, db[  12]); K46XOR(DB12, db[  13]); K40XOR(DB13, db[  14]); K34XOR(DB14, db[  15]); K25XOR(DB15, db[  16]);
				} else {
					K05XOR(DB00, db[   7]); K33XOR(DB01, db[   8]); K27XOR(DB02, db[   9]); K52XOR(DB03, db[  10]); K39XOR(DB04, db[  11]); K55XOR(DB05, db[  12]);
					K54XOR(DB10, db[  11]); K31XOR(DB11, db[  12]); K32XOR(DB12, db[  13]); K26XOR(DB13, db[  14]); K20XOR(DB14, db[  15]); K11XOR(DB15, db[  16]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K46XOR(DB00, db[   7]); K19XOR(DB01, db[   8]); K13XOR(DB02, db[   9]); K38XOR(DB03, db[  10]); K25XOR(DB04, db[  11]); K41XOR(DB05, db[  12]);
					K40XOR(DB10, db[  11]); K48XOR(DB11, db[  12]); K18XOR(DB12, db[  13]); K12XOR(DB13, db[  14]); K06XOR(DB14, db[  15]); K52XOR(DB15, db[  16]);
				} else {
					K32XOR(DB00, db[   7]); K05XOR(DB01, db[   8]); K54XOR(DB02, db[   9]); K55XOR(DB03, db[  10]); K11XOR(DB04, db[  11]); K27XOR(DB05, db[  12]);
					K26XOR(DB10, db[  11]); K34XOR(DB11, db[  12]); K04XOR(DB12, db[  13]); K53XOR(DB13, db[  14]); K47XOR(DB14, db[  15]); K38XOR(DB15, db[  16]);
				}
			} else {
				if (round == 14) {
					K18XOR(DB00, db[   7]); K46XOR(DB01, db[   8]); K40XOR(DB02, db[   9]); K41XOR(DB03, db[  10]); K52XOR(DB04, db[  11]); K13XOR(DB05, db[  12]);
					K12XOR(DB10, db[  11]); K20XOR(DB11, db[  12]); K45XOR(DB12, db[  13]); K39XOR(DB13, db[  14]); K33XOR(DB14, db[  15]); K55XOR(DB15, db[  16]);
				} else {
					K11XOR(DB00, db[   7]); K39XOR(DB01, db[   8]); K33XOR(DB02, db[   9]); K34XOR(DB03, db[  10]); K45XOR(DB04, db[  11]); K06XOR(DB05, db[  12]);
					K05XOR(DB10, db[  11]); K13XOR(DB11, db[  12]); K38XOR(DB12, db[  13]); K32XOR(DB13, db[  14]); K26XOR(DB14, db[  15]); K48XOR(DB15, db[  16]);
				}
			}
		}	
	}
	s3(DB00, DB01, DB02, DB03, DB04, DB05, z(55), z(47), z(61), z(37));
	s4(DB10, DB11, DB12, DB13, DB14, DB15, z(57), z(51), z(41), z(32));

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K15XOR(DB00, db[EF24]); K24XOR(DB01, db[EF25]); K28XOR(DB02, db[EF26]); K43XOR(DB03, db[EF27]); K30XOR(DB04, db[EF28]); K03XOR(DB05, db[EF29]);
					K35XOR(DB10, db[EF30]); K22XOR(DB11, db[EF31]); K02XOR(DB12, db[EF32]); K44XOR(DB13, db[EF33]); K14XOR(DB14, db[EF34]); K23XOR(DB15, db[EF35]);
				} else {
					K08XOR(DB00, db[EF24]); K17XOR(DB01, db[EF25]); K21XOR(DB02, db[EF26]); K36XOR(DB03, db[EF27]); K23XOR(DB04, db[EF28]); K49XOR(DB05, db[EF29]);
					K28XOR(DB10, db[EF30]); K15XOR(DB11, db[EF31]); K24XOR(DB12, db[EF32]); K37XOR(DB13, db[EF33]); K07XOR(DB14, db[EF34]); K16XOR(DB15, db[EF35]);
				}
			} else {
				if (round == 2) {
					K51XOR(DB00, db[EF24]); K03XOR(DB01, db[EF25]); K07XOR(DB02, db[EF26]); K22XOR(DB03, db[EF27]); K09XOR(DB04, db[EF28]); K35XOR(DB05, db[EF29]);
					K14XOR(DB10, db[EF30]); K01XOR(DB11, db[EF31]); K10XOR(DB12, db[EF32]); K23XOR(DB13, db[EF33]); K50XOR(DB14, db[EF34]); K02XOR(DB15, db[EF35]);
				} else {
					K37XOR(DB00, db[EF24]); K42XOR(DB01, db[EF25]); K50XOR(DB02, db[EF26]); K08XOR(DB03, db[EF27]); K24XOR(DB04, db[EF28]); K21XOR(DB05, db[EF29]);
					K00XOR(DB10, db[EF30]); K44XOR(DB11, db[EF31]); K49XOR(DB12, db[EF32]); K09XOR(DB13, db[EF33]); K36XOR(DB14, db[EF34]); K17XOR(DB15, db[EF35]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K23XOR(DB00, db[EF24]); K28XOR(DB01, db[EF25]); K36XOR(DB02, db[EF26]); K51XOR(DB03, db[EF27]); K10XOR(DB04, db[EF28]); K07XOR(DB05, db[EF29]);
					K43XOR(DB10, db[EF30]); K30XOR(DB11, db[EF31]); K35XOR(DB12, db[EF32]); K24XOR(DB13, db[EF33]); K22XOR(DB14, db[EF34]); K03XOR(DB15, db[EF35]);
				} else {
					K09XOR(DB00, db[EF24]); K14XOR(DB01, db[EF25]); K22XOR(DB02, db[EF26]); K37XOR(DB03, db[EF27]); K49XOR(DB04, db[EF28]); K50XOR(DB05, db[EF29]);
					K29XOR(DB10, db[EF30]); K16XOR(DB11, db[EF31]); K21XOR(DB12, db[EF32]); K10XOR(DB13, db[EF33]); K08XOR(DB14, db[EF34]); K42XOR(DB15, db[EF35]);
				}
			} else {
				if (round == 6) {
					K24XOR(DB00, db[EF24]); K00XOR(DB01, db[EF25]); K08XOR(DB02, db[EF26]); K23XOR(DB03, db[EF27]); K35XOR(DB04, db[EF28]); K36XOR(DB05, db[EF29]);
					K15XOR(DB10, db[EF30]); K02XOR(DB11, db[EF31]); K07XOR(DB12, db[EF32]); K49XOR(DB13, db[EF33]); K51XOR(DB14, db[EF34]); K28XOR(DB15, db[EF35]);
				} else {
					K10XOR(DB00, db[EF24]); K43XOR(DB01, db[EF25]); K51XOR(DB02, db[EF26]); K09XOR(DB03, db[EF27]); K21XOR(DB04, db[EF28]); K22XOR(DB05, db[EF29]);
					K01XOR(DB10, db[EF30]); K17XOR(DB11, db[EF31]); K50XOR(DB12, db[EF32]); K35XOR(DB13, db[EF33]); K37XOR(DB14, db[EF34]); K14XOR(DB15, db[EF35]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K03XOR(DB00, db[EF24]); K36XOR(DB01, db[EF25]); K44XOR(DB02, db[EF26]); K02XOR(DB03, db[EF27]); K14XOR(DB04, db[EF28]); K15XOR(DB05, db[EF29]);
					K51XOR(DB10, db[EF30]); K10XOR(DB11, db[EF31]); K43XOR(DB12, db[EF32]); K28XOR(DB13, db[EF33]); K30XOR(DB14, db[EF34]); K07XOR(DB15, db[EF35]);
				} else {
					K42XOR(DB00, db[EF24]); K22XOR(DB01, db[EF25]); K30XOR(DB02, db[EF26]); K17XOR(DB03, db[EF27]); K00XOR(DB04, db[EF28]); K01XOR(DB05, db[EF29]);
					K37XOR(DB10, db[EF30]); K49XOR(DB11, db[EF31]); K29XOR(DB12, db[EF32]); K14XOR(DB13, db[EF33]); K16XOR(DB14, db[EF34]); K50XOR(DB15, db[EF35]);
				}
			} else {
				if (round == 10) {
					K28XOR(DB00, db[EF24]); K08XOR(DB01, db[EF25]); K16XOR(DB02, db[EF26]); K03XOR(DB03, db[EF27]); K43XOR(DB04, db[EF28]); K44XOR(DB05, db[EF29]);
					K23XOR(DB10, db[EF30]); K35XOR(DB11, db[EF31]); K15XOR(DB12, db[EF32]); K00XOR(DB13, db[EF33]); K02XOR(DB14, db[EF34]); K36XOR(DB15, db[EF35]);
				} else {
					K14XOR(DB00, db[EF24]); K51XOR(DB01, db[EF25]); K02XOR(DB02, db[EF26]); K42XOR(DB03, db[EF27]); K29XOR(DB04, db[EF28]); K30XOR(DB05, db[EF29]);
					K09XOR(DB10, db[EF30]); K21XOR(DB11, db[EF31]); K01XOR(DB12, db[EF32]); K43XOR(DB13, db[EF33]); K17XOR(DB14, db[EF34]); K22XOR(DB15, db[EF35]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K00XOR(DB00, db[EF24]); K37XOR(DB01, db[EF25]); K17XOR(DB02, db[EF26]); K28XOR(DB03, db[EF27]); K15XOR(DB04, db[EF28]); K16XOR(DB05, db[EF29]);
					K24XOR(DB10, db[EF30]); K07XOR(DB11, db[EF31]); K44XOR(DB12, db[EF32]); K29XOR(DB13, db[EF33]); K03XOR(DB14, db[EF34]); K08XOR(DB15, db[EF35]);
				} else {
					K43XOR(DB00, db[EF24]); K23XOR(DB01, db[EF25]); K03XOR(DB02, db[EF26]); K14XOR(DB03, db[EF27]); K01XOR(DB04, db[EF28]); K02XOR(DB05, db[EF29]);
					K10XOR(DB10, db[EF30]); K50XOR(DB11, db[EF31]); K30XOR(DB12, db[EF32]); K15XOR(DB13, db[EF33]); K42XOR(DB14, db[EF34]); K51XOR(DB15, db[EF35]);
				}
			} else {
				if (round == 14) {
					K29XOR(DB00, db[EF24]); K09XOR(DB01, db[EF25]); K42XOR(DB02, db[EF26]); K00XOR(DB03, db[EF27]); K44XOR(DB04, db[EF28]); K17XOR(DB05, db[EF29]);
					K49XOR(DB10, db[EF30]); K36XOR(DB11, db[EF31]); K16XOR(DB12, db[EF32]); K01XOR(DB13, db[EF33]); K28XOR(DB14, db[EF34]); K37XOR(DB15, db[EF35]);
				} else {
					K22XOR(DB00, db[EF24]); K02XOR(DB01, db[EF25]); K35XOR(DB02, db[EF26]); K50XOR(DB03, db[EF27]); K37XOR(DB04, db[EF28]); K10XOR(DB05, db[EF29]);
					K42XOR(DB10, db[EF30]); K29XOR(DB11, db[EF31]); K09XOR(DB12, db[EF32]); K51XOR(DB13, db[EF33]); K21XOR(DB14, db[EF34]); K30XOR(DB15, db[EF35]);
				}
			}
		}	
	}
	s5(DB00, DB01, DB02, DB03, DB04, DB05, z(39), z(45), z(56), z(34));
	s6(DB10, DB11, DB12, DB13, DB14, DB15, z(35), z(60), z(42), z(50));

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K51XOR(DB00, db[  23]); K16XOR(DB01, db[  24]); K29XOR(DB02, db[  25]); K49XOR(DB03, db[  26]); K07XOR(DB04, db[  27]); K17XOR(DB05, db[  28]);
					K37XOR(DB10, db[  27]); K08XOR(DB11, db[  28]); K09XOR(DB12, db[  29]); K50XOR(DB13, db[  30]); K42XOR(DB14, db[  31]); K21XOR(DB15, db[   0]);
				} else {
					K44XOR(DB00, db[  23]); K09XOR(DB01, db[  24]); K22XOR(DB02, db[  25]); K42XOR(DB03, db[  26]); K00XOR(DB04, db[  27]); K10XOR(DB05, db[  28]);
					K30XOR(DB10, db[  27]); K01XOR(DB11, db[  28]); K02XOR(DB12, db[  29]); K43XOR(DB13, db[  30]); K35XOR(DB14, db[  31]); K14XOR(DB15, db[   0]);
				}
			} else {
				if (round == 2) {
					K30XOR(DB00, db[  23]); K24XOR(DB01, db[  24]); K08XOR(DB02, db[  25]); K28XOR(DB03, db[  26]); K43XOR(DB04, db[  27]); K49XOR(DB05, db[  28]);
					K16XOR(DB10, db[  27]); K44XOR(DB11, db[  28]); K17XOR(DB12, db[  29]); K29XOR(DB13, db[  30]); K21XOR(DB14, db[  31]); K00XOR(DB15, db[   0]);
				} else {
					K16XOR(DB00, db[  23]); K10XOR(DB01, db[  24]); K51XOR(DB02, db[  25]); K14XOR(DB03, db[  26]); K29XOR(DB04, db[  27]); K35XOR(DB05, db[  28]);
					K02XOR(DB10, db[  27]); K30XOR(DB11, db[  28]); K03XOR(DB12, db[  29]); K15XOR(DB13, db[  30]); K07XOR(DB14, db[  31]); K43XOR(DB15, db[   0]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K02XOR(DB00, db[  23]); K49XOR(DB01, db[  24]); K37XOR(DB02, db[  25]); K00XOR(DB03, db[  26]); K15XOR(DB04, db[  27]); K21XOR(DB05, db[  28]);
					K17XOR(DB10, db[  27]); K16XOR(DB11, db[  28]); K42XOR(DB12, db[  29]); K01XOR(DB13, db[  30]); K50XOR(DB14, db[  31]); K29XOR(DB15, db[   0]);
				} else {
					K17XOR(DB00, db[  23]); K35XOR(DB01, db[  24]); K23XOR(DB02, db[  25]); K43XOR(DB03, db[  26]); K01XOR(DB04, db[  27]); K07XOR(DB05, db[  28]);
					K03XOR(DB10, db[  27]); K02XOR(DB11, db[  28]); K28XOR(DB12, db[  29]); K44XOR(DB13, db[  30]); K36XOR(DB14, db[  31]); K15XOR(DB15, db[   0]);
				}
			} else {
				if (round == 6) {
					K03XOR(DB00, db[  23]); K21XOR(DB01, db[  24]); K09XOR(DB02, db[  25]); K29XOR(DB03, db[  26]); K44XOR(DB04, db[  27]); K50XOR(DB05, db[  28]);
					K42XOR(DB10, db[  27]); K17XOR(DB11, db[  28]); K14XOR(DB12, db[  29]); K30XOR(DB13, db[  30]); K22XOR(DB14, db[  31]); K01XOR(DB15, db[   0]);
				} else {
					K42XOR(DB00, db[  23]); K07XOR(DB01, db[  24]); K24XOR(DB02, db[  25]); K15XOR(DB03, db[  26]); K30XOR(DB04, db[  27]); K36XOR(DB05, db[  28]);
					K28XOR(DB10, db[  27]); K03XOR(DB11, db[  28]); K00XOR(DB12, db[  29]); K16XOR(DB13, db[  30]); K08XOR(DB14, db[  31]); K44XOR(DB15, db[   0]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K35XOR(DB00, db[  23]); K00XOR(DB01, db[  24]); K17XOR(DB02, db[  25]); K08XOR(DB03, db[  26]); K23XOR(DB04, db[  27]); K29XOR(DB05, db[  28]);
					K21XOR(DB10, db[  27]); K49XOR(DB11, db[  28]); K50XOR(DB12, db[  29]); K09XOR(DB13, db[  30]); K01XOR(DB14, db[  31]); K37XOR(DB15, db[   0]);
				} else {
					K21XOR(DB00, db[  23]); K43XOR(DB01, db[  24]); K03XOR(DB02, db[  25]); K51XOR(DB03, db[  26]); K09XOR(DB04, db[  27]); K15XOR(DB05, db[  28]);
					K07XOR(DB10, db[  27]); K35XOR(DB11, db[  28]); K36XOR(DB12, db[  29]); K24XOR(DB13, db[  30]); K44XOR(DB14, db[  31]); K23XOR(DB15, db[   0]);
				}
			} else {
				if (round == 10) {
					K07XOR(DB00, db[  23]); K29XOR(DB01, db[  24]); K42XOR(DB02, db[  25]); K37XOR(DB03, db[  26]); K24XOR(DB04, db[  27]); K01XOR(DB05, db[  28]);
					K50XOR(DB10, db[  27]); K21XOR(DB11, db[  28]); K22XOR(DB12, db[  29]); K10XOR(DB13, db[  30]); K30XOR(DB14, db[  31]); K09XOR(DB15, db[   0]);
				} else {
					K50XOR(DB00, db[  23]); K15XOR(DB01, db[  24]); K28XOR(DB02, db[  25]); K23XOR(DB03, db[  26]); K10XOR(DB04, db[  27]); K44XOR(DB05, db[  28]);
					K36XOR(DB10, db[  27]); K07XOR(DB11, db[  28]); K08XOR(DB12, db[  29]); K49XOR(DB13, db[  30]); K16XOR(DB14, db[  31]); K24XOR(DB15, db[   0]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K36XOR(DB00, db[  23]); K01XOR(DB01, db[  24]); K14XOR(DB02, db[  25]); K09XOR(DB03, db[  26]); K49XOR(DB04, db[  27]); K30XOR(DB05, db[  28]);
					K22XOR(DB10, db[  27]); K50XOR(DB11, db[  28]); K51XOR(DB12, db[  29]); K35XOR(DB13, db[  30]); K02XOR(DB14, db[  31]); K10XOR(DB15, db[   0]);
				} else {
					K22XOR(DB00, db[  23]); K44XOR(DB01, db[  24]); K00XOR(DB02, db[  25]); K24XOR(DB03, db[  26]); K35XOR(DB04, db[  27]); K16XOR(DB05, db[  28]);
					K08XOR(DB10, db[  27]); K36XOR(DB11, db[  28]); K37XOR(DB12, db[  29]); K21XOR(DB13, db[  30]); K17XOR(DB14, db[  31]); K49XOR(DB15, db[   0]);
				}
			} else {
				if (round == 14) {
					K08XOR(DB00, db[  23]); K30XOR(DB01, db[  24]); K43XOR(DB02, db[  25]); K10XOR(DB03, db[  26]); K21XOR(DB04, db[  27]); K02XOR(DB05, db[  28]);
					K51XOR(DB10, db[  27]); K22XOR(DB11, db[  28]); K23XOR(DB12, db[  29]); K07XOR(DB13, db[  30]); K03XOR(DB14, db[  31]); K35XOR(DB15, db[   0]);
				} else {
					K01XOR(DB00, db[  23]); K23XOR(DB01, db[  24]); K36XOR(DB02, db[  25]); K03XOR(DB03, db[  26]); K14XOR(DB04, db[  27]); K24XOR(DB05, db[  28]);
					K44XOR(DB10, db[  27]); K15XOR(DB11, db[  28]); K16XOR(DB12, db[  29]); K00XOR(DB13, db[  30]); K49XOR(DB14, db[  31]); K28XOR(DB15, db[   0]);
				}
			}
		}	
	}
	s7(DB00, DB01, DB02, DB03, DB04, DB05, z(63), z(43), z(53), z(38));
	s8(DB10, DB11, DB12, DB13, DB14, DB15, z(36), z(58), z(46), z(52));

	if (roundsAndSwapped == 0x100)
		goto next;

swap:
	++round;

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K12XOR(DB00, db[EF00+32]); K46XOR(DB01, db[EF01+32]); K33XOR(DB02, db[EF02+32]); K52XOR(DB03, db[EF03+32]); K48XOR(DB04, db[EF04+32]); K20XOR(DB05, db[EF05+32]);
					K34XOR(DB10, db[EF06+32]); K55XOR(DB11, db[EF07+32]); K05XOR(DB12, db[EF08+32]); K13XOR(DB13, db[EF09+32]); K18XOR(DB14, db[EF10+32]); K40XOR(DB15, db[EF11+32]);
				} else {
					K05XOR(DB00, db[EF00+32]); K39XOR(DB01, db[EF01+32]); K26XOR(DB02, db[EF02+32]); K45XOR(DB03, db[EF03+32]); K41XOR(DB04, db[EF04+32]); K13XOR(DB05, db[EF05+32]);
					K27XOR(DB10, db[EF06+32]); K48XOR(DB11, db[EF07+32]); K53XOR(DB12, db[EF08+32]); K06XOR(DB13, db[EF09+32]); K11XOR(DB14, db[EF10+32]); K33XOR(DB15, db[EF11+32]);
				}
			} else {
				if (round == 2) {
					K46XOR(DB00, db[EF00+32]); K25XOR(DB01, db[EF01+32]); K12XOR(DB02, db[EF02+32]); K31XOR(DB03, db[EF03+32]); K27XOR(DB04, db[EF04+32]); K54XOR(DB05, db[EF05+32]);
					K13XOR(DB10, db[EF06+32]); K34XOR(DB11, db[EF07+32]); K39XOR(DB12, db[EF08+32]); K47XOR(DB13, db[EF09+32]); K52XOR(DB14, db[EF10+32]); K19XOR(DB15, db[EF11+32]);
				} else {
					K32XOR(DB00, db[EF00+32]); K11XOR(DB01, db[EF01+32]); K53XOR(DB02, db[EF02+32]); K48XOR(DB03, db[EF03+32]); K13XOR(DB04, db[EF04+32]); K40XOR(DB05, db[EF05+32]);
					K54XOR(DB10, db[EF06+32]); K20XOR(DB11, db[EF07+32]); K25XOR(DB12, db[EF08+32]); K33XOR(DB13, db[EF09+32]); K38XOR(DB14, db[EF10+32]); K05XOR(DB15, db[EF11+32]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K18XOR(DB00, db[EF00+32]); K52XOR(DB01, db[EF01+32]); K39XOR(DB02, db[EF02+32]); K34XOR(DB03, db[EF03+32]); K54XOR(DB04, db[EF04+32]); K26XOR(DB05, db[EF05+32]);
					K40XOR(DB10, db[EF06+32]); K06XOR(DB11, db[EF07+32]); K11XOR(DB12, db[EF08+32]); K19XOR(DB13, db[EF09+32]); K55XOR(DB14, db[EF10+32]); K46XOR(DB15, db[EF11+32]);
				} else {
					K04XOR(DB00, db[EF00+32]); K38XOR(DB01, db[EF01+32]); K25XOR(DB02, db[EF02+32]); K20XOR(DB03, db[EF03+32]); K40XOR(DB04, db[EF04+32]); K12XOR(DB05, db[EF05+32]);
					K26XOR(DB10, db[EF06+32]); K47XOR(DB11, db[EF07+32]); K52XOR(DB12, db[EF08+32]); K05XOR(DB13, db[EF09+32]); K41XOR(DB14, db[EF10+32]); K32XOR(DB15, db[EF11+32]);
				}
			} else {
				if (round == 6) {
					K45XOR(DB00, db[EF00+32]); K55XOR(DB01, db[EF01+32]); K11XOR(DB02, db[EF02+32]); K06XOR(DB03, db[EF03+32]); K26XOR(DB04, db[EF04+32]); K53XOR(DB05, db[EF05+32]);
					K12XOR(DB10, db[EF06+32]); K33XOR(DB11, db[EF07+32]); K38XOR(DB12, db[EF08+32]); K46XOR(DB13, db[EF09+32]); K27XOR(DB14, db[EF10+32]); K18XOR(DB15, db[EF11+32]);
				} else {
					K31XOR(DB00, db[EF00+32]); K41XOR(DB01, db[EF01+32]); K52XOR(DB02, db[EF02+32]); K47XOR(DB03, db[EF03+32]); K12XOR(DB04, db[EF04+32]); K39XOR(DB05, db[EF05+32]);
					K53XOR(DB10, db[EF06+32]); K19XOR(DB11, db[EF07+32]); K55XOR(DB12, db[EF08+32]); K32XOR(DB13, db[EF09+32]); K13XOR(DB14, db[EF10+32]); K04XOR(DB15, db[EF11+32]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K55XOR(DB00, db[EF00+32]); K34XOR(DB01, db[EF01+32]); K45XOR(DB02, db[EF02+32]); K40XOR(DB03, db[EF03+32]); K05XOR(DB04, db[EF04+32]); K32XOR(DB05, db[EF05+32]);
					K46XOR(DB10, db[EF06+32]); K12XOR(DB11, db[EF07+32]); K48XOR(DB12, db[EF08+32]); K25XOR(DB13, db[EF09+32]); K06XOR(DB14, db[EF10+32]); K52XOR(DB15, db[EF11+32]);
				} else {
					K41XOR(DB00, db[EF00+32]); K20XOR(DB01, db[EF01+32]); K31XOR(DB02, db[EF02+32]); K26XOR(DB03, db[EF03+32]); K46XOR(DB04, db[EF04+32]); K18XOR(DB05, db[EF05+32]);
					K32XOR(DB10, db[EF06+32]); K53XOR(DB11, db[EF07+32]); K34XOR(DB12, db[EF08+32]); K11XOR(DB13, db[EF09+32]); K47XOR(DB14, db[EF10+32]); K38XOR(DB15, db[EF11+32]);
				}
			} else {
				if (round == 10) {
					K27XOR(DB00, db[EF00+32]); K06XOR(DB01, db[EF01+32]); K48XOR(DB02, db[EF02+32]); K12XOR(DB03, db[EF03+32]); K32XOR(DB04, db[EF04+32]); K04XOR(DB05, db[EF05+32]);
					K18XOR(DB10, db[EF06+32]); K39XOR(DB11, db[EF07+32]); K20XOR(DB12, db[EF08+32]); K52XOR(DB13, db[EF09+32]); K33XOR(DB14, db[EF10+32]); K55XOR(DB15, db[EF11+32]);
				} else {
					K13XOR(DB00, db[EF00+32]); K47XOR(DB01, db[EF01+32]); K34XOR(DB02, db[EF02+32]); K53XOR(DB03, db[EF03+32]); K18XOR(DB04, db[EF04+32]); K45XOR(DB05, db[EF05+32]);
					K04XOR(DB10, db[EF06+32]); K25XOR(DB11, db[EF07+32]); K06XOR(DB12, db[EF08+32]); K38XOR(DB13, db[EF09+32]); K19XOR(DB14, db[EF10+32]); K41XOR(DB15, db[EF11+32]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K54XOR(DB00, db[EF00+32]); K33XOR(DB01, db[EF01+32]); K20XOR(DB02, db[EF02+32]); K39XOR(DB03, db[EF03+32]); K04XOR(DB04, db[EF04+32]); K31XOR(DB05, db[EF05+32]);
					K45XOR(DB10, db[EF06+32]); K11XOR(DB11, db[EF07+32]); K47XOR(DB12, db[EF08+32]); K55XOR(DB13, db[EF09+32]); K05XOR(DB14, db[EF10+32]); K27XOR(DB15, db[EF11+32]);
				} else {
					K40XOR(DB00, db[EF00+32]); K19XOR(DB01, db[EF01+32]); K06XOR(DB02, db[EF02+32]); K25XOR(DB03, db[EF03+32]); K45XOR(DB04, db[EF04+32]); K48XOR(DB05, db[EF05+32]);
					K31XOR(DB10, db[EF06+32]); K52XOR(DB11, db[EF07+32]); K33XOR(DB12, db[EF08+32]); K41XOR(DB13, db[EF09+32]); K46XOR(DB14, db[EF10+32]); K13XOR(DB15, db[EF11+32]);
				}
			} else {
				if (round == 14) {
					K26XOR(DB00, db[EF00+32]); K05XOR(DB01, db[EF01+32]); K47XOR(DB02, db[EF02+32]); K11XOR(DB03, db[EF03+32]); K31XOR(DB04, db[EF04+32]); K34XOR(DB05, db[EF05+32]);
					K48XOR(DB10, db[EF06+32]); K38XOR(DB11, db[EF07+32]); K19XOR(DB12, db[EF08+32]); K27XOR(DB13, db[EF09+32]); K32XOR(DB14, db[EF10+32]); K54XOR(DB15, db[EF11+32]);
				} else {
					K19XOR(DB00, db[EF00+32]); K53XOR(DB01, db[EF01+32]); K40XOR(DB02, db[EF02+32]); K04XOR(DB03, db[EF03+32]); K55XOR(DB04, db[EF04+32]); K27XOR(DB05, db[EF05+32]);
					K41XOR(DB10, db[EF06+32]); K31XOR(DB11, db[EF07+32]); K12XOR(DB12, db[EF08+32]); K20XOR(DB13, db[EF09+32]); K25XOR(DB14, db[EF10+32]); K47XOR(DB15, db[EF11+32]);
				}
			}
		}	
	}
	s1(DB00, DB01, DB02, DB03, DB04, DB05, z(40-32), z(48-32), z(54-32), z(62-32));
    s2(DB10, DB11, DB12, DB13, DB14, DB15, z(44-32), z(59-32), z(33-32), z(49-32)); 

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K04XOR(DB00, db[   7+32]); K32XOR(DB01, db[   8+32]); K26XOR(DB02, db[   9+32]); K27XOR(DB03, db[  10+32]); K38XOR(DB04, db[  11+32]); K54XOR(DB05, db[  12+32]);
					K53XOR(DB10, db[  11+32]); K06XOR(DB11, db[  12+32]); K31XOR(DB12, db[  13+32]); K25XOR(DB13, db[  14+32]); K19XOR(DB14, db[  15+32]); K41XOR(DB15, db[  16+32]);
				} else {
					K52XOR(DB00, db[   7+32]); K25XOR(DB01, db[   8+32]); K19XOR(DB02, db[   9+32]); K20XOR(DB03, db[  10+32]); K31XOR(DB04, db[  11+32]); K47XOR(DB05, db[  12+32]);
					K46XOR(DB10, db[  11+32]); K54XOR(DB11, db[  12+32]); K55XOR(DB12, db[  13+32]); K18XOR(DB13, db[  14+32]); K12XOR(DB14, db[  15+32]); K34XOR(DB15, db[  16+32]);
				}
			} else {
				if (round == 2) {
					K38XOR(DB00, db[   7+32]); K11XOR(DB01, db[   8+32]); K05XOR(DB02, db[   9+32]); K06XOR(DB03, db[  10+32]); K48XOR(DB04, db[  11+32]); K33XOR(DB05, db[  12+32]);
					K32XOR(DB10, db[  11+32]); K40XOR(DB11, db[  12+32]); K41XOR(DB12, db[  13+32]); K04XOR(DB13, db[  14+32]); K53XOR(DB14, db[  15+32]); K20XOR(DB15, db[  16+32]);
				} else {
					K55XOR(DB00, db[   7+32]); K52XOR(DB01, db[   8+32]); K46XOR(DB02, db[   9+32]); K47XOR(DB03, db[  10+32]); K34XOR(DB04, db[  11+32]); K19XOR(DB05, db[  12+32]);
					K18XOR(DB10, db[  11+32]); K26XOR(DB11, db[  12+32]); K27XOR(DB12, db[  13+32]); K45XOR(DB13, db[  14+32]); K39XOR(DB14, db[  15+32]); K06XOR(DB15, db[  16+32]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K41XOR(DB00, db[   7+32]); K38XOR(DB01, db[   8+32]); K32XOR(DB02, db[   9+32]); K33XOR(DB03, db[  10+32]); K20XOR(DB04, db[  11+32]); K05XOR(DB05, db[  12+32]);
					K04XOR(DB10, db[  11+32]); K12XOR(DB11, db[  12+32]); K13XOR(DB12, db[  13+32]); K31XOR(DB13, db[  14+32]); K25XOR(DB14, db[  15+32]); K47XOR(DB15, db[  16+32]);
				} else {
					K27XOR(DB00, db[   7+32]); K55XOR(DB01, db[   8+32]); K18XOR(DB02, db[   9+32]); K19XOR(DB03, db[  10+32]); K06XOR(DB04, db[  11+32]); K46XOR(DB05, db[  12+32]);
					K45XOR(DB10, db[  11+32]); K53XOR(DB11, db[  12+32]); K54XOR(DB12, db[  13+32]); K48XOR(DB13, db[  14+32]); K11XOR(DB14, db[  15+32]); K33XOR(DB15, db[  16+32]);
				}
			} else {
				if (round == 6) {
					K13XOR(DB00, db[   7+32]); K41XOR(DB01, db[   8+32]); K04XOR(DB02, db[   9+32]); K05XOR(DB03, db[  10+32]); K47XOR(DB04, db[  11+32]); K32XOR(DB05, db[  12+32]);
					K31XOR(DB10, db[  11+32]); K39XOR(DB11, db[  12+32]); K40XOR(DB12, db[  13+32]); K34XOR(DB13, db[  14+32]); K52XOR(DB14, db[  15+32]); K19XOR(DB15, db[  16+32]);
				} else {
					K54XOR(DB00, db[   7+32]); K27XOR(DB01, db[   8+32]); K45XOR(DB02, db[   9+32]); K46XOR(DB03, db[  10+32]); K33XOR(DB04, db[  11+32]); K18XOR(DB05, db[  12+32]);
					K48XOR(DB10, db[  11+32]); K25XOR(DB11, db[  12+32]); K26XOR(DB12, db[  13+32]); K20XOR(DB13, db[  14+32]); K38XOR(DB14, db[  15+32]); K05XOR(DB15, db[  16+32]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K47XOR(DB00, db[   7+32]); K20XOR(DB01, db[   8+32]); K38XOR(DB02, db[   9+32]); K39XOR(DB03, db[  10+32]); K26XOR(DB04, db[  11+32]); K11XOR(DB05, db[  12+32]);
					K41XOR(DB10, db[  11+32]); K18XOR(DB11, db[  12+32]); K19XOR(DB12, db[  13+32]); K13XOR(DB13, db[  14+32]); K31XOR(DB14, db[  15+32]); K53XOR(DB15, db[  16+32]);
				} else {
					K33XOR(DB00, db[   7+32]); K06XOR(DB01, db[   8+32]); K55XOR(DB02, db[   9+32]); K25XOR(DB03, db[  10+32]); K12XOR(DB04, db[  11+32]); K52XOR(DB05, db[  12+32]);
					K27XOR(DB10, db[  11+32]); K04XOR(DB11, db[  12+32]); K05XOR(DB12, db[  13+32]); K54XOR(DB13, db[  14+32]); K48XOR(DB14, db[  15+32]); K39XOR(DB15, db[  16+32]);
				}
			} else {
				if (round == 10) {
					K19XOR(DB00, db[   7+32]); K47XOR(DB01, db[   8+32]); K41XOR(DB02, db[   9+32]); K11XOR(DB03, db[  10+32]); K53XOR(DB04, db[  11+32]); K38XOR(DB05, db[  12+32]);
					K13XOR(DB10, db[  11+32]); K45XOR(DB11, db[  12+32]); K46XOR(DB12, db[  13+32]); K40XOR(DB13, db[  14+32]); K34XOR(DB14, db[  15+32]); K25XOR(DB15, db[  16+32]);
				} else {
					K05XOR(DB00, db[   7+32]); K33XOR(DB01, db[   8+32]); K27XOR(DB02, db[   9+32]); K52XOR(DB03, db[  10+32]); K39XOR(DB04, db[  11+32]); K55XOR(DB05, db[  12+32]);
					K54XOR(DB10, db[  11+32]); K31XOR(DB11, db[  12+32]); K32XOR(DB12, db[  13+32]); K26XOR(DB13, db[  14+32]); K20XOR(DB14, db[  15+32]); K11XOR(DB15, db[  16+32]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K46XOR(DB00, db[   7+32]); K19XOR(DB01, db[   8+32]); K13XOR(DB02, db[   9+32]); K38XOR(DB03, db[  10+32]); K25XOR(DB04, db[  11+32]); K41XOR(DB05, db[  12+32]);
					K40XOR(DB10, db[  11+32]); K48XOR(DB11, db[  12+32]); K18XOR(DB12, db[  13+32]); K12XOR(DB13, db[  14+32]); K06XOR(DB14, db[  15+32]); K52XOR(DB15, db[  16+32]);
				} else {
					K32XOR(DB00, db[   7+32]); K05XOR(DB01, db[   8+32]); K54XOR(DB02, db[   9+32]); K55XOR(DB03, db[  10+32]); K11XOR(DB04, db[  11+32]); K27XOR(DB05, db[  12+32]);
					K26XOR(DB10, db[  11+32]); K34XOR(DB11, db[  12+32]); K04XOR(DB12, db[  13+32]); K53XOR(DB13, db[  14+32]); K47XOR(DB14, db[  15+32]); K38XOR(DB15, db[  16+32]);
				}
			} else {
				if (round == 14) {
					K18XOR(DB00, db[   7+32]); K46XOR(DB01, db[   8+32]); K40XOR(DB02, db[   9+32]); K41XOR(DB03, db[  10+32]); K52XOR(DB04, db[  11+32]); K13XOR(DB05, db[  12+32]);
					K12XOR(DB10, db[  11+32]); K20XOR(DB11, db[  12+32]); K45XOR(DB12, db[  13+32]); K39XOR(DB13, db[  14+32]); K33XOR(DB14, db[  15+32]); K55XOR(DB15, db[  16+32]);
				} else {
					K11XOR(DB00, db[   7+32]); K39XOR(DB01, db[   8+32]); K33XOR(DB02, db[   9+32]); K34XOR(DB03, db[  10+32]); K45XOR(DB04, db[  11+32]); K06XOR(DB05, db[  12+32]);
					K05XOR(DB10, db[  11+32]); K13XOR(DB11, db[  12+32]); K38XOR(DB12, db[  13+32]); K32XOR(DB13, db[  14+32]); K26XOR(DB14, db[  15+32]); K48XOR(DB15, db[  16+32]);
				}
			}
		}	
	}
	s3(DB00, DB01, DB02, DB03, DB04, DB05, z(55-32), z(47-32), z(61-32), z(37-32));
	s4(DB10, DB11, DB12, DB13, DB14, DB15, z(57-32), z(51-32), z(41-32), z(32-32));

	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K15XOR(DB00, db[EF24+32]); K24XOR(DB01, db[EF25+32]); K28XOR(DB02, db[EF26+32]); K43XOR(DB03, db[EF27+32]); K30XOR(DB04, db[EF28+32]); K03XOR(DB05, db[EF29+32]);
					K35XOR(DB10, db[EF30+32]); K22XOR(DB11, db[EF31+32]); K02XOR(DB12, db[EF32+32]); K44XOR(DB13, db[EF33+32]); K14XOR(DB14, db[EF34+32]); K23XOR(DB15, db[EF35+32]);
				} else {
					K08XOR(DB00, db[EF24+32]); K17XOR(DB01, db[EF25+32]); K21XOR(DB02, db[EF26+32]); K36XOR(DB03, db[EF27+32]); K23XOR(DB04, db[EF28+32]); K49XOR(DB05, db[EF29+32]);
					K28XOR(DB10, db[EF30+32]); K15XOR(DB11, db[EF31+32]); K24XOR(DB12, db[EF32+32]); K37XOR(DB13, db[EF33+32]); K07XOR(DB14, db[EF34+32]); K16XOR(DB15, db[EF35+32]);
				}
			} else {
				if (round == 2) {
					K51XOR(DB00, db[EF24+32]); K03XOR(DB01, db[EF25+32]); K07XOR(DB02, db[EF26+32]); K22XOR(DB03, db[EF27+32]); K09XOR(DB04, db[EF28+32]); K35XOR(DB05, db[EF29+32]);
					K14XOR(DB10, db[EF30+32]); K01XOR(DB11, db[EF31+32]); K10XOR(DB12, db[EF32+32]); K23XOR(DB13, db[EF33+32]); K50XOR(DB14, db[EF34+32]); K02XOR(DB15, db[EF35+32]);
				} else {
					K37XOR(DB00, db[EF24+32]); K42XOR(DB01, db[EF25+32]); K50XOR(DB02, db[EF26+32]); K08XOR(DB03, db[EF27+32]); K24XOR(DB04, db[EF28+32]); K21XOR(DB05, db[EF29+32]);
					K00XOR(DB10, db[EF30+32]); K44XOR(DB11, db[EF31+32]); K49XOR(DB12, db[EF32+32]); K09XOR(DB13, db[EF33+32]); K36XOR(DB14, db[EF34+32]); K17XOR(DB15, db[EF35+32]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K23XOR(DB00, db[EF24+32]); K28XOR(DB01, db[EF25+32]); K36XOR(DB02, db[EF26+32]); K51XOR(DB03, db[EF27+32]); K10XOR(DB04, db[EF28+32]); K07XOR(DB05, db[EF29+32]);
					K43XOR(DB10, db[EF30+32]); K30XOR(DB11, db[EF31+32]); K35XOR(DB12, db[EF32+32]); K24XOR(DB13, db[EF33+32]); K22XOR(DB14, db[EF34+32]); K03XOR(DB15, db[EF35+32]);
				} else {
					K09XOR(DB00, db[EF24+32]); K14XOR(DB01, db[EF25+32]); K22XOR(DB02, db[EF26+32]); K37XOR(DB03, db[EF27+32]); K49XOR(DB04, db[EF28+32]); K50XOR(DB05, db[EF29+32]);
					K29XOR(DB10, db[EF30+32]); K16XOR(DB11, db[EF31+32]); K21XOR(DB12, db[EF32+32]); K10XOR(DB13, db[EF33+32]); K08XOR(DB14, db[EF34+32]); K42XOR(DB15, db[EF35+32]);
				}
			} else {
				if (round == 6) {
					K24XOR(DB00, db[EF24+32]); K00XOR(DB01, db[EF25+32]); K08XOR(DB02, db[EF26+32]); K23XOR(DB03, db[EF27+32]); K35XOR(DB04, db[EF28+32]); K36XOR(DB05, db[EF29+32]);
					K15XOR(DB10, db[EF30+32]); K02XOR(DB11, db[EF31+32]); K07XOR(DB12, db[EF32+32]); K49XOR(DB13, db[EF33+32]); K51XOR(DB14, db[EF34+32]); K28XOR(DB15, db[EF35+32]);
				} else {
					K10XOR(DB00, db[EF24+32]); K43XOR(DB01, db[EF25+32]); K51XOR(DB02, db[EF26+32]); K09XOR(DB03, db[EF27+32]); K21XOR(DB04, db[EF28+32]); K22XOR(DB05, db[EF29+32]);
					K01XOR(DB10, db[EF30+32]); K17XOR(DB11, db[EF31+32]); K50XOR(DB12, db[EF32+32]); K35XOR(DB13, db[EF33+32]); K37XOR(DB14, db[EF34+32]); K14XOR(DB15, db[EF35+32]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K03XOR(DB00, db[EF24+32]); K36XOR(DB01, db[EF25+32]); K44XOR(DB02, db[EF26+32]); K02XOR(DB03, db[EF27+32]); K14XOR(DB04, db[EF28+32]); K15XOR(DB05, db[EF29+32]);
					K51XOR(DB10, db[EF30+32]); K10XOR(DB11, db[EF31+32]); K43XOR(DB12, db[EF32+32]); K28XOR(DB13, db[EF33+32]); K30XOR(DB14, db[EF34+32]); K07XOR(DB15, db[EF35+32]);
				} else {
					K42XOR(DB00, db[EF24+32]); K22XOR(DB01, db[EF25+32]); K30XOR(DB02, db[EF26+32]); K17XOR(DB03, db[EF27+32]); K00XOR(DB04, db[EF28+32]); K01XOR(DB05, db[EF29+32]);
					K37XOR(DB10, db[EF30+32]); K49XOR(DB11, db[EF31+32]); K29XOR(DB12, db[EF32+32]); K14XOR(DB13, db[EF33+32]); K16XOR(DB14, db[EF34+32]); K50XOR(DB15, db[EF35+32]);
				}
			} else {
				if (round == 10) {
					K28XOR(DB00, db[EF24+32]); K08XOR(DB01, db[EF25+32]); K16XOR(DB02, db[EF26+32]); K03XOR(DB03, db[EF27+32]); K43XOR(DB04, db[EF28+32]); K44XOR(DB05, db[EF29+32]);
					K23XOR(DB10, db[EF30+32]); K35XOR(DB11, db[EF31+32]); K15XOR(DB12, db[EF32+32]); K00XOR(DB13, db[EF33+32]); K02XOR(DB14, db[EF34+32]); K36XOR(DB15, db[EF35+32]);
				} else {
					K14XOR(DB00, db[EF24+32]); K51XOR(DB01, db[EF25+32]); K02XOR(DB02, db[EF26+32]); K42XOR(DB03, db[EF27+32]); K29XOR(DB04, db[EF28+32]); K30XOR(DB05, db[EF29+32]);
					K09XOR(DB10, db[EF30+32]); K21XOR(DB11, db[EF31+32]); K01XOR(DB12, db[EF32+32]); K43XOR(DB13, db[EF33+32]); K17XOR(DB14, db[EF34+32]); K22XOR(DB15, db[EF35+32]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K00XOR(DB00, db[EF24+32]); K37XOR(DB01, db[EF25+32]); K17XOR(DB02, db[EF26+32]); K28XOR(DB03, db[EF27+32]); K15XOR(DB04, db[EF28+32]); K16XOR(DB05, db[EF29+32]);
					K24XOR(DB10, db[EF30+32]); K07XOR(DB11, db[EF31+32]); K44XOR(DB12, db[EF32+32]); K29XOR(DB13, db[EF33+32]); K03XOR(DB14, db[EF34+32]); K08XOR(DB15, db[EF35+32]);
				} else {
					K43XOR(DB00, db[EF24+32]); K23XOR(DB01, db[EF25+32]); K03XOR(DB02, db[EF26+32]); K14XOR(DB03, db[EF27+32]); K01XOR(DB04, db[EF28+32]); K02XOR(DB05, db[EF29+32]);
					K10XOR(DB10, db[EF30+32]); K50XOR(DB11, db[EF31+32]); K30XOR(DB12, db[EF32+32]); K15XOR(DB13, db[EF33+32]); K42XOR(DB14, db[EF34+32]); K51XOR(DB15, db[EF35+32]);
				}
			} else {
				if (round == 14) {
					K29XOR(DB00, db[EF24+32]); K09XOR(DB01, db[EF25+32]); K42XOR(DB02, db[EF26+32]); K00XOR(DB03, db[EF27+32]); K44XOR(DB04, db[EF28+32]); K17XOR(DB05, db[EF29+32]);
					K49XOR(DB10, db[EF30+32]); K36XOR(DB11, db[EF31+32]); K16XOR(DB12, db[EF32+32]); K01XOR(DB13, db[EF33+32]); K28XOR(DB14, db[EF34+32]); K37XOR(DB15, db[EF35+32]);
				} else {
					K22XOR(DB00, db[EF24+32]); K02XOR(DB01, db[EF25+32]); K35XOR(DB02, db[EF26+32]); K50XOR(DB03, db[EF27+32]); K37XOR(DB04, db[EF28+32]); K10XOR(DB05, db[EF29+32]);
					K42XOR(DB10, db[EF30+32]); K29XOR(DB11, db[EF31+32]); K09XOR(DB12, db[EF32+32]); K51XOR(DB13, db[EF33+32]); K21XOR(DB14, db[EF34+32]); K30XOR(DB15, db[EF35+32]);
				}
			}
		}	
	}
	s5(DB00, DB01, DB02, DB03, DB04, DB05, z(39-32), z(45-32), z(56-32), z(34-32));
	s6(DB10, DB11, DB12, DB13, DB14, DB15, z(35-32), z(60-32), z(42-32), z(50-32));


	if (round < 8) {
		if (round < 4) {
			if (round < 2) {
				if (round == 0) {
					K51XOR(DB00, db[  23+32]); K16XOR(DB01, db[  24+32]); K29XOR(DB02, db[  25+32]); K49XOR(DB03, db[  26+32]); K07XOR(DB04, db[  27+32]); K17XOR(DB05, db[  28+32]);
					K37XOR(DB10, db[  27+32]); K08XOR(DB11, db[  28+32]); K09XOR(DB12, db[  29+32]); K50XOR(DB13, db[  30+32]); K42XOR(DB14, db[  31+32]); K21XOR(DB15, db[   0+32]);
				} else {
					K44XOR(DB00, db[  23+32]); K09XOR(DB01, db[  24+32]); K22XOR(DB02, db[  25+32]); K42XOR(DB03, db[  26+32]); K00XOR(DB04, db[  27+32]); K10XOR(DB05, db[  28+32]);
					K30XOR(DB10, db[  27+32]); K01XOR(DB11, db[  28+32]); K02XOR(DB12, db[  29+32]); K43XOR(DB13, db[  30+32]); K35XOR(DB14, db[  31+32]); K14XOR(DB15, db[   0+32]);
				}
			} else {
				if (round == 2) {
					K30XOR(DB00, db[  23+32]); K24XOR(DB01, db[  24+32]); K08XOR(DB02, db[  25+32]); K28XOR(DB03, db[  26+32]); K43XOR(DB04, db[  27+32]); K49XOR(DB05, db[  28+32]);
					K16XOR(DB10, db[  27+32]); K44XOR(DB11, db[  28+32]); K17XOR(DB12, db[  29+32]); K29XOR(DB13, db[  30+32]); K21XOR(DB14, db[  31+32]); K00XOR(DB15, db[   0+32]);
				} else {
					K16XOR(DB00, db[  23+32]); K10XOR(DB01, db[  24+32]); K51XOR(DB02, db[  25+32]); K14XOR(DB03, db[  26+32]); K29XOR(DB04, db[  27+32]); K35XOR(DB05, db[  28+32]);
					K02XOR(DB10, db[  27+32]); K30XOR(DB11, db[  28+32]); K03XOR(DB12, db[  29+32]); K15XOR(DB13, db[  30+32]); K07XOR(DB14, db[  31+32]); K43XOR(DB15, db[   0+32]);
				}
			}
		} else {
			if (round < 6) {
				if (round == 4) {
					K02XOR(DB00, db[  23+32]); K49XOR(DB01, db[  24+32]); K37XOR(DB02, db[  25+32]); K00XOR(DB03, db[  26+32]); K15XOR(DB04, db[  27+32]); K21XOR(DB05, db[  28+32]);
					K17XOR(DB10, db[  27+32]); K16XOR(DB11, db[  28+32]); K42XOR(DB12, db[  29+32]); K01XOR(DB13, db[  30+32]); K50XOR(DB14, db[  31+32]); K29XOR(DB15, db[   0+32]);
				} else {
					K17XOR(DB00, db[  23+32]); K35XOR(DB01, db[  24+32]); K23XOR(DB02, db[  25+32]); K43XOR(DB03, db[  26+32]); K01XOR(DB04, db[  27+32]); K07XOR(DB05, db[  28+32]);
					K03XOR(DB10, db[  27+32]); K02XOR(DB11, db[  28+32]); K28XOR(DB12, db[  29+32]); K44XOR(DB13, db[  30+32]); K36XOR(DB14, db[  31+32]); K15XOR(DB15, db[   0+32]);
				}
			} else {
				if (round == 6) {
					K03XOR(DB00, db[  23+32]); K21XOR(DB01, db[  24+32]); K09XOR(DB02, db[  25+32]); K29XOR(DB03, db[  26+32]); K44XOR(DB04, db[  27+32]); K50XOR(DB05, db[  28+32]);
					K42XOR(DB10, db[  27+32]); K17XOR(DB11, db[  28+32]); K14XOR(DB12, db[  29+32]); K30XOR(DB13, db[  30+32]); K22XOR(DB14, db[  31+32]); K01XOR(DB15, db[   0+32]);
				} else {
					K42XOR(DB00, db[  23+32]); K07XOR(DB01, db[  24+32]); K24XOR(DB02, db[  25+32]); K15XOR(DB03, db[  26+32]); K30XOR(DB04, db[  27+32]); K36XOR(DB05, db[  28+32]);
					K28XOR(DB10, db[  27+32]); K03XOR(DB11, db[  28+32]); K00XOR(DB12, db[  29+32]); K16XOR(DB13, db[  30+32]); K08XOR(DB14, db[  31+32]); K44XOR(DB15, db[   0+32]);
				}
			}
		}
	} else {
		if (round < 12) {
			if (round < 10) {
				if (round == 8) {
					K35XOR(DB00, db[  23+32]); K00XOR(DB01, db[  24+32]); K17XOR(DB02, db[  25+32]); K08XOR(DB03, db[  26+32]); K23XOR(DB04, db[  27+32]); K29XOR(DB05, db[  28+32]);
					K21XOR(DB10, db[  27+32]); K49XOR(DB11, db[  28+32]); K50XOR(DB12, db[  29+32]); K09XOR(DB13, db[  30+32]); K01XOR(DB14, db[  31+32]); K37XOR(DB15, db[   0+32]);
				} else {
					K21XOR(DB00, db[  23+32]); K43XOR(DB01, db[  24+32]); K03XOR(DB02, db[  25+32]); K51XOR(DB03, db[  26+32]); K09XOR(DB04, db[  27+32]); K15XOR(DB05, db[  28+32]);
					K07XOR(DB10, db[  27+32]); K35XOR(DB11, db[  28+32]); K36XOR(DB12, db[  29+32]); K24XOR(DB13, db[  30+32]); K44XOR(DB14, db[  31+32]); K23XOR(DB15, db[   0+32]);
				}
			} else {
				if (round == 10) {
					K07XOR(DB00, db[  23+32]); K29XOR(DB01, db[  24+32]); K42XOR(DB02, db[  25+32]); K37XOR(DB03, db[  26+32]); K24XOR(DB04, db[  27+32]); K01XOR(DB05, db[  28+32]);
					K50XOR(DB10, db[  27+32]); K21XOR(DB11, db[  28+32]); K22XOR(DB12, db[  29+32]); K10XOR(DB13, db[  30+32]); K30XOR(DB14, db[  31+32]); K09XOR(DB15, db[   0+32]);
				} else {
					K50XOR(DB00, db[  23+32]); K15XOR(DB01, db[  24+32]); K28XOR(DB02, db[  25+32]); K23XOR(DB03, db[  26+32]); K10XOR(DB04, db[  27+32]); K44XOR(DB05, db[  28+32]);
					K36XOR(DB10, db[  27+32]); K07XOR(DB11, db[  28+32]); K08XOR(DB12, db[  29+32]); K49XOR(DB13, db[  30+32]); K16XOR(DB14, db[  31+32]); K24XOR(DB15, db[   0+32]);
				}
			}
		} else {
			if (round < 14) {
				if (round == 12) {
					K36XOR(DB00, db[  23+32]); K01XOR(DB01, db[  24+32]); K14XOR(DB02, db[  25+32]); K09XOR(DB03, db[  26+32]); K49XOR(DB04, db[  27+32]); K30XOR(DB05, db[  28+32]);
					K22XOR(DB10, db[  27+32]); K50XOR(DB11, db[  28+32]); K51XOR(DB12, db[  29+32]); K35XOR(DB13, db[  30+32]); K02XOR(DB14, db[  31+32]); K10XOR(DB15, db[   0+32]);
				} else {
					K22XOR(DB00, db[  23+32]); K44XOR(DB01, db[  24+32]); K00XOR(DB02, db[  25+32]); K24XOR(DB03, db[  26+32]); K35XOR(DB04, db[  27+32]); K16XOR(DB05, db[  28+32]);
					K08XOR(DB10, db[  27+32]); K36XOR(DB11, db[  28+32]); K37XOR(DB12, db[  29+32]); K21XOR(DB13, db[  30+32]); K17XOR(DB14, db[  31+32]); K49XOR(DB15, db[   0+32]);
				}
			} else {
				if (round == 14) {
					K08XOR(DB00, db[  23+32]); K30XOR(DB01, db[  24+32]); K43XOR(DB02, db[  25+32]); K10XOR(DB03, db[  26+32]); K21XOR(DB04, db[  27+32]); K02XOR(DB05, db[  28+32]);
					K51XOR(DB10, db[  27+32]); K22XOR(DB11, db[  28+32]); K23XOR(DB12, db[  29+32]); K07XOR(DB13, db[  30+32]); K03XOR(DB14, db[  31+32]); K35XOR(DB15, db[   0+32]);
				} else {
					K01XOR(DB00, db[  23+32]); K23XOR(DB01, db[  24+32]); K36XOR(DB02, db[  25+32]); K03XOR(DB03, db[  26+32]); K14XOR(DB04, db[  27+32]); K24XOR(DB05, db[  28+32]);
					K44XOR(DB10, db[  27+32]); K15XOR(DB11, db[  28+32]); K16XOR(DB12, db[  29+32]); K00XOR(DB13, db[  30+32]); K49XOR(DB14, db[  31+32]); K28XOR(DB15, db[   0+32]);
				}
			}
		}	
	}
	s7(DB00, DB01, DB02, DB03, DB04, DB05, z(63-32), z(43-32), z(53-32), z(38-32));
	s8(DB10, DB11, DB12, DB13, DB14, DB15, z(36-32), z(58-32), z(46-32), z(52-32));

	++round;

	if (--roundsAndSwapped)
		goto start;
	round -= 17;
	roundsAndSwapped = 0x108;
	if (--iterations)
		goto swap;
	return;

next:
	round -= 15;
	roundsAndSwapped = 8;
	iterations--;
	goto start;
}

#define OPENCL_DES_DEFINE_SEARCH_FUNCTION                                                                  \
	__kernel void OpenCL_DES_PerformSearching(                                                             \
		__global   GPUOutput                * const outputArray,                                           \
		__constant KeyInfo                  *       keyInfo,                                               \
		__global   const unsigned int       * const tripcodeChunkArray,                                    \
				   const unsigned int               numTripcodeChunk,                                      \
 		__constant const unsigned char      * const smallKeyBitmap,                                        \
  		__constant const unsigned int       * const compactMediumKeyBitmap,                                \
		__global   const unsigned char      * const keyBitmap,                                             \
		__global   const PartialKeyFrom3To6 * const partialKeyFrom3To6Array,                               \
                   const unsigned int               keyFrom00To27                                          \
	) {                                                                                                    \
		__global              GPUOutput     *output = &outputArray[get_global_id(0)];                      \
							  int  tripcodeIndex;                                                          \
		DES_DATA_BLOCKS_SPACE vtype          DES_dataBlocks[64];                                           \
		__global unsigned char *partialKeyFrom3To6 = partialKeyFrom3To6Array[get_global_id(0)].partialKeyFrom3To6; \
		output->numMatchingTripcodes = 0;                                                                  \
		unsigned int keyFrom28To48 = ((partialKeyFrom3To6[3] & 0x7f) << 14) | ((partialKeyFrom3To6[2] & 0x7f) << 7) | (partialKeyFrom3To6[1] & 0x7f); \
		                                                                                                   \
		DES_Crypt(DES_dataBlocks, keyFrom00To27, keyFrom28To48);                                           \
		                                                                                                   \
		BOOL found = FALSE;                                                                                \

#define OPENCL_DES_END_OF_SEAERCH_FUNCTION                                                                 \
	quit_loops:                                                                                            \
		if (found == TRUE) {                                                                               \
			output->numMatchingTripcodes = 1;                                                              \
			output->pair.key.c[7] = key7Array[tripcodeIndex];                                              \
		}                                                                                                  \
		output->numGeneratedTripcodes = OPENCL_DES_BS_DEPTH;                                               \
	}                                                                                                      \

#define OPENCL_DES_USE_SMALL_KEY_BITMAP                                           \
	if (smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) \
		continue;                                                                 \

#define OPENCL_DES_USE_MEDIUM_KEY_BITMAP                                          \
	if (compactMediumKeyBitmap[tripcodeChunk >> ((5 - MEDIUM_KEY_BITMAP_LEN_STRING) * 6 + 5)] & (0x1 << (tripcodeChunk >> ((5 - MEDIUM_KEY_BITMAP_LEN_STRING) * 6) & 0x1f))) \
		continue;                                                                 \

#define OPENCL_DES_USE_KEY_BITMAP                                                 \
	if (keyBitmap[tripcodeChunk >> ((5 - KEY_BITMAP_LEN_STRING) * 6)])            \
		continue;                                                                 \

#define OPENCL_DES_PERFORM_LINEAR_SEARCH                                          \
	for (int j = 0; j < numTripcodeChunk; ++j) {                                  \
		if (tripcodeChunkArray[j] == tripcodeChunk) {                             \
			found = TRUE;                                                         \
			goto quit_loops;                                                      \
		}                                                                         \
	}                                                                             \

#define OPENCL_DES_PERFORM_BINARY_SEARCH                                    \
	int lower = 0, upper = numTripcodeChunk - 1, middle = lower;            \
	while (tripcodeChunk != tripcodeChunkArray[middle] && lower <= upper) { \
		middle = (lower + upper) >> 1;                                      \
		if (tripcodeChunk > tripcodeChunkArray[middle]) {                   \
			lower = middle + 1;                                             \
		} else {                                                            \
			upper = middle - 1;                                             \
		}                                                                   \
	}                                                                       \
	if (tripcodeChunk == tripcodeChunkArray[middle]) {                      \
		found = TRUE;                                                       \
		goto quit_loops;                                                    \
	}                                                                       \

#define GET_TRIPCODE_CHAR_INDEX(r, t, i0, i1, i2, i3, i4, i5, pos)         \
	(  ((((r)[i0] & (0x01U << (t))) ? (0x1) : (0x0)) << (5 + ((pos) * 6)))  \
	 | ((((r)[i1] & (0x01U << (t))) ? (0x1) : (0x0)) << (4 + ((pos) * 6)))  \
	 | ((((r)[i2] & (0x01U << (t))) ? (0x1) : (0x0)) << (3 + ((pos) * 6)))  \
	 | ((((r)[i3] & (0x01U << (t))) ? (0x1) : (0x0)) << (2 + ((pos) * 6)))  \
	 | ((((r)[i4] & (0x01U << (t))) ? (0x1) : (0x0)) << (1 + ((pos) * 6)))  \
	 | ((((r)[i5] & (0x01U << (t))) ? (0x1) : (0x0)) << (0 + ((pos) * 6)))) \

#define GET_TRIPCODE_CHAR_INDEX_LAST(r, t, i0, i1, i2, i3) \
	(  ((((r)[i0] & (0x01U << (t))) ? (0x1) : (0x0)) << 5)  \
	 | ((((r)[i1] & (0x01U << (t))) ? (0x1) : (0x0)) << 4)  \
	 | ((((r)[i2] & (0x01U << (t))) ? (0x1) : (0x0)) << 3)  \
	 | ((((r)[i3] & (0x01U << (t))) ? (0x1) : (0x0)) << 2)) \

#if defined(FORWARD_MATCHING_1CHUNK)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		if (GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 0) != ((tripcodeChunkArray[0] >> (6 * 4)) & 0x3f)) continue;
		if (GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 0) != ((tripcodeChunkArray[0] >> (6 * 3)) & 0x3f)) continue;
		if (GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 0) != ((tripcodeChunkArray[0] >> (6 * 2)) & 0x3f)) continue;
		if (GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 0) != ((tripcodeChunkArray[0] >> (6 * 1)) & 0x3f)) continue;
		if (GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0) != ((tripcodeChunkArray[0] >> (6 * 0)) & 0x3f)) continue;
		found = TRUE;
		goto quit_loops;
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FORWARD_MATCHING_SIMPLE)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_PERFORM_LINEAR_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FORWARD_MATCHING)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		// all:                                  2181M (10m)
		// w/o OPENCL_DES_USE_SMALL_KEY_BITMAP:  2160M (10m)
		// w/o OPENCL_DES_USE_MEDIUM_KEY_BITMAP: 2142M (10m)
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_USE_MEDIUM_KEY_BITMAP
		OPENCL_DES_USE_KEY_BITMAP
		OPENCL_DES_PERFORM_BINARY_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(BACKWARD_MATCHING_SIMPLE)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
		                             | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_PERFORM_LINEAR_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(BACKWARD_MATCHING)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
		                             | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_USE_KEY_BITMAP
		OPENCL_DES_PERFORM_BINARY_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FORWARD_AND_BACKWARD_MATCHING_SIMPLE)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_PERFORM_LINEAR_SEARCH
	}
	
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
		                             | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_PERFORM_LINEAR_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FORWARD_AND_BACKWARD_MATCHING)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_USE_KEY_BITMAP
		OPENCL_DES_PERFORM_BINARY_SEARCH
	}
	
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 4)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 3)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 2)
		                             | GET_TRIPCODE_CHAR_INDEX     (DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 1)
		                             | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		OPENCL_DES_USE_SMALL_KEY_BITMAP
		OPENCL_DES_USE_KEY_BITMAP
		OPENCL_DES_PERFORM_BINARY_SEARCH
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FLEXIBLE_SIMPLE)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 0);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 0);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 0);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 0);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		if (!smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]) { OPENCL_DES_PERFORM_LINEAR_SEARCH }
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#elif defined(FLEXIBLE)

OPENCL_DES_DEFINE_SEARCH_FUNCTION
	for (tripcodeIndex = 0; tripcodeIndex < OPENCL_DES_BS_DEPTH; ++tripcodeIndex) {
		unsigned int tripcodeChunk =   GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 63, 31, 38,  6, 46, 14, 4)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 54, 22, 62, 30, 37,  5, 3)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 45, 13, 53, 21, 61, 29, 2)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 36,  4, 44, 12, 52, 20, 1)
						             | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 60, 28, 35,  3, 43, 11, 0);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 51, 19, 59, 27, 34,  2, 0);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 42, 10, 50, 18, 58, 26, 0);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 33,  1, 41,  9, 49, 17, 0);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX(DES_dataBlocks, tripcodeIndex, 57, 25, 32,  0, 40,  8, 0);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}

		tripcodeChunk = ((tripcodeChunk << 6) & 0x3fffffff) | GET_TRIPCODE_CHAR_INDEX_LAST(DES_dataBlocks, tripcodeIndex, 48, 16, 56, 24);
		if (   !smallKeyBitmap[tripcodeChunk >> ((5 - SMALL_KEY_BITMAP_LEN_STRING) * 6)]
		    && !     keyBitmap[tripcodeChunk >> ((5 -       KEY_BITMAP_LEN_STRING) * 6)]) {
			OPENCL_DES_PERFORM_BINARY_SEARCH
		}
	}
OPENCL_DES_END_OF_SEAERCH_FUNCTION

#endif