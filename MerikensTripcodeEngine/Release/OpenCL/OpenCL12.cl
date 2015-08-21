// Meriken's Tripcode Engine 2.0.1
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

typedef int BOOL;
#define TRUE  (1)
#define FALSE (0)

#define MAX_LEN_TRIPCODE            12
#define MAX_LEN_TRIPCODE_KEY        12
#define MAX_LEN_EXPANDED_PATTERN    MAX_LEN_TRIPCODE
#define SMALL_CHUNK_BITMAP_LEN_STRING 2
#define SMALL_CHUNK_BITMAP_SIZE       (64 * 64)
#define CHUNK_BITMAP_LEN_STRING       4
#define OPENCL_SHA1_MAX_PASS_COUNT  1024

#define IS_FIRST_BYTE_SJIS_FULL(c)    \
	(   (0x81 <= (c) && (c) <= 0x84)  \
	 || (0x88 <= (c) && (c) <= 0x9f)  \
	 || (0xe0 <= (c) && (c) <= 0xea)) \

#define IS_FIRST_BYTE_SJIS_CONSERVATIVE(c) \
	(   (0x89 <= (c) && (c) <= 0x97)       \
	 || (0x99 <= (c) && (c) <= 0x9f)       \
	 || (0xe0 <= (c) && (c) <= 0xe9))      \

#ifdef MAXIMIZE_KEY_SPACE
#define IS_FIRST_BYTE_SJIS(c) IS_FIRST_BYTE_SJIS_FULL(c)
#else
#define IS_FIRST_BYTE_SJIS(c) IS_FIRST_BYTE_SJIS_CONSERVATIVE(c)
#endif

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



///////////////////////////////////////////////////////////////////////////////
// SHA-1                                                                     //
///////////////////////////////////////////////////////////////////////////////

// Circular left rotation of 32-bit value 'val' left by 'bits' bits
// (assumes that 'bits' is always within range from 0 to 32)
#if TRUE

#define ROTL( bits, val ) rotate((val), (unsigned int)(bits))

#else

#define ROTL( bits, val ) \
        ( ( ( val ) << ( bits ) ) | ( ( val ) >> ( 32 - ( bits ) ) ) )

#endif

// Central routine for calculating the hash value. See the FIPS
// 180-3 standard p. 17f for a detailed explanation.
#if TRUE

#define f1 	bitselect(D, C, B)
#define f2  ( B ^ C ^ D )
#define f3  (bitselect(B, C, D) ^ bitselect(B, 0U, C))
#define f4  f2

#else

#define f1 	( ( B & C ) ^ ( ( ~ B ) & D ) )
#define f2  ( B ^ C ^ D )
#define f3  ( ( B & C ) ^ ( B & D ) ^ ( C & D ) )
#define f4  f2

#endif

// Initial hash values (see p. 14 of FIPS 180-3)
#define H0 0x67452301
#define H1 0xefcdab89
#define H2 0x98badcfe
#define H3 0x10325476
#define H4 0xc3d2e1f0

// Constants required for hash calculation (see p. 11 of FIPS 180-3)
#define K0 0x5a827999
#define K1 0x6ed9eba1
#define K2 0x8f1bbcdc
#define K3 0xca62c1d6

#define SET_KEY_CHAR(var, flag, table, value)             \
	if (!(flag)) {                                        \
		var = (table)[(value)];                           \
		isSecondByte = IS_FIRST_BYTE_SJIS_FULL(var);      \
	} else {                                              \
		var = keyCharTable_SecondByte[(value)];           \
		isSecondByte = FALSE;                             \
	}                                                     \

#define ROUND_00_TO_19(t, w)                              \
		{                                                 \
			tmp = (ROTL(5, A) + f1 + E + (w) + K0);       \
			E = D;                                        \
			D = C;                                        \
			C = ROTL( 30, B );                            \
			B = A;                                        \
			A = tmp;                                      \
		}                                                 \

#define ROUND_20_TO_39(t, w)                              \
		{                                                 \
			tmp = (ROTL(5, A) + f2 + E + (w) + K1);       \
			E = D;                                        \
			D = C;                                        \
			C = ROTL( 30, B );                            \
			B = A;                                        \
			A = tmp;                                      \
		}                                                 \

#define ROUND_40_TO_59(t, w)                              \
		{                                                 \
			tmp = (ROTL(5, A) + f3 + E + (w) + K2);       \
			E = D;                                        \
			D = C;                                        \
			C = ROTL( 30, B );                            \
			B = A;                                        \
			A = tmp;                                      \
		}                                                 \

