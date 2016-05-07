// Meriken's Tripcode Engine
// Copyright (c) 2011-2016 /Meriken/. <meriken.ygch.net@gmail.com>
//
// The initial versions of this software were based on:
// CUDA SHA-1 Tripper 0.2.1
// Copyright (c) 2009 Horo/.IBXjcg
// 
// The code that deals with DES decryption is partially adopted from:
// John the Ripper password cracker
// Copyright (c) 1996-2002, 2005, 2010 by Solar Designer
// DeepLearningJohnDoe's fork of Meriken's Tripcode Engine
// Copyright (c) 2015 by <deeplearningjohndoe at gmail.com>
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



// #define DEBUG_KEEP_TEMPORARY_FILES_FOR_OPENCL
// #define SAVE_ASSEMBLY_SOURCE



///////////////////////////////////////////////////////////////////////////////
// INCLUDE FILE(S)                                                           //
///////////////////////////////////////////////////////////////////////////////

#include "MerikensTripcodeEngine.h"
#include <boost/iostreams/stream.hpp>
#include <boost/locale.hpp>



///////////////////////////////////////////////////////////////////////////////
// OPENCL SEARCH THREAD FOR 12 CHARACTER TRIPCODES                           //
///////////////////////////////////////////////////////////////////////////////

char *ConvertOpenCLErrorCodeToString(cl_int openCLError)
{
	switch (openCLError) {
        case CL_SUCCESS:                         return "CL_SUCCESS";
        case CL_DEVICE_NOT_FOUND:                return "CL_DEVICE_NOT_FOUND";
        case CL_DEVICE_NOT_AVAILABLE:            return "CL_DEVICE_NOT_AVAILABLE";
        case CL_COMPILER_NOT_AVAILABLE:          return "CL_COMPILER_NOT_AVAILABLE";
        case CL_MEM_OBJECT_ALLOCATION_FAILURE:   return "CL_MEM_OBJECT_ALLOCATION_FAILURE";
        case CL_OUT_OF_RESOURCES:                return "CL_OUT_OF_RESOURCES";
        case CL_OUT_OF_HOST_MEMORY:              return "CL_OUT_OF_HOST_MEMORY";
        case CL_PROFILING_INFO_NOT_AVAILABLE:    return "CL_PROFILING_INFO_NOT_AVAILABLE";
        case CL_MEM_COPY_OVERLAP:                return "CL_MEM_COPY_OVERLAP";
        case CL_IMAGE_FORMAT_MISMATCH:           return "CL_IMAGE_FORMAT_MISMATCH";
        case CL_IMAGE_FORMAT_NOT_SUPPORTED:      return "CL_IMAGE_FORMAT_NOT_SUPPORTED";
        case CL_BUILD_PROGRAM_FAILURE:           return "CL_BUILD_PROGRAM_FAILURE";
        case CL_MAP_FAILURE:                     return "CL_MAP_FAILURE";
        case CL_INVALID_VALUE:                   return "CL_INVALID_VALUE";
        case CL_INVALID_DEVICE_TYPE:             return "CL_INVALID_DEVICE_TYPE";
        case CL_INVALID_PLATFORM:                return "CL_INVALID_PLATFORM";
        case CL_INVALID_DEVICE:                  return "CL_INVALID_DEVICE";
        case CL_INVALID_CONTEXT:                 return "CL_INVALID_CONTEXT";
        case CL_INVALID_QUEUE_PROPERTIES:        return "CL_INVALID_QUEUE_PROPERTIES";
        case CL_INVALID_COMMAND_QUEUE:           return "CL_INVALID_COMMAND_QUEUE";
        case CL_INVALID_HOST_PTR:                return "CL_INVALID_HOST_PTR";
        case CL_INVALID_MEM_OBJECT:              return "CL_INVALID_MEM_OBJECT";
        case CL_INVALID_IMAGE_FORMAT_DESCRIPTOR: return "CL_INVALID_IMAGE_FORMAT_DESCRIPTOR";
        case CL_INVALID_IMAGE_SIZE:              return "CL_INVALID_IMAGE_SIZE";
        case CL_INVALID_SAMPLER:                 return "CL_INVALID_SAMPLER";
        case CL_INVALID_BINARY:                  return "CL_INVALID_BINARY";
        case CL_INVALID_BUILD_OPTIONS:           return "CL_INVALID_BUILD_OPTIONS";
        case CL_INVALID_PROGRAM:                 return "CL_INVALID_PROGRAM";
        case CL_INVALID_PROGRAM_EXECUTABLE:      return "CL_INVALID_PROGRAM_EXECUTABLE";
        case CL_INVALID_KERNEL_NAME:             return "CL_INVALID_KERNEL_NAME";
        case CL_INVALID_KERNEL_DEFINITION:       return "CL_INVALID_KERNEL_DEFINITION";
        case CL_INVALID_KERNEL:                  return "CL_INVALID_KERNEL";
        case CL_INVALID_ARG_INDEX:               return "CL_INVALID_ARG_INDEX";
        case CL_INVALID_ARG_VALUE:               return "CL_INVALID_ARG_VALUE";
        case CL_INVALID_ARG_SIZE:                return "CL_INVALID_ARG_SIZE";
        case CL_INVALID_KERNEL_ARGS:             return "CL_INVALID_KERNEL_ARGS";
        case CL_INVALID_WORK_DIMENSION:          return "CL_INVALID_WORK_DIMENSION";
        case CL_INVALID_WORK_GROUP_SIZE:         return "CL_INVALID_WORK_GROUP_SIZE";
        case CL_INVALID_WORK_ITEM_SIZE:          return "CL_INVALID_WORK_ITEM_SIZE";
        case CL_INVALID_GLOBAL_OFFSET:           return "CL_INVALID_GLOBAL_OFFSET";
        case CL_INVALID_EVENT_WAIT_LIST:         return "CL_INVALID_EVENT_WAIT_LIST";
        case CL_INVALID_EVENT:                   return "CL_INVALID_EVENT";
        case CL_INVALID_OPERATION:               return "CL_INVALID_OPERATION";
        case CL_INVALID_GL_OBJECT:               return "CL_INVALID_GL_OBJECT";
        case CL_INVALID_BUFFER_SIZE:             return "CL_INVALID_BUFFER_SIZE";
        case CL_INVALID_MIP_LEVEL:               return "CL_INVALID_MIP_LEVEL";
        default:                                 return "Unknown";
    }
}

