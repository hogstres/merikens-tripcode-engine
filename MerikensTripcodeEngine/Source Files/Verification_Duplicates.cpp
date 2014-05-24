// Meriken's Tripcode Engine 1.1.2
// Copyright (c) 2011-2014 Meriken//XXX <meriken.2ch@gmail.com>
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



///////////////////////////////////////////////////////////////////////////////
// INCLUDE FILE(S)                                                           //
///////////////////////////////////////////////////////////////////////////////

#include "MerikensTripcodeEngine.h"



///////////////////////////////////////////////////////////////////////////////
// VARIABLES                                                                 //
///////////////////////////////////////////////////////////////////////////////

char *crypt(char *key, char *salt);

static BOOL             wasCriticalSectionInitialized = FALSE;
static CRITICAL_SECTION criticalSection;

typedef struct TripcodeLinkedList {
	struct TripcodeLinkedList *next;
	unsigned char tripcode[MAX_LEN_TRIPCODE + 1];
} TripcodeLinkedList;

#define SIZE_MATCHED_TRIPCODE_TABLE (64 * 64)

static TripcodeLinkedList *matchedTripcodeTable[SIZE_MATCHED_TRIPCODE_TABLE];
static BOOL                wasMatchedTripcodeTableInitialized = FALSE;



///////////////////////////////////////////////////////////////////////////////
// FUNCTION DEFINITIONS                                                      //
///////////////////////////////////////////////////////////////////////////////

BOOL IsTripcodeDuplicate(unsigned char *tripcode)
{
	BOOL result = FALSE;

	if (!wasCriticalSectionInitialized) {
		InitializeCriticalSection(&criticalSection);
		wasCriticalSectionInitialized = TRUE;
	}
	EnterCriticalSection(&criticalSection);

	// Initialize the table.
	if (!wasMatchedTripcodeTableInitialized) {
		for (int i = 0; i < SIZE_MATCHED_TRIPCODE_TABLE; ++i)
			matchedTripcodeTable[i] = NULL;
		wasMatchedTripcodeTableInitialized = TRUE;
	}

	// Create a hash value from the tripcode.
	int hashValueUpper = 0;
	for (int i = 0; i < lenTripcode; i += 2) {
		int j;
		for (j = 0; j < 63 && base64CharTable[j] != tripcode[i]; ++j)
			;
		hashValueUpper ^= j;
	}
	int hashValueLower = 0;
	for (int i = 1; i < lenTripcode; i += 2) {
		int j;
		for (j = 0; j < 63 && base64CharTable[j] != tripcode[i]; ++j)
			;
		hashValueLower ^= j;
	}
	int tableIndex = (hashValueUpper * 64 + hashValueLower) % SIZE_MATCHED_TRIPCODE_TABLE;
	// printf("tableIndex = %d\n", tableIndex);

	// Check to see if the tripcode is a duplicate.
	TripcodeLinkedList *p = matchedTripcodeTable[tableIndex];
	while (p != NULL) {
		if (strncmp((char *)(p->tripcode), (char *)tripcode, lenTripcode) == 0) {
			result = TRUE;
			// printf("[DUPLICATE FOUND]\n");
			goto exit;
		}
		p = p->next;
	}

	// Add the tripcode to the table.
	TripcodeLinkedList *newNode = (TripcodeLinkedList *)malloc(sizeof(TripcodeLinkedList));
	ERROR0(newNode == NULL, ERROR_NO_MEMORY, "Not enough memory");
	newNode->next = matchedTripcodeTable[tableIndex];
	strncpy((char *)(newNode->tripcode), (char *)tripcode, lenTripcode);
	newNode->tripcode[lenTripcode] = '\0';
	matchedTripcodeTable[tableIndex] = newNode;

exit:
	LeaveCriticalSection(&criticalSection);
	return result;
}