#define	ROUND_60_TO_79(t, w)                              \
		{                                                 \
			tmp = (ROTL(5, A) + f4 + E + (w) + K3 );      \
			E = D;                                        \
			D = C;                                        \
			C = ROTL( 30, B );                            \
			B = A;                                        \
			A = tmp;                                      \
		}                                                 \

__constant char base64CharTable[64] = {
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P',
	'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f',
	'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v',
	'w', 'x', 'y', 'z', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '.', '/',
};

#define OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(functionName)         \
__kernel void (functionName)(                                    \
	__global   GPUOutput           * const outputArray,          \
	__constant const unsigned char * const key,                  \
	__global   const unsigned int  * const tripcodeChunkArray,   \
	           const unsigned int          numTripcodeChunk,     \
	__constant const unsigned char * const keyCharTable_OneByte, \
	__constant const unsigned char * const keyCharTable_FirstByte,   \
	__constant const unsigned char * const keyCharTable_SecondByte,  \
	__constant const unsigned char * const keyCharTable_SecondByteAndOneByte,  \
 	__constant const unsigned char * const smallChunkBitmap_constant, \
 	__global   const unsigned char * const chunkBitmap             \
) {                                                              \

#define OPENCL_SHA1_BEFORE_SEARCHING \
	unsigned int        A, B, C, D, E, tmp;                                                                \
	unsigned char       key0, key1, key2, key3, key11;                                                     \
	unsigned char       found = 0;                                                                         \
	BOOL                isSecondByte = FALSE;                                                              \
	__global GPUOutput *output = &outputArray[(int)get_global_id(0)];                                      \
    int                 passCount;                                                                         \
	unsigned char       randomByte2 = key[2];                                                              \
	unsigned char       randomByte3 = key[3];                                                              \
	                                                                                                       \
	output->numMatchingTripcodes = 0;                                                                      \
	key0  = keyCharTable_FirstByte           [key[0 ] + ((int)get_group_id(0) & 0x3f)];                    \
	key1  = keyCharTable_SecondByteAndOneByte[key[1 ] + ((int)get_local_id(0) & 0x3f)];                    \
	key11 = keyCharTable_SecondByteAndOneByte[key[11] + ((int)get_group_id(0) >> 6  )];                    \
	                                                                                                       \
	__local unsigned int  PW[80];                                                                          \
	__local unsigned char smallChunkBitmap[SMALL_CHUNK_BITMAP_SIZE];                                           \
	if (get_local_id(0) == 0) {                                                                            \
		PW[0]  = 0;                                                                                        \
		PW[1]  = (key[4] << 24) | (key[5] << 16) | (key[ 6] << 8) | key[ 7];                               \
		PW[2]  = (key[8] << 24) | (key[9] << 16) | (key[10] << 8) | key11;                                 \
		PW[3]  = 0x80000000;                                                                               \
		PW[4]  = 0;                                                                                        \
		PW[5]  = 0;                                                                                        \
		PW[6]  = 0;                                                                                        \
		PW[7]  = 0;                                                                                        \
		PW[8]  = 0;                                                                                        \
		PW[9]  = 0;                                                                                        \
		PW[10] = 0;                                                                                        \
		PW[11] = 0;                                                                                        \
		PW[12] = 0;                                                                                        \
		PW[13] = 0;                                                                                        \
		PW[14] = 0;                                                                                        \
		PW[15] = 12 * 8;                                                                                   \
		PW[16] = ROTL(1, PW[16 - 3] ^ PW[16 - 8] ^ PW[16 - 14]);                                           \
		for (int t = 17; t < 80; ++t)                                                                      \
			PW[t] = ROTL(1, PW[(t) - 3] ^ PW[(t) - 8] ^ PW[(t) - 14] ^ PW[(t) - 16]);                      \
			                                                                                               \
		for (int i = 0; i < SMALL_CHUNK_BITMAP_SIZE; ++i)                                                    \
			smallChunkBitmap[i] = smallChunkBitmap_constant[i];                                                \
	}                                                                                                      \
	barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);                                                   \
	                                                                                                       \
	randomByte2 += ((get_local_id(0) & 0xc0) >> 2);                                                        \
	for (passCount = 0; passCount < OPENCL_SHA1_MAX_PASS_COUNT; passCount++){                              \
		barrier(CLK_GLOBAL_MEM_FENCE | CLK_LOCAL_MEM_FENCE);                                               \
		                                                                                                   \
		key2 = keyCharTable_FirstByte           [randomByte2 + (passCount >> 6)];                          \
		key3 = keyCharTable_SecondByteAndOneByte[randomByte3 + (passCount & 63)];                          \
		                                                                                                   \
		A = H0;                                                                                            \
		B = H1;                                                                                            \
		C = H2;                                                                                            \
		D = H3;                                                                                            \
		E = H4;                                                                                            \
		                                                                                                   \
		unsigned int W0   = (key0 << 24) | (key1 << 16) | (key2 << 8) | key3;                              \
		unsigned int W0_1 = ROTL(1,  W0);                                                                  \
		unsigned int W0_2 = ROTL(2,  W0);                                                                  \
		unsigned int W0_3 = ROTL(3,  W0);                                                                  \
		unsigned int W0_4 = ROTL(4,  W0);                                                                  \
		unsigned int W0_5 = ROTL(5,  W0);                                                                  \
		unsigned int W0_6 = ROTL(6,  W0);                                                                  \
		unsigned int W0_7 = ROTL(7,  W0);                                                                  \
		unsigned int W0_8 = ROTL(8,  W0);                                                                  \
		unsigned int W0_9 = ROTL(9,  W0);                                                                  \
		unsigned int W010 = ROTL(10, W0);                                                                  \
		unsigned int W011 = ROTL(11, W0);                                                                  \
		unsigned int W012 = ROTL(12, W0);                                                                  \
		unsigned int W013 = ROTL(13, W0);                                                                  \
		unsigned int W014 = ROTL(14, W0);                                                                  \
		unsigned int W015 = ROTL(15, W0);                                                                  \
		unsigned int W016 = ROTL(16, W0);                                                                  \
		unsigned int W017 = ROTL(17, W0);                                                                  \
		unsigned int W018 = ROTL(18, W0);                                                                  \
		unsigned int W019 = ROTL(19, W0);                                                                  \
		unsigned int W020 = ROTL(20, W0);                                                                  \
		unsigned int W021 = ROTL(21, W0);                                                                  \
		unsigned int W022 = ROTL(22, W0);                                                                  \
		unsigned int W0_6___W0_4        = W0_6        ^ W0_4;                                              \
		unsigned int W0_6___W0_4___W0_7 = W0_6___W0_4 ^ W0_7;                                              \
		unsigned int W0_8___W0_4        = W0_8        ^ W0_4;                                              \
		unsigned int W0_8___W012        = W0_8        ^ W012;                                              \
		                                                                                                   \
		ROUND_00_TO_19(0,  W0);                                                                            \
		ROUND_00_TO_19(1,  PW[1]);                                                                         \
		ROUND_00_TO_19(2,  PW[2]);                                                                         \
		ROUND_00_TO_19(3,  PW[3]);                                                                         \
		ROUND_00_TO_19(4,  PW[4]);                                                                         \
		ROUND_00_TO_19(5,  PW[5]);                                                                         \
		ROUND_00_TO_19(6,  PW[6]);                                                                         \
		ROUND_00_TO_19(7,  PW[7]);                                                                         \
		ROUND_00_TO_19(8,  PW[8]);                                                                         \
		ROUND_00_TO_19(9,  PW[9]);                                                                         \
		ROUND_00_TO_19(10, PW[10]);                                                                        \
		ROUND_00_TO_19(11, PW[11]);                                                                        \
		ROUND_00_TO_19(12, PW[12]);                                                                        \
		ROUND_00_TO_19(13, PW[13]);                                                                        \
		ROUND_00_TO_19(14, PW[14]);                                                                        \
		ROUND_00_TO_19(15, PW[15]);                                                                        \
		                                                                                                   \
		ROUND_00_TO_19(16, PW[16] ^ W0_1                                   );                              \
		ROUND_00_TO_19(17, PW[17]                                          );                              \
		ROUND_00_TO_19(18, PW[18]                                          );                              \
		ROUND_00_TO_19(19, PW[19] ^ W0_2                                   );                              \
		                                                                                                   \
		ROUND_20_TO_39(20, PW[20]                                          );                              \
		ROUND_20_TO_39(21, PW[21]                                          );                              \
		ROUND_20_TO_39(22, PW[22] ^ W0_3                                   );                              \
		ROUND_20_TO_39(23, PW[23]                                          );                              \
		ROUND_20_TO_39(24, PW[24] ^ W0_2                                   );                              \
		ROUND_20_TO_39(25, PW[25] ^ W0_4                                   );                              \
		ROUND_20_TO_39(26, PW[26]                                          );                              \
		ROUND_20_TO_39(27, PW[27]                                          );                              \
		ROUND_20_TO_39(28, PW[28] ^ W0_5                                   );                              \
		ROUND_20_TO_39(29, PW[29]                                          );                              \
		ROUND_20_TO_39(30, PW[30] ^ W0_4 ^ W0_2                            );                              \
		ROUND_20_TO_39(31, PW[31] ^ W0_6                                   );                              \
		ROUND_20_TO_39(32, PW[32] ^ W0_3 ^ W0_2                            );                              \
		ROUND_20_TO_39(33, PW[33]                                          );                              \
		ROUND_20_TO_39(34, PW[34] ^ W0_7                                   );                              \
		ROUND_20_TO_39(35, PW[35] ^ W0_4                                   );                              \
		ROUND_20_TO_39(36, PW[36] ^ W0_6___W0_4                            );                              \
		ROUND_20_TO_39(37, PW[37] ^ W0_8                                   );                              \
		ROUND_20_TO_39(38, PW[38] ^ W0_4                                   );                              \
		ROUND_20_TO_39(39, PW[39]                                          );                              \
		                                                                                                   \
		ROUND_40_TO_59(40, PW[40] ^ W0_4 ^ W0_9                            );                              \
		ROUND_40_TO_59(41, PW[41]                                          );                              \
		ROUND_40_TO_59(42, PW[42] ^ W0_6 ^ W0_8                            );                              \
		ROUND_40_TO_59(43, PW[43] ^ W010                                   );                              \
		ROUND_40_TO_59(44, PW[44] ^ W0_6 ^ W0_3 ^ W0_7                     );                              \
		ROUND_40_TO_59(45, PW[45]                                          );                              \
		ROUND_40_TO_59(46, PW[46] ^ W0_4 ^ W011                            );                              \
		ROUND_40_TO_59(47, PW[47] ^ W0_8___W0_4                            );                              \
		ROUND_40_TO_59(48, PW[48] ^ W0_8___W0_4 ^ W0_3 ^ W010 ^ W0_5       );                              \
		ROUND_40_TO_59(49, PW[49] ^ W012                                   );                              \
		ROUND_40_TO_59(50, PW[50] ^ W0_8                                   );                              \
		ROUND_40_TO_59(51, PW[51] ^ W0_6___W0_4                            );                              \
		ROUND_40_TO_59(52, PW[52] ^ W0_8___W0_4 ^ W013                     );                              \
		ROUND_40_TO_59(53, PW[53]                                          );                              \
		ROUND_40_TO_59(54, PW[54] ^ W0_7 ^ W010 ^ W012                     );                              \
		ROUND_40_TO_59(55, PW[55] ^ W014                                   );                              \
		ROUND_40_TO_59(56, PW[56] ^ W0_6___W0_4___W0_7 ^ W011 ^ W010       );                              \
		ROUND_40_TO_59(57, PW[57] ^ W0_8                                   );                              \
		ROUND_40_TO_59(58, PW[58] ^ W0_8___W0_4 ^ W015                     );                              \
		ROUND_40_TO_59(59, PW[59] ^ W0_8___W012                            );                              \
		                                                                                                   \
		ROUND_60_TO_79(60, PW[60] ^ W0_8___W012 ^ W0_4 ^ W0_7 ^ W014       );                              \
		ROUND_60_TO_79(61, PW[61] ^ W016                                   );                              \
		ROUND_60_TO_79(62, PW[62] ^ W0_6___W0_4 ^ W0_8___W012              );                              \
		ROUND_60_TO_79(63, PW[63] ^ W0_8                                   );                              \
		ROUND_60_TO_79(64, PW[64] ^ W0_6___W0_4___W0_7 ^ W0_8___W012 ^ W017);                              \
		ROUND_60_TO_79(65, PW[65]                                          );                              \
		ROUND_60_TO_79(66, PW[66] ^ W014 ^ W016                            );                              \
		ROUND_60_TO_79(67, PW[67] ^ W0_8 ^ W018                            );                              \
		ROUND_60_TO_79(68, PW[68] ^ W011 ^ W014 ^ W015                     );                              \
		ROUND_60_TO_79(69, PW[69]                                          );                              \
		ROUND_60_TO_79(70, PW[70] ^ W012 ^ W019                            );                              \
		ROUND_60_TO_79(71, PW[71] ^ W012 ^ W016                            );                              \
		ROUND_60_TO_79(72, PW[72] ^ W011 ^ W012 ^ W018 ^ W013 ^ W016 ^ W0_5);                              \
		ROUND_60_TO_79(73, PW[73] ^ W020                                   );                              \
		ROUND_60_TO_79(74, PW[74] ^ W0_8 ^ W016                            );                              \
		ROUND_60_TO_79(75, PW[75] ^ W0_6 ^ W012 ^ W014                     );                              \
		ROUND_60_TO_79(76, PW[76] ^ W0_7 ^ W0_8 ^ W012 ^ W016 ^ W021       );                              \
		ROUND_60_TO_79(77, PW[77]                                          );                              \
		ROUND_60_TO_79(78, PW[78] ^ W0_7 ^ W0_8 ^ W015 ^ W018 ^ W020       );                              \
		ROUND_60_TO_79(79, PW[79] ^ W0_8 ^ W022                            );                              \
		                                                                                                   \
		A += H0;\
		B += H1;\
		C += H2;\
		\
		unsigned int tripcodeChunk = A >> 2;\

#define OPENCL_SHA1_USE_SMALL_CHUNK_BITMAP                                              \
		if (smallChunkBitmap[tripcodeChunk >> ((5 - SMALL_CHUNK_BITMAP_LEN_STRING) * 6)]) \
			continue;                                                                 \

#define OPENCL_SHA1_USE_CHUNK_BITMAP                                                  \
		if (chunkBitmap[tripcodeChunk >> ((5 - CHUNK_BITMAP_LEN_STRING) * 6)])          \
			continue;                                                               \
		
#define OPENCL_SHA1_LINEAR_SEARCH                                                   \
		for (unsigned int i = 0; i < numTripcodeChunk; i++){                        \
			if (tripcodeChunkArray[i] == tripcodeChunk) {                           \
				found = 1;                                                          \
				break;                                                              \
			}                                                                       \
		}                                                                           \
		if (found)                                                                  \
			break;                                                                  \

#define OPENCL_SHA1_BINARY_SEARCH                                               \
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
			found = 1;                                                          \
			break;                                                              \
		}                                                                       \