void __stdcall OnOpenCLError(const char *errorInfo, const void *privateInfo, size_t sizePrivateInfo, void *userData)
{
	fprintf(stderr, "OnOpenCLError(): %s\n", errorInfo);
}


struct {
	char   *vendor;
	char   *name;
	int32_t     numCU;
	char   *productName;

	char   *sourceFile_SHA1;
	size_t  numWorkItemsPerComputeUnit_SHA1;
	size_t  localWorkSize_SHA1;

	char   *sourceFile_DES;
	size_t  numWorkItemsPerComputeUnit_DES;
	size_t  localWorkSize_DES;
	char   *buildOptions_DES;
} static deviceSettingsArray[] = {
	{OPENCL_VENDOR_AMD,    "Cedar",                      2, "Radeon HD 5450",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Redwood",                    4, "Radeon HD 5550",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Redwood",                    5, "Radeon HD 5570/5670",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Juniper",                    9, "Radeon HD 5750",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Juniper",                   10, "Radeon HD 5770",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Cypress",                   14, "Radeon HD 5830",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Cypress",                   18, "Radeon HD 5850",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Cypress",                   20, "Radeon HD 5870",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 5120,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Hemlock",                   -1, "Radeon HD 5970",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 5120,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl",  512, 64, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_AMD,    "Saymour",                    2, "Radeon HD 6400M Series", "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Caicos",                     2, "Radeon HD 6450",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Turks",                      6, "Radeon HD 6570/6670",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Whistler",                   6, "Radeon HD 6700M Series", "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Barts",                     10, "Radeon HD 6790",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Barts",                     12, "Radeon HD 6850",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Barts",                     14, "Radeon HD 6870",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Blackcomb",                 12, "Radeon HD 6950M",        "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 1024, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Cayman",                    22, "Radeon HD 6950",         "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl",  512, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Cayman",                    -1, "Radeon HD 6970/6990",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl",  512, 64, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_AMD,    "Verde",                      8, "Radeon HD 7750",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Verde",                     10, "Radeon HD 7770",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Pitcairn",                  16, "Radeon HD 7850",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Pitcairn",                  20, "Radeon HD 7870",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Tahiti",                    28, "Radeon HD 7950",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Tahiti",                    32, "Radeon HD 7970/7990",    "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl", 1024, 128, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_AMD,    "Hawaii",                    40, "Radeon R9 290/390",         "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl",  640, 256, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Hawaii",                    44, "Radeon R9 290X/295X2/390X", "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl",  640, 256, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_AMD,    "Desna",                     -1, "Z-series",               "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Ontario",                   -1, "C/G-series",             "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Zacate",                    -1, "E/G-series",             "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Llano",                     -1, "A8/A6/A4/E2-series",     "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Hondo",                     -1, "Z-series",               "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Brazos",                    -1, "E2-series",              "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Trinity",                   -1, "A10/A8/A6/A4-series",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Devastator",                -1, "A10/A8/A6/A4-series",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},
	{OPENCL_VENDOR_AMD,    "Richland",                  -1, "A10/A8/A6/A4-series",    "OpenCL\\OpenCL12_AMD_pre-GCN.cl", 2560,  64, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_AMD,    NULL,                        -1, NULL,                     "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10.cl",  512, 256, "-O5 -cl-mad-enable"},

	{OPENCL_VENDOR_NVIDIA, NULL,                        -1, NULL,                     "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10_AMD_pre-GCN.cl",  512, 64, "-cl-nv-opt-level=3"},

	{OPENCL_VENDOR_INTEL,  "Intel(R) HD Graphics 2500", -1, NULL,                     "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, ""},
	{OPENCL_VENDOR_INTEL,  "Intel(R) HD Graphics 4000", -1, NULL,                     "OpenCL\\OpenCL12.cl",              512, 256, "OpenCL\\OpenCL10_AMD_pre-GCN.cl", 2048, 64, ""},

	{NULL}
};


 
char *GetProductNameForOpenCLDevice(char *vendor, char *name, cl_uint numComputeUnits)
{
	for (int32_t i = 0; deviceSettingsArray[i].vendor != NULL; ++i) {
		if (   (   strcmp(deviceSettingsArray[i].vendor, vendor) == 0
			    && deviceSettingsArray[i].name == NULL               )
		    || (   strcmp(deviceSettingsArray[i].vendor, vendor) == 0
			    && strcmp(deviceSettingsArray[i].name,   name  ) == 0
				&& deviceSettingsArray[i].numCU < 0                  )
			|| (   strcmp(deviceSettingsArray[i].vendor, vendor) == 0
			    && strcmp(deviceSettingsArray[i].name,   name  ) == 0
				&& (cl_uint)(deviceSettingsArray[i].numCU) == numComputeUnits))
			return deviceSettingsArray[i].productName;
	}
	return NULL;
}

void GetParametersForOpenCLDevice(cl_device_id deviceID, char *sourceFile, size_t *numWorkItemsPerComputeUnit, size_t *localWorkSize, char *buildOptions)
{
	cl_uint numComputeUnits;

	*numWorkItemsPerComputeUnit = OPENCL_SHA1_DEFAULT_NUM_WORK_ITEMS_PER_COMPUTE_UNIT;
	*localWorkSize               = OPENCL_SHA1_DEFAULT_NUM_WORK_ITEMS_PER_WORK_GROUP;
	if (sourceFile && lenTripcode == 12) {
		strcpy(sourceFile, OPENCL_SHA1_DEFAULT_SOURCE_FILE);
	} else if (sourceFile && lenTripcode == 10) {
		strcpy(sourceFile, OPENCL_DES_DEFAULT_SOURCE_FILE);
	} 
	if (buildOptions)
		strcpy(buildOptions, "");
	char    deviceVendor[LEN_LINE_BUFFER_FOR_SCREEN];
	char    deviceName  [LEN_LINE_BUFFER_FOR_SCREEN];
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_VENDOR,            sizeof(deviceVendor),    &deviceVendor,    NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_NAME,              sizeof(deviceName),      &deviceName,      NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_MAX_COMPUTE_UNITS, sizeof(numComputeUnits), &numComputeUnits, NULL));
	for (int32_t i = 0; deviceSettingsArray[i].vendor != NULL; ++i) {
		if (   (   strcmp(deviceSettingsArray[i].vendor, deviceVendor) == 0
			    && deviceSettingsArray[i].name == NULL                     )
		    || (   strcmp(deviceSettingsArray[i].vendor, deviceVendor) == 0
			    && strcmp(deviceSettingsArray[i].name,   deviceName  ) == 0
				&& deviceSettingsArray[i].numCU < 0                        )
			|| (   strcmp(deviceSettingsArray[i].vendor, deviceVendor) == 0
			    && strcmp(deviceSettingsArray[i].name,   deviceName  ) == 0
				&& (cl_uint)(deviceSettingsArray[i].numCU) == numComputeUnits)) {
			if (sourceFile && lenTripcode == 12) {
				strcpy(sourceFile, deviceSettingsArray[i].sourceFile_SHA1);
			} else if (sourceFile && lenTripcode == 10) {
				strcpy(sourceFile, deviceSettingsArray[i].sourceFile_DES);
			}
			if (buildOptions && lenTripcode == 10)
				strcpy(buildOptions, deviceSettingsArray[i].buildOptions_DES);
			*numWorkItemsPerComputeUnit = (lenTripcode == 12) ? (deviceSettingsArray[i].numWorkItemsPerComputeUnit_SHA1) : (deviceSettingsArray[i].numWorkItemsPerComputeUnit_DES);
			*localWorkSize               = (lenTripcode == 12) ? (deviceSettingsArray[i].localWorkSize_SHA1              ) : (deviceSettingsArray[i].localWorkSize_DES              );
			break;
		}
	}
	if (options.openCLNumWorkItemsPerCU != OPENCL_NUM_NUM_WORK_ITEMS_PER_CU_NIL)
		*numWorkItemsPerComputeUnit = options.openCLNumWorkItemsPerCU;
	if (options.openCLNumWorkItemsPerWG  != OPENCL_NUM_WORK_ITEMS_PER_WG_NIL)
		*localWorkSize = options.openCLNumWorkItemsPerWG;
}

void Thread_RunChildProcessForOpenCLDevice(OpenCLDeviceSearchThreadInfo *info)
{
	// This thread may be restarted. See CheckSearchThreads().
	double   prevTotalNumGeneratedTripcodes = info->totalNumGeneratedTripcodes;
	uint32_t prevNumDiscardedTripcodes      = info->numDiscardedTripcodes;
	UpdateOpenCLDeviceStatus_ChildProcess(info, "[process] Launching a child process...",  0, 0, prevTotalNumGeneratedTripcodes, prevNumDiscardedTripcodes, NULL);

	size_t  numWorkItemsPerComputeUnit = OPENCL_SHA1_DEFAULT_NUM_WORK_ITEMS_PER_COMPUTE_UNIT;
	size_t  localWorkSize = OPENCL_SHA1_DEFAULT_NUM_WORK_ITEMS_PER_WORK_GROUP;
	GetParametersForOpenCLDevice(info->openCLDeviceID, NULL, &numWorkItemsPerComputeUnit, &localWorkSize, NULL);

	char childProcessPath[MAX_LEN_COMMAND_LINE + 1];
	int32_t applicationPathLen = strlen(applicationPath);
	strcpy(childProcessPath, applicationPath);
	if (strcmp(childProcessPath + applicationPathLen - 6, "64.exe") == 0) {
		strcpy(childProcessPath + applicationPathLen - 6, ".exe"); // For 32-bit OpenCL binaries
	} else if (strcmp(childProcessPath + applicationPathLen - 13, "64_NVIDIA.exe") == 0) {
		strcpy(childProcessPath + applicationPathLen - 13, ".exe"); // For 32-bit OpenCL binaries
	}

	boost_process_spinlock.lock();

#ifdef _WIN32
	std::vector<std::wstring> args;
	typedef std::codecvt_byname<wchar_t, char, std::mbstate_t> converter_type;
	std::wstring_convert<converter_type> converter(new converter_type("cp" + std::to_string(GetACP())));
#define CONVERT_FROM_BYTES(s) converter.from_bytes(s)
#else
	std::vector<std::string> args;
#define CONVERT_FROM_BYTES(s) (s)
#endif
	args.push_back(CONVERT_FROM_BYTES(childProcessPath));
	args.push_back(CONVERT_FROM_BYTES("--output-for-redirection"));
	args.push_back(CONVERT_FROM_BYTES("--disable-tripcode-checks"));
	args.push_back(CONVERT_FROM_BYTES("-l"));
	args.push_back(CONVERT_FROM_BYTES(std::to_string(lenTripcode)));
	args.push_back(CONVERT_FROM_BYTES("-g"));
	args.push_back(CONVERT_FROM_BYTES("-d" ));
	args.push_back(CONVERT_FROM_BYTES(std::to_string(info->deviceNo)));
	args.push_back(CONVERT_FROM_BYTES("-y"));
	args.push_back(CONVERT_FROM_BYTES(std::to_string(numWorkItemsPerComputeUnit)));
	args.push_back(CONVERT_FROM_BYTES("-z"));
	args.push_back(CONVERT_FROM_BYTES(std::to_string(localWorkSize)));
	args.push_back(CONVERT_FROM_BYTES("-a"));
	args.push_back(CONVERT_FROM_BYTES(std::to_string(options.openCLNumThreads)));
	args.push_back(CONVERT_FROM_BYTES("-b"));
	args.push_back(CONVERT_FROM_BYTES("1"));
	for (int32_t patternFileIndex = 0; patternFileIndex < numPatternFiles; ++patternFileIndex) {
		args.push_back(CONVERT_FROM_BYTES("-f"));
		args.push_back(CONVERT_FROM_BYTES(std::string(patternFilePathArray[patternFileIndex])));
	}
	if (options.useOpenCLForCUDADevices)
		args.push_back(CONVERT_FROM_BYTES("--use-opencl-for-cuda-devices"));
	if (!options.enableGCNAssembler)
		args.push_back(CONVERT_FROM_BYTES("--disable-gcn-assembler"));
	if (options.useOnlyASCIICharactersForKeys) {
		args.push_back(CONVERT_FROM_BYTES("--use-ascii-characters-for-keys"));
	} else if (options.useOneByteCharactersForKeys) {
		args.push_back(CONVERT_FROM_BYTES("--use-one-byte-characters-for-keys"));
	} else if (options.maximizeKeySpace) {
		args.push_back(CONVERT_FROM_BYTES("--maximize-key-space"));
	} else {
		args.push_back(CONVERT_FROM_BYTES("--use-one-and-two-byte-characters-for-keys"));
	}
	if (pause_event.is_open()) {
		args.push_back(CONVERT_FROM_BYTES("-e"));
		args.push_back(CONVERT_FROM_BYTES(pause_event.name()));
	}
	if (termination_event.is_open()) {
		args.push_back(CONVERT_FROM_BYTES("-E"));
		args.push_back(CONVERT_FROM_BYTES(termination_event.name()));
	}

	boost::process::pipe pipe = boost::process::create_pipe();
	boost::iostreams::file_descriptor_sink sink(pipe.sink, boost::iostreams::close_handle);
	boost::process::child child_process = boost::process::execute(
		boost::process::initializers::set_args(args),
		boost::process::initializers::bind_stdout(sink),
		boost::process::initializers::start_in_dir(applicationDirectory),
		boost::process::initializers::inherit_env());
	boost::iostreams::file_descriptor_source source(pipe.source, boost::iostreams::close_handle);
	boost::iostreams::stream<boost::iostreams::file_descriptor_source> input_stream(source);

	boost_process_spinlock.unlock();

	while(!GetTerminationState())
	{
		std::string line;
		if (!std::getline(input_stream, line))
			break;
		char line_buffer[65536];
		strncpy(line_buffer, line.data(), sizeof(line_buffer) - 1);
		line_buffer[sizeof(line_buffer) - 1] = '\0';

		if (strncmp(line_buffer, "[tripcode],", strlen("[tripcode],")) == 0) {
			unsigned char tripcode[MAX_LEN_TRIPCODE + 1];
			unsigned char key     [MAX_LEN_TRIPCODE_KEY + 1];
			int32_t i, j;
			ASSERT(line_buffer[10 + 1 + 2 + lenTripcode                         ] == ',');
			ASSERT(line_buffer[10 + 1 + 2 + lenTripcode + 1                     ] == '#');
			ASSERT(line_buffer[10 + 1 + 2 + lenTripcode + 1 + 1 + lenTripcodeKey] == ',');
			for (i = 0, j = 10 + 1 + 2; i < lenTripcode; ++i, ++j)
				tripcode[i] = line_buffer[j];
			for (i = 0, j = 10 + 1 + 2 + lenTripcodeKey + 1 + 1; i < lenTripcodeKey; ++i, ++j)
				key[i] = line_buffer[j];
			tripcode[lenTripcode] = '\0';
			key     [lenTripcodeKey] = '\0';
			ProcessPossibleMatch(tripcode, key);
		} else if (strncmp(line_buffer, "[status],", strlen("[status],")) == 0) {
			double       currentSpeed, averageSpeed, totalNumGeneratedTripcodes;
			uint32_t numDiscardedTripcodes;
			char *delimiter = ",";
			char *currentToken = strtok(line_buffer, delimiter);                                                                                           //     "[status]"
			BOOL isGood = (currentToken != NULL);
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          //     totalTime,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL) && 1 == sscanf(currentToken, "%lf", &currentSpeed);       // 	   currentSpeed,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   currentSpeed_GPU,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   currentSpeed_CPU,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL) && 1 == sscanf(currentToken, "%lf", &averageSpeed);       // 	   averageSpeed,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   timeForOneMatch,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   (int32_t)(matchingProbDiff * 100),
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL) && 1 == sscanf(currentToken, "%lf", &totalNumGeneratedTripcodes); // 	   prevTotalNumGeneratedTripcodes,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   prevNumValidTripcodes,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   IsCUDADeviceOptimizationInProgress(),
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   averageSpeed_GPU,
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL);                                                          // 	   averageSpeed_CPU);
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL) && 1 == sscanf(currentToken, "%u",  &numDiscardedTripcodes);      // 	   numDiscardedTripcodes
			if (isGood) {
				char status[LEN_LINE_BUFFER_FOR_SCREEN] = "";
				sprintf(status,
						"[process] %.1lfM TPS, %d WI/CU, %d WI/WG, Restarts: %u",
						averageSpeed / 1000000,
						numWorkItemsPerComputeUnit,
						localWorkSize,
						info->numRestarts);
				UpdateOpenCLDeviceStatus_ChildProcess(info, 
													  status, 
													  currentSpeed, 
													  averageSpeed, 
													  prevTotalNumGeneratedTripcodes + totalNumGeneratedTripcodes, 
													  prevNumDiscardedTripcodes      + numDiscardedTripcodes, 
													  &child_process);
			}
		} else if (strncmp(line_buffer, "[error],", strlen("[error],")) == 0) {
			int32_t   errorCode;
			char *delimiter = ",";
			char *currentToken = strtok(line_buffer, delimiter); // "[error]"
			BOOL isGood = (currentToken != NULL);
			currentToken = strtok(NULL, delimiter); isGood = isGood && (currentToken != NULL) && 1 == sscanf(currentToken, "%d", &errorCode);
			errorCode = (isGood) ? (errorCode) : (ERROR_UNKNOWN);
			if (errorCode != ERROR_SEARCH_THREAD_UNRESPONSIVE) {
				ERROR0(TRUE, errorCode, GetErrorMessage(errorCode));
			}
		}
	}
}