#define OPENCL_SHA1_END_OF_SEAERCH_FUNCTION \
	}\
	if (!found) {\
		output->numGeneratedTripcodes = OPENCL_SHA1_MAX_PASS_COUNT;  \
	} else {\
		__global TripcodeKeyPair *pair = &(output->pair);\
		pair->key.c[0]  = key0;\
		pair->key.c[1]  = key1;\
		pair->key.c[2]  = key2;\
		pair->key.c[3]  = key3;\
		pair->key.c[7]  = key[7];\
		pair->key.c[11] = key11;\
		pair->tripcode.c[0]  = base64CharTable[ A >> 26                  ];\
		pair->tripcode.c[1]  = base64CharTable[(A >> 20          ) & 0x3f];\
		pair->tripcode.c[2]  = base64CharTable[(A >> 14          ) & 0x3f];\
		pair->tripcode.c[3]  = base64CharTable[(A >>  8          ) & 0x3f];\
		pair->tripcode.c[4]  = base64CharTable[(A >>  2          ) & 0x3f];\
		pair->tripcode.c[5]  = base64CharTable[(B >> 28 | A <<  4) & 0x3f];\
		pair->tripcode.c[6]  = base64CharTable[(B >> 22          ) & 0x3f];\
		pair->tripcode.c[7]  = base64CharTable[(B >> 16          ) & 0x3f];\
		pair->tripcode.c[8]  = base64CharTable[(B >> 10          ) & 0x3f];\
		pair->tripcode.c[9]  = base64CharTable[(B >>  4          ) & 0x3f];\
		pair->tripcode.c[10] = base64CharTable[(B <<  2 | C >> 30) & 0x3f];\
		pair->tripcode.c[11] = base64CharTable[(C >> 24          ) & 0x3f];\
		output->numMatchingTripcodes = 1;\
		output->numGeneratedTripcodes = passCount + 1;\
	}\
}\

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_ForwardMatching_1Chunk)
	unsigned int      tripcodeChunk0 = tripcodeChunkArray[0];