static void CreateProgramFromGCNAssemblySource(cl_context *context, cl_program *program, cl_device_id *deviceID, char *deviceName, char *deviceVersion, char *driverVersion)
{
	cl_int         openCLError;
	
	system_command_spinlock.lock();

	char    binaryFilePath[MAX_LEN_FILE_PATH + 1];
	FILE   *binaryFile;
	sprintf(binaryFilePath, "%s\\OpenCL\\bin\\OpenCL12GCN_%02x%02x%02x%02x.bin", applicationDirectory, RandomByte(), RandomByte(), RandomByte(), RandomByte());
	
	char    sourceFilePath[MAX_LEN_FILE_PATH + 1];
	FILE   *sourceFile;
	sprintf(sourceFilePath, "%s\\OpenCL\\bin\\OpenCL12GCN.asm", applicationDirectory);
	
	int driverMajorVersion;
	int driverMinorVersion;
	char rest[LEN_LINE_BUFFER_FOR_SCREEN];
	sscanf(driverVersion, "%d.%d%s", &driverMajorVersion, &driverMinorVersion, rest);
	
	char    assemblerCommand[MAX_LEN_COMMAND_LINE + 1];
	sprintf(assemblerCommand, 
		    "cmd /C \"\"%s\\CLRadeonExtender\\clrxasm\" -b %s -g %s -A %s -t %d%02d -o \"%s\" \"%s\"\"",
			applicationDirectory,
			"amd",
			deviceName,
			(   strcmp(deviceName, "CapeVerde") == 0
			 || strcmp(deviceName, "Pitcairn" ) == 0
			 || strcmp(deviceName, "Tahiti"   ) == 0
			 || strcmp(deviceName, "Oland"    ) == 0
			 || strcmp(deviceName, "Iceland"  ) == 0) ? "gcn1.0" :
	        (   strcmp(deviceName, "Bonaire"  ) == 0
			 || strcmp(deviceName, "Spectre"  ) == 0
			 || strcmp(deviceName, "Spooky"   ) == 0
			 || strcmp(deviceName, "Kalindi"  ) == 0
			 || strcmp(deviceName, "Hainan"   ) == 0
			 || strcmp(deviceName, "Hawaii"   ) == 0
			 || strcmp(deviceName, "Mullins"  ) == 0) ? "gcn1.1" :
	                                                    "gcn1.2",
            driverMajorVersion, 
			driverMinorVersion, 
			binaryFilePath,
			sourceFilePath);
	ERROR0(system(assemblerCommand) != 0, ERROR_GCN_ASSEMBLER, "Failed to assemble GCN kernel.");

	binaryFile = fopen(binaryFilePath, "rb");
	ERROR0(   binaryFile == NULL
		   || fseek(binaryFile, 0L, SEEK_END) != 0, 
		   ERROR_GCN_ASSEMBLER,
		   "Failed to load GCN kernel.");
	size_t binarySize = ftell(binaryFile);
	unsigned char *binary = (unsigned char *)malloc(binarySize);
	const unsigned char *binaryArray[1] = {binary};
	ERROR0(binary == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
	ERROR0(   fseek(binaryFile, 0L, SEEK_SET) != 0
		   || fread(binary, sizeof(unsigned char), binarySize, binaryFile) != binarySize,
		   ERROR_GCN_ASSEMBLER,
		   "Failed to load GCN kernel.");
	fclose(binaryFile);

	*program = clCreateProgramWithBinary(*context, 1, deviceID, &binarySize, binaryArray, NULL, &openCLError);
	OPENCL_ERROR(openCLError);
	openCLError = clBuildProgram(*program, 1, deviceID, NULL, NULL, NULL);
	OPENCL_ERROR(openCLError);
		
	free(binary);
	
	sprintf(assemblerCommand, "cmd /C \"del \"%s\"\"", binaryFilePath);
	system(assemblerCommand);

	system_command_spinlock.unlock();
}

void Thread_SearchForSHA1TripcodesOnOpenCLDevice(OpenCLDeviceSearchThreadInfo *info)
{
	cl_int         openCLError;
	cl_device_id   deviceID = info->openCLDeviceID;
	cl_uint        numComputeUnits;
	char           status[LEN_LINE_BUFFER_FOR_SCREEN] = "";
	char           buildOptions[MAX_LEN_COMMAND_LINE + 1] = ""; 
	unsigned char  key[MAX_LEN_TRIPCODE + 1];

	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_MAX_COMPUTE_UNITS, sizeof(numComputeUnits), &numComputeUnits, NULL));
	key[lenTripcode] = '\0';
	
	// Determine the sizes of local and global work items.
	size_t numWorkItemsPerComputeUnit;
	size_t localWorkSize;
	size_t globalWorkSize;
	char   sourceFileName[MAX_LEN_FILE_PATH + 1];
	GetParametersForOpenCLDevice(deviceID, sourceFileName, &numWorkItemsPerComputeUnit, &localWorkSize, buildOptions);
	globalWorkSize = numWorkItemsPerComputeUnit * numComputeUnits;

	char    deviceVendor[LEN_LINE_BUFFER_FOR_SCREEN];
	char    deviceName  [LEN_LINE_BUFFER_FOR_SCREEN];
	char deviceVersion[LEN_LINE_BUFFER_FOR_SCREEN];
	char driverVersion[LEN_LINE_BUFFER_FOR_SCREEN];
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_MAX_COMPUTE_UNITS, sizeof(numComputeUnits), &numComputeUnits, NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_VENDOR,            sizeof(deviceVendor),    &deviceVendor,    NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_NAME,              sizeof(deviceName),      &deviceName,      NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DEVICE_VERSION,           sizeof(deviceVersion),    &deviceVersion,    NULL));
	OPENCL_ERROR(clGetDeviceInfo(deviceID, CL_DRIVER_VERSION,           sizeof(driverVersion),    &driverVersion,    NULL));
	BOOL enableGCNAssembler =    options.enableGCNAssembler
		                      && (strcmp(deviceVendor, OPENCL_VENDOR_AMD) == 0)
		                      && (   strcmp(deviceName, "CapeVerde") == 0
						          || strcmp(deviceName, "Pitcairn") == 0
						          || strcmp(deviceName, "Tahiti") == 0
						          || strcmp(deviceName, "Oland") == 0
						          || strcmp(deviceName, "Iceland") == 0

						          || strcmp(deviceName, "Bonaire") == 0
						          || strcmp(deviceName, "Spectre") == 0
						          || strcmp(deviceName, "Spooky") == 0
						          || strcmp(deviceName, "Kalindi") == 0
						          || strcmp(deviceName, "Hainan") == 0
						          || strcmp(deviceName, "Hawaii") == 0
						          || strcmp(deviceName, "Mullins") == 0
						          /*
								  || strcmp(deviceName, "Tonga") == 0
						          || strcmp(deviceName, "Fiji") == 0
						          || strcmp(deviceName, "Carrizo") == 0 */)
						   && (   strncmp(deviceVersion, "OpenCL 1.2", 10) == 0
						       || strncmp(deviceVersion, "OpenCL 2.0", 10) == 0);
	BOOL isIntelHDGraphics = FALSE;
	if (   strcmp(deviceVendor, OPENCL_VENDOR_INTEL) == 0
		&& strncmp(deviceName, "Intel(R) HD Graphics", strlen("Intel(R) HD Graphics")) == 0) {
		// There is a bug in the Intel OpenCL driver.
		// ERROR0(TRUE, ERROR_INTEL_HD_GRAPHICS, "This software is not compatible with the Intel(R) HD Graphics series.");
		strcat(buildOptions, " -D INTEL_HD_GRAPHICS ");
	}
#ifdef DEBUG_KEEP_TEMPORARY_FILES_FOR_OPENCL
	strcat(buildOptions, " -save-temps=OpenCL12.cl ");
#endif

	// Load an OpenCL source code
	char    sourceFilePath[MAX_LEN_FILE_PATH + 1];
    FILE   *sourceFile;
    char   *sourceCode;
    size_t  sizeSourceCode;
	strcpy(sourceFilePath, applicationDirectory);
	strcat(sourceFilePath, "\\");
	strcat(sourceFilePath, sourceFileName);
    sourceFile = fopen(sourceFilePath, "r");
    ERROR0(!sourceFile, ERROR_OPENCL, "Failed to load an OpenCL source file.");
    sourceCode = (char*)malloc(OPENCL_MAX_SIZE_SOURCE_CODE);
	ERROR0(sourceCode == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
    sizeSourceCode = fread(sourceCode, 1, OPENCL_MAX_SIZE_SOURCE_CODE, sourceFile);
    fclose(sourceFile);

	cl_context       context      = clCreateContext(NULL, 1, &deviceID, OnOpenCLError, NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_command_queue commandQueue = clCreateCommandQueue(context, deviceID, 0, &openCLError);               OPENCL_ERROR(openCLError);
	cl_program       program;
	if (enableGCNAssembler) {
		CreateProgramFromGCNAssemblySource(&context, &program, &deviceID, deviceName, deviceVersion, driverVersion);
	} else {
		// Create an OpenCL kernel from the source code.
		if (options.maximizeKeySpace)
			strcat(buildOptions, " -D MAXIMIZE_KEY_SPACE ");
		// strcat(buildOptions, " -save-temps=OpenCL10.cl ");
		program = clCreateProgramWithSource(context, 1, (const char **)&sourceCode, (const size_t *)&sizeSourceCode, &openCLError);
		openCLError = clBuildProgram(program, 1, &deviceID, buildOptions, NULL, NULL);
		if (openCLError != CL_SUCCESS && !options.redirection) {
			size_t lenBuildLog= 0;
			char  *buildLog = NULL;
			clGetProgramBuildInfo(program, deviceID, CL_PROGRAM_BUILD_LOG, 0, NULL, &lenBuildLog);
			if ((buildLog = (char *)malloc(lenBuildLog + 1)) != NULL) {
				clGetProgramBuildInfo(program, deviceID, CL_PROGRAM_BUILD_LOG, lenBuildLog, buildLog, &lenBuildLog);
				buildLog[lenBuildLog] = '\0';
				fprintf(stderr, "%s\n", buildLog);
				free(buildLog);
			}
		}
		OPENCL_ERROR(openCLError);
	}
	char *nameKernelFunction;
	if (searchMode == SEARCH_MODE_FORWARD_MATCHING) {
		nameKernelFunction = "OpenCL_SHA1_PerformSearching_ForwardMatching";
	} else if (searchMode == SEARCH_MODE_BACKWARD_MATCHING) {
		nameKernelFunction = "OpenCL_SHA1_PerformSearching_BackwardMatching";
	} else if (searchMode == SEARCH_MODE_FORWARD_AND_BACKWARD_MATCHING) {
		nameKernelFunction = "OpenCL_SHA1_PerformSearching_ForwardAndBackwardMatching";
	} else {
		nameKernelFunction = "OpenCL_SHA1_PerformSearching_Flexible";
	}
	// printf("nameKernelFunction = %s\n", nameKernelFunction);
	cl_kernel kernel = clCreateKernel(program, nameKernelFunction, &openCLError);
   	OPENCL_ERROR(openCLError);

	//
#ifdef SAVE_ASSEMBLY_SOURCE
	size_t numDevices;
	openCLError = clGetProgramInfo(program, CL_PROGRAM_NUM_DEVICES, sizeof(size_t), &numDevices, NULL);
	OPENCL_ERROR(openCLError);
	size_t *binarySizeArray = (size_t *)malloc(sizeof(size_t) * numDevices);
	ERROR0(binarySizeArray == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
	openCLError = clGetProgramInfo(program, CL_PROGRAM_BINARY_SIZES, sizeof(size_t) * numDevices, binarySizeArray, NULL);
	OPENCL_ERROR(openCLError);
	unsigned char **binaryArray = (unsigned char **)malloc(sizeof(unsigned char *) * numDevices);
	ERROR0(binaryArray == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
	for(int32_t i = 0; i < numDevices; ++i) {
		binaryArray[i] = (unsigned char *)malloc(binarySizeArray[i]);
		ERROR0(binaryArray[i] == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
	}
	openCLError = clGetProgramInfo(program, CL_PROGRAM_BINARIES, sizeof(unsigned char *) * numDevices, binaryArray, NULL);
	OPENCL_ERROR(openCLError);
	char    binaryFilePath[MAX_LEN_FILE_PATH + 1];
	FILE   *binaryFile;
	sprintf(binaryFilePath, "%s\\OpenCL\\bin\\OpenCL12GCN_%02x%02x%02x%02x.bin", applicationDirectory, RandomByte(), RandomByte(), RandomByte(), RandomByte());
	if (binaryFile = fopen(binaryFilePath, "wb")) {
		fwrite(binaryArray[0], sizeof(unsigned char), binarySizeArray[0], binaryFile);
		fclose(binaryFile);
	}
	free(binarySizeArray);
	for(int32_t i = 0; i < numDevices; ++i)
		free(binaryArray[i]);
	free(binaryArray);
	sprintf(sourceFilePath, "%s\\OpenCL\\bin\\OpenCL12GCN_%02x%02x%02x%02x.asm", applicationDirectory, RandomByte(), RandomByte(), RandomByte(), RandomByte());
	char    assemblerCommand[MAX_LEN_COMMAND_LINE + 1];
	sprintf(assemblerCommand, "cmd /C \"\"%s\\CLRadeonExtender\\clrxdisasm\" -m -d -c -f \"%s\" > \"%s\"\"", applicationDirectory, binaryFilePath, sourceFilePath);
	system(assemblerCommand);
	sprintf(assemblerCommand, "cmd /C \"del \"%s\"\"", binaryFilePath);
	system(assemblerCommand);
#endif

	// Create memory blocks for CPU.
	uint32_t  sizeOutputArray = globalWorkSize;
	GPUOutput    *outputArray     = (GPUOutput *)malloc(sizeof(GPUOutput) * sizeOutputArray);
	ERROR0(outputArray == NULL, ERROR_NO_MEMORY, GetErrorMessage(ERROR_NO_MEMORY));
	// printf("sizeOutputArray = %u\n", sizeOutputArray);

	// Create memory blocks for the OpenCL device.
	cl_mem openCL_outputArray                       = clCreateBuffer(context, CL_MEM_WRITE_ONLY, sizeof(GPUOutput) * sizeOutputArray,     NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_key                               = clCreateBuffer(context, CL_MEM_READ_ONLY,  sizeof(key),                             NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_tripcodeChunkArray                = clCreateBuffer(context, CL_MEM_READ_ONLY,  sizeof(uint32_t) * numTripcodeChunk, NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_keyCharTable_OneByte              = clCreateBuffer(context, CL_MEM_READ_ONLY,  SIZE_KEY_CHAR_TABLE,                     NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_keyCharTable_FirstByte            = clCreateBuffer(context, CL_MEM_READ_ONLY,  SIZE_KEY_CHAR_TABLE,                     NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_keyCharTable_SecondByte           = clCreateBuffer(context, CL_MEM_READ_ONLY,  SIZE_KEY_CHAR_TABLE,                     NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_keyCharTable_SecondByteAndOneByte = clCreateBuffer(context, CL_MEM_READ_ONLY,  SIZE_KEY_CHAR_TABLE,                     NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_smallChunkBitmap                    = clCreateBuffer(context, CL_MEM_READ_ONLY,  SMALL_CHUNK_BITMAP_SIZE,                   NULL, &openCLError); OPENCL_ERROR(openCLError);
	cl_mem openCL_chunkBitmap                         = clCreateBuffer(context, CL_MEM_READ_ONLY,  CHUNK_BITMAP_SIZE,                         NULL, &openCLError); OPENCL_ERROR(openCLError);
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_tripcodeChunkArray,                CL_TRUE, 0, sizeof(uint32_t) * numTripcodeChunk, tripcodeChunkArray,                0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_keyCharTable_OneByte,              CL_TRUE, 0, SIZE_KEY_CHAR_TABLE,                     keyCharTable_OneByte,              0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_keyCharTable_FirstByte,            CL_TRUE, 0, SIZE_KEY_CHAR_TABLE,                     keyCharTable_FirstByte,            0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_keyCharTable_SecondByte,           CL_TRUE, 0, SIZE_KEY_CHAR_TABLE,                     keyCharTable_SecondByte,           0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_keyCharTable_SecondByteAndOneByte, CL_TRUE, 0, SIZE_KEY_CHAR_TABLE,                     keyCharTable_SecondByteAndOneByte, 0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_smallChunkBitmap,                    CL_TRUE, 0, SMALL_CHUNK_BITMAP_SIZE,                   smallChunkBitmap,                    0, NULL, NULL));
	OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_chunkBitmap,                         CL_TRUE, 0, CHUNK_BITMAP_SIZE,                         chunkBitmap,                         0, NULL, NULL));

	// The main loop of the thread. 
	double       timeElapsed = 0;
	double       numGeneratedTripcodes = 0;
	double       averageSpeed = 0;
	uint64_t        startingTime = TIME_SINCE_EPOCH_IN_MILLISECONDS;
	uint64_t        endingTime;
	double       deltaTime;
	while (!GetTerminationState()) {
		// Choose a random key.
		SetCharactersInTripcodeKeyForSHA1Tripcode(key);
		while (TRUE) {
			key[7] = ((key[7] & 0xfc) | 0x00); if (!IsValidKey(key)) { SetCharactersInTripcodeKeyForSHA1Tripcode(key); continue; }
			key[7] = ((key[7] & 0xfc) | 0x01); if (!IsValidKey(key)) { SetCharactersInTripcodeKeyForSHA1Tripcode(key); continue; }
			key[7] = ((key[7] & 0xfc) | 0x02); if (!IsValidKey(key)) { SetCharactersInTripcodeKeyForSHA1Tripcode(key); continue; }
			key[7] = ((key[7] & 0xfc) | 0x03); if (!IsValidKey(key)) { SetCharactersInTripcodeKeyForSHA1Tripcode(key); continue; }
			break;
		}
		for (int32_t i = 0; i < 4; ++i)
			key[i] = RandomByte();
		key[11] = RandomByte();

		// Execute the OpenCL kernel
		OPENCL_ERROR(clEnqueueWriteBuffer(commandQueue, openCL_key, CL_TRUE, 0, sizeof(key), key, 0, NULL, NULL));
		OPENCL_ERROR(clSetKernelArg(kernel, 0, sizeof(cl_mem),       (void *)&openCL_outputArray));
		OPENCL_ERROR(clSetKernelArg(kernel, 1, sizeof(cl_mem),       (void *)&openCL_key));
		OPENCL_ERROR(clSetKernelArg(kernel, 2, sizeof(cl_mem),       (void *)&openCL_tripcodeChunkArray));
		OPENCL_ERROR(clSetKernelArg(kernel, 3, sizeof(uint32_t), (void *)&numTripcodeChunk));
		OPENCL_ERROR(clSetKernelArg(kernel, 4, sizeof(cl_mem),       (void *)&openCL_keyCharTable_OneByte));
		OPENCL_ERROR(clSetKernelArg(kernel, 5, sizeof(cl_mem),       (void *)&openCL_keyCharTable_FirstByte));
		OPENCL_ERROR(clSetKernelArg(kernel, 6, sizeof(cl_mem),       (void *)&openCL_keyCharTable_SecondByte));
		OPENCL_ERROR(clSetKernelArg(kernel, 7, sizeof(cl_mem),       (void *)&openCL_keyCharTable_SecondByteAndOneByte));
		OPENCL_ERROR(clSetKernelArg(kernel, 8, sizeof(cl_mem),       (void *)&openCL_smallChunkBitmap));
		OPENCL_ERROR(clSetKernelArg(kernel, 9, sizeof(cl_mem),       (void *)&openCL_chunkBitmap));
		// printf("globalWorkSize = [%u]\n", globalWorkSize);
		// printf("localWorkSize  = [%u]\n", localWorkSize);
		// size_t sizeWorkGroup;
		// OPENCL_ERROR(clGetKernelWorkGroupInfo(kernel, deviceID, CL_KERNEL_WORK_GROUP_SIZE, sizeof(size_t), &sizeWorkGroup, NULL));
		// printf("sizeWorkGroup  = [%u]\n", sizeWorkGroup);
		OPENCL_ERROR(clEnqueueNDRangeKernel(commandQueue, kernel, 1, NULL, &globalWorkSize, &localWorkSize, 0, NULL, NULL));
		OPENCL_ERROR(clEnqueueReadBuffer(commandQueue, openCL_outputArray, CL_TRUE, 0, sizeOutputArray * sizeof(GPUOutput), outputArray, 0, NULL, NULL));
	    OPENCL_ERROR(clFlush (commandQueue));
	    OPENCL_ERROR(clFinish(commandQueue));
		for (uint32_t indexOutput = 0; indexOutput < sizeOutputArray; indexOutput++){
			GPUOutput *output = &outputArray[indexOutput];
			ASSERT(output->numGeneratedTripcodes <= 2048 * 4);
			ASSERT(output->numMatchingTripcodes <= 1);
		}
		numGeneratedTripcodes += ProcessGPUOutput(key, outputArray, sizeOutputArray, TRUE);

		// Measure the current speed.
		endingTime = TIME_SINCE_EPOCH_IN_MILLISECONDS;
		deltaTime = (endingTime - startingTime) * 0.001;
		while (GetPauseState() && !GetTerminationState())
			sleep_for_milliseconds(PAUSE_INTERVAL);
		startingTime = TIME_SINCE_EPOCH_IN_MILLISECONDS;
		timeElapsed += deltaTime;
		averageSpeed = numGeneratedTripcodes / timeElapsed;
		
		// Update the current status.
		sprintf(status,
			    "[thread] %.1lfM TPS, %d WI, %d WI/CU, %d WI/WG",
				averageSpeed / 1000000,
				globalWorkSize,
				numWorkItemsPerComputeUnit,
				localWorkSize);
		UpdateOpenCLDeviceStatus(info, status);
	}
 
    // Clean up.
    OPENCL_ERROR(clFlush(commandQueue));
    OPENCL_ERROR(clFinish(commandQueue));
    OPENCL_ERROR(clReleaseKernel(kernel));
    OPENCL_ERROR(clReleaseProgram(program));
    OPENCL_ERROR(clReleaseMemObject(openCL_outputArray));
    OPENCL_ERROR(clReleaseMemObject(openCL_key));
    OPENCL_ERROR(clReleaseMemObject(openCL_tripcodeChunkArray));
    OPENCL_ERROR(clReleaseMemObject(openCL_keyCharTable_OneByte));
    OPENCL_ERROR(clReleaseMemObject(openCL_keyCharTable_FirstByte));
    OPENCL_ERROR(clReleaseMemObject(openCL_keyCharTable_SecondByte));
    OPENCL_ERROR(clReleaseMemObject(openCL_keyCharTable_SecondByteAndOneByte));
    OPENCL_ERROR(clReleaseMemObject(openCL_smallChunkBitmap));
    OPENCL_ERROR(clReleaseCommandQueue(commandQueue));
    OPENCL_ERROR(clReleaseContext(context));
}