OPENCL_SHA1_BEFORE_SEARCHING
	if (tripcodeChunk == tripcodeChunk0) {
		found = 1;
		break;
	}
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_ForwardMatching_Simple)
OPENCL_SHA1_BEFORE_SEARCHING
	OPENCL_SHA1_USE_SMALL_CHUNK_BITMAP
	OPENCL_SHA1_LINEAR_SEARCH
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_ForwardMatching)
OPENCL_SHA1_BEFORE_SEARCHING
	OPENCL_SHA1_USE_SMALL_CHUNK_BITMAP
	OPENCL_SHA1_USE_CHUNK_BITMAP
	OPENCL_SHA1_BINARY_SEARCH
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_BackwardMatching_Simple)
OPENCL_SHA1_BEFORE_SEARCHING
	tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff);
	OPENCL_SHA1_USE_SMALL_CHUNK_BITMAP
	OPENCL_SHA1_LINEAR_SEARCH
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_BackwardMatching)
OPENCL_SHA1_BEFORE_SEARCHING
	tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff);
	OPENCL_SHA1_USE_SMALL_CHUNK_BITMAP
	OPENCL_SHA1_USE_CHUNK_BITMAP
	OPENCL_SHA1_BINARY_SEARCH
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_Flexible_Simple)
OPENCL_SHA1_BEFORE_SEARCHING

	#define PERFORM_LINEAR_SEARCH_IF_NECESSARY                                           \
		if (!smallChunkBitmap[tripcodeChunk >> ((5 - SMALL_CHUNK_BITMAP_LEN_STRING) * 6)]) { \
			OPENCL_SHA1_LINEAR_SEARCH                                                    \
		}                                                                                \
	
	/* tripcodeChunk =  (A >>  2) */                                        PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A <<  4) & 0x3fffffff) | ((B >> 28) & 0x0000000f); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 10) & 0x3fffffff) | ((B >> 22) & 0x000003ff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 16) & 0x3fffffff) | ((B >> 16) & 0x0000ffff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 22) & 0x3fffffff) | ((B >> 10) & 0x003fffff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 28) & 0x3fffffff) | ((B >>  4) & 0x0fffffff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  2) & 0x3fffffff) | ((C >> 30) & 0x00000003); PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_Flexible)
OPENCL_SHA1_BEFORE_SEARCHING

	#define PERFORM_BINARY_SEARCH_IF_NECESSARY                                              \
		if (   !smallChunkBitmap[tripcodeChunk >> ((5 - SMALL_CHUNK_BITMAP_LEN_STRING) * 6)]    \
			&& !chunkBitmap     [tripcodeChunk >> ((5 - CHUNK_BITMAP_LEN_STRING      ) * 6)]) { \
			OPENCL_SHA1_BINARY_SEARCH                                                       \
		}                                                                                   \

	/* tripcodeChunk =  (A >>  2) */                                        PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A <<  4) & 0x3fffffff) | ((B >> 28) & 0x0000000f); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 10) & 0x3fffffff) | ((B >> 22) & 0x000003ff); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 16) & 0x3fffffff) | ((B >> 16) & 0x0000ffff); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 22) & 0x3fffffff) | ((B >> 10) & 0x003fffff); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((A << 28) & 0x3fffffff) | ((B >>  4) & 0x0fffffff); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  2) & 0x3fffffff) | ((C >> 30) & 0x00000003); PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff); PERFORM_BINARY_SEARCH_IF_NECESSARY
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_ForwardAndBackwardMatching_Simple)
OPENCL_SHA1_BEFORE_SEARCHING
	/* tripcodeChunk =  (A >>  2) */                                        PERFORM_LINEAR_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff); PERFORM_LINEAR_SEARCH_IF_NECESSARY
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION

OPENCL_SHA1_DEFINE_SEARCH_FUNCTION(OpenCL_SHA1_PerformSearching_ForwardAndBackwardMatching)
OPENCL_SHA1_BEFORE_SEARCHING
	/* tripcodeChunk =  (A >>  2) */                                        PERFORM_BINARY_SEARCH_IF_NECESSARY
	   tripcodeChunk = ((B <<  8) & 0x3fffffff) | ((C >> 24) & 0x000000ff); PERFORM_BINARY_SEARCH_IF_NECESSARY
OPENCL_SHA1_END_OF_SEAERCH_FUNCTION
