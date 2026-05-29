/**
 * FreeRDP: A Remote Desktop Protocol Implementation
 *
 * Copyright 2014 Marc-Andre Moreau <marcandre.moreau@gmail.com>
 * Copyright 2015 Thincast Technologies GmbH
 * Copyright 2015 DI (FH) Martin Haimberger <martin.haimberger@thincast.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Clipboard.h"
#import "MRDPView.h"

#include <winpr/endian.h>
#include <winpr/file.h>
#include <freerdp/utils/cliprdr_utils.h>

static UINT mac_cliprdr_send_file_contents_failure(wClipboardDelegate *delegate, UINT32 streamId);

#define MAC_CLIPRDR_FILE_CHUNK_SIZE (1024 * 1024)

static const char type_FileGroupDescriptorW[] = "FileGroupDescriptorW";

static BOOL mac_cliprdr_create_remote_file_path(mfContext *mfc, const FILEDESCRIPTORW *descriptor,
                                                char **path);

static void mac_cliprdr_clear_remote_files(mfContext *mfc)
{
	if (!mfc)
		return;

	for (UINT32 index = 0; index < mfc->remoteFileCount; index++)
		free(mfc->remoteFiles[index].localPath);

	free(mfc->remoteFiles);
	mfc->remoteFiles = nullptr;
	mfc->remoteFileCount = 0;
	free(mfc->remoteFilePasteDir);
	mfc->remoteFilePasteDir = nullptr;
}

static BOOL mac_cliprdr_all_remote_files_complete(const mfContext *mfc)
{
	if (!mfc || (mfc->remoteFileCount == 0))
		return FALSE;

	for (UINT32 index = 0; index < mfc->remoteFileCount; index++)
	{
		if (!mfc->remoteFiles[index].complete)
			return FALSE;
	}

	return TRUE;
}

static UINT mac_cliprdr_publish_remote_files(mfContext *mfc)
{
	MRDPView *view = (MRDPView *)mfc->view;
	NSMutableArray *urls = [NSMutableArray arrayWithCapacity:mfc->remoteFileCount];

	for (UINT32 index = 0; index < mfc->remoteFileCount; index++)
	{
		const char *path = mfc->remoteFiles[index].localPath;
		if (!path)
			continue;

		NSString *nsPath = [NSString stringWithUTF8String:path];
		if (!nsPath)
			continue;

		NSURL *url = [NSURL fileURLWithPath:nsPath];
		if (url)
			[urls addObject:url];
	}

	if ([urls count] == 0)
		return CHANNEL_RC_OK;

	[view->pasteboard_wr clearContents];
	[view->pasteboard_wr writeObjects:urls];
	return CHANNEL_RC_OK;
}

static UINT mac_cliprdr_request_remote_file_range(mfContext *mfc, mfClipboardRemoteFile *file)
{
	if (!mfc || !mfc->cliprdr || !file || file->complete)
		return CHANNEL_RC_OK;

	const UINT64 remaining = file->size - file->received;
	const UINT32 requested = (remaining > MAC_CLIPRDR_FILE_CHUNK_SIZE)
	                             ? MAC_CLIPRDR_FILE_CHUNK_SIZE
	                             : (UINT32)remaining;

	if (requested == 0)
	{
		file->complete = TRUE;
		if (mac_cliprdr_all_remote_files_complete(mfc))
			return mac_cliprdr_publish_remote_files(mfc);
		return CHANNEL_RC_OK;
	}

	CLIPRDR_FILE_CONTENTS_REQUEST request = WINPR_C_ARRAY_INIT;
	file->streamId = mfc->remoteFileStreamIdNext++;
	request.common.msgType = CB_FILECONTENTS_REQUEST;
	request.streamId = file->streamId;
	request.listIndex = file->listIndex;
	request.dwFlags = FILECONTENTS_RANGE;
	request.nPositionLow = (UINT32)(file->received & 0xFFFFFFFF);
	request.nPositionHigh = (UINT32)(file->received >> 32);
	request.cbRequested = requested;
	return mfc->cliprdr->ClientFileContentsRequest(mfc->cliprdr, &request);
}

static UINT mac_cliprdr_request_next_remote_file(mfContext *mfc)
{
	for (UINT32 index = 0; index < mfc->remoteFileCount; index++)
	{
		if (!mfc->remoteFiles[index].complete)
			return mac_cliprdr_request_remote_file_range(mfc, &mfc->remoteFiles[index]);
	}

	return mac_cliprdr_publish_remote_files(mfc);
}

static UINT mac_cliprdr_handle_remote_file_list(mfContext *mfc,
                                                const CLIPRDR_FORMAT_DATA_RESPONSE *response)
{
	FILEDESCRIPTORW *descriptors = nullptr;
	UINT32 descriptorCount = 0;

	mac_cliprdr_clear_remote_files(mfc);

	if (cliprdr_parse_file_list(response->requestedFormatData, response->common.dataLen, &descriptors,
	                            &descriptorCount) != CHANNEL_RC_OK)
		return CHANNEL_RC_OK;

	mfc->remoteFiles = (mfClipboardRemoteFile *)calloc(descriptorCount, sizeof(mfClipboardRemoteFile));
	if (!mfc->remoteFiles)
	{
		free(descriptors);
		return CHANNEL_RC_NO_MEMORY;
	}

	mfc->remoteFileStreamIdNext = 1;

	for (UINT32 index = 0; index < descriptorCount; index++)
	{
		const FILEDESCRIPTORW *descriptor = &descriptors[index];
		mfClipboardRemoteFile *file = &mfc->remoteFiles[mfc->remoteFileCount];

		if (descriptor->dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
			continue;

		if (!mac_cliprdr_create_remote_file_path(mfc, descriptor, &file->localPath))
			continue;

		file->listIndex = index;
		file->size = (((UINT64)descriptor->nFileSizeHigh) << 32) | descriptor->nFileSizeLow;
		file->received = 0;
		file->complete = FALSE;

		if (file->size == 0)
		{
			NSString *path = [NSString stringWithUTF8String:file->localPath];
			[[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data] attributes:nil];
			file->complete = TRUE;
		}

		mfc->remoteFileCount++;
	}

	free(descriptors);

	if (mfc->remoteFileCount == 0)
		return CHANNEL_RC_OK;

	return mac_cliprdr_request_next_remote_file(mfc);
}

static BOOL mac_cliprdr_create_remote_file_path(mfContext *mfc, const FILEDESCRIPTORW *descriptor,
                                                char **path)
{
	char name[MAX_PATH] = WINPR_C_ARRAY_INIT;

	if (ConvertWCharNToUtf8(descriptor->cFileName, ARRAYSIZE(descriptor->cFileName), name,
	                        ARRAYSIZE(name)) < 1)
		return FALSE;

	NSString *fileName = [NSString stringWithUTF8String:name];
	fileName = [[fileName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] lastPathComponent];

	if (!fileName || ([fileName length] == 0))
		return FALSE;

	if (!mfc->remoteFilePasteDir)
	{
		NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:@"MacFreeRDP-Clipboard"];
		NSString *session = [base stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
		NSError *error = nil;

		if (![[NSFileManager defaultManager] createDirectoryAtPath:session
		                                withIntermediateDirectories:YES
		                                                 attributes:nil
		                                                      error:&error])
			return FALSE;

		mfc->remoteFilePasteDir = _strdup([session fileSystemRepresentation]);
		if (!mfc->remoteFilePasteDir)
			return FALSE;
	}

	NSString *dir = [NSString stringWithUTF8String:mfc->remoteFilePasteDir];
	NSString *filePath = [dir stringByAppendingPathComponent:fileName];

	*path = _strdup([filePath fileSystemRepresentation]);
	return *path != nullptr;
}

int mac_cliprdr_send_client_format_list(CliprdrClientContext *cliprdr)
{
	UINT32 formatId;
	UINT32 numFormats;
	UINT32 *pFormatIds;
	const char *formatName;
	CLIPRDR_FORMAT *formats;
	CLIPRDR_FORMAT_LIST formatList = WINPR_C_ARRAY_INIT;

	WINPR_ASSERT(cliprdr);
	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	pFormatIds = nullptr;
	numFormats = ClipboardGetFormatIds(mfc->clipboard, &pFormatIds);

	formats = (CLIPRDR_FORMAT *)calloc(numFormats, sizeof(CLIPRDR_FORMAT));

	if (!formats)
		return -1;

	for (UINT32 index = 0; index < numFormats; index++)
	{
		formatId = pFormatIds[index];
		formatName = ClipboardGetFormatName(mfc->clipboard, formatId);

		formats[index].formatId = formatId;
		formats[index].formatName = nullptr;

		if ((formatId > CF_MAX) && formatName)
			formats[index].formatName = _strdup(formatName);
	}

	formatList.common.msgFlags = 0;
	formatList.numFormats = numFormats;
	formatList.formats = formats;
	formatList.common.msgType = CB_FORMAT_LIST;

	mfc->cliprdr->ClientFormatList(mfc->cliprdr, &formatList);

	for (UINT32 index = 0; index < numFormats; index++)
	{
		free(formats[index].formatName);
	}

	free(pFormatIds);
	free(formats);

	return 1;
}

static int mac_cliprdr_send_client_format_list_response(CliprdrClientContext *cliprdr, BOOL status)
{
	CLIPRDR_FORMAT_LIST_RESPONSE formatListResponse;

	formatListResponse.common.msgType = CB_FORMAT_LIST_RESPONSE;
	formatListResponse.common.msgFlags = status ? CB_RESPONSE_OK : CB_RESPONSE_FAIL;
	formatListResponse.common.dataLen = 0;

	cliprdr->ClientFormatListResponse(cliprdr, &formatListResponse);

	return 1;
}

static UINT mac_cliprdr_send_client_format_data_request(CliprdrClientContext *cliprdr,
                                                        UINT32 formatId)
{
	CLIPRDR_FORMAT_DATA_REQUEST formatDataRequest = WINPR_C_ARRAY_INIT;
	WINPR_ASSERT(cliprdr);

	if (formatId == 0)
		return CHANNEL_RC_OK;

	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	formatDataRequest.common.msgType = CB_FORMAT_DATA_REQUEST;
	formatDataRequest.common.msgFlags = 0;

	formatDataRequest.requestedFormatId = formatId;
	mfc->requestedFormatId = formatId;
	(void)ResetEvent(mfc->clipboardRequestEvent);

	return cliprdr->ClientFormatDataRequest(cliprdr, &formatDataRequest);
}

static int mac_cliprdr_send_client_capabilities(CliprdrClientContext *cliprdr)
{
	CLIPRDR_CAPABILITIES capabilities;
	CLIPRDR_GENERAL_CAPABILITY_SET generalCapabilitySet;

	capabilities.cCapabilitiesSets = 1;
	capabilities.capabilitySets = (CLIPRDR_CAPABILITY_SET *)&(generalCapabilitySet);

	generalCapabilitySet.capabilitySetType = CB_CAPSTYPE_GENERAL;
	generalCapabilitySet.capabilitySetLength = 12;

	generalCapabilitySet.version = CB_CAPS_VERSION_2;
	generalCapabilitySet.generalFlags = CB_USE_LONG_FORMAT_NAMES | CB_STREAM_FILECLIP_ENABLED |
	                                    CB_FILECLIP_NO_FILE_PATHS |
	                                    CB_HUGE_FILE_SUPPORT_ENABLED;

	cliprdr->ClientCapabilities(cliprdr, &capabilities);

	return 1;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT mac_cliprdr_monitor_ready(CliprdrClientContext *cliprdr,
                                      const CLIPRDR_MONITOR_READY *monitorReady)
{
	mfContext *mfc = (mfContext *)cliprdr->custom;

	mfc->clipboardSync = TRUE;
	mac_cliprdr_send_client_capabilities(cliprdr);
	mac_cliprdr_send_client_format_list(cliprdr);

	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT mac_cliprdr_server_capabilities(CliprdrClientContext *cliprdr,
                                            const CLIPRDR_CAPABILITIES *capabilities)
{
	CLIPRDR_CAPABILITY_SET *capabilitySet;
	mfContext *mfc = (mfContext *)cliprdr->custom;

	for (UINT32 index = 0; index < capabilities->cCapabilitiesSets; index++)
	{
		capabilitySet = &(capabilities->capabilitySets[index]);

		if ((capabilitySet->capabilitySetType == CB_CAPSTYPE_GENERAL) &&
		    (capabilitySet->capabilitySetLength >= CB_CAPSTYPE_GENERAL_LEN))
		{
			CLIPRDR_GENERAL_CAPABILITY_SET *generalCapabilitySet =
			    (CLIPRDR_GENERAL_CAPABILITY_SET *)capabilitySet;

			mfc->clipboardCapabilities = generalCapabilitySet->generalFlags;
			break;
		}
	}

	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT mac_cliprdr_server_format_list(CliprdrClientContext *cliprdr,
                                           const CLIPRDR_FORMAT_LIST *formatList)
{
	WINPR_ASSERT(cliprdr);

	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	if (mfc->serverFormats)
	{
		for (UINT32 index = 0; index < mfc->numServerFormats; index++)
		{
			free(mfc->serverFormats[index].formatName);
		}

		free(mfc->serverFormats);
		mfc->serverFormats = nullptr;
		mfc->numServerFormats = 0;
	}

	if (formatList->numFormats < 1)
		return CHANNEL_RC_OK;

	mfc->numServerFormats = formatList->numFormats;
	mfc->serverFormats = (CLIPRDR_FORMAT *)calloc(mfc->numServerFormats, sizeof(CLIPRDR_FORMAT));

	if (!mfc->serverFormats)
		return CHANNEL_RC_NO_MEMORY;

	for (UINT32 index = 0; index < mfc->numServerFormats; index++)
	{
		mfc->serverFormats[index].formatId = formatList->formats[index].formatId;
		mfc->serverFormats[index].formatName = nullptr;

		if (formatList->formats[index].formatName)
			mfc->serverFormats[index].formatName = _strdup(formatList->formats[index].formatName);
	}

	mac_cliprdr_send_client_format_list_response(cliprdr, TRUE);

	uint32_t fileFormatId = 0;
	uint32_t textFormatId = 0;
	for (UINT32 index = 0; index < mfc->numServerFormats; index++)
	{
		const CLIPRDR_FORMAT *format = &(mfc->serverFormats[index]);

		if (format->formatName && (strcmp(format->formatName, type_FileGroupDescriptorW) == 0))
			fileFormatId = format->formatId;
		if (format->formatId == CF_UNICODETEXT)
			textFormatId = format->formatId;
		else if (format->formatId == CF_OEMTEXT)
		{
			if (textFormatId == 0)
				textFormatId = CF_OEMTEXT;
		}
		else if (format->formatId == CF_TEXT)
		{
			if (textFormatId == 0)
				textFormatId = CF_TEXT;
		}
	}

	if (fileFormatId != 0)
		return mac_cliprdr_send_client_format_data_request(cliprdr, fileFormatId);

	return mac_cliprdr_send_client_format_data_request(cliprdr, textFormatId);
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_format_list_response(CliprdrClientContext *cliprdr,
                                        const CLIPRDR_FORMAT_LIST_RESPONSE *formatListResponse)
{
	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_lock_clipboard_data(CliprdrClientContext *cliprdr,
                                       const CLIPRDR_LOCK_CLIPBOARD_DATA *lockClipboardData)
{
	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_unlock_clipboard_data(CliprdrClientContext *cliprdr,
                                         const CLIPRDR_UNLOCK_CLIPBOARD_DATA *unlockClipboardData)
{
	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_format_data_request(CliprdrClientContext *cliprdr,
                                       const CLIPRDR_FORMAT_DATA_REQUEST *formatDataRequest)
{
	BYTE *data;
	UINT32 size;
	UINT32 formatId;
	CLIPRDR_FORMAT_DATA_RESPONSE response = WINPR_C_ARRAY_INIT;

	WINPR_ASSERT(cliprdr);

	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	formatId = formatDataRequest->requestedFormatId;
	data = (BYTE *)ClipboardGetData(mfc->clipboard, formatId, &size);

	response.common.msgFlags = CB_RESPONSE_OK;
	response.common.dataLen = size;
	response.requestedFormatData = data;

	if (!data)
	{
		response.common.msgFlags = CB_RESPONSE_FAIL;
		response.common.dataLen = 0;
		response.requestedFormatData = nullptr;
	}

	cliprdr->ClientFormatDataResponse(cliprdr, &response);

	free(data);

	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_format_data_response(CliprdrClientContext *cliprdr,
                                        const CLIPRDR_FORMAT_DATA_RESPONSE *formatDataResponse)
{
	UINT32 formatId;
	CLIPRDR_FORMAT *format = nullptr;
	mfContext *mfc = (mfContext *)cliprdr->custom;
	MRDPView *view = (MRDPView *)mfc->view;

	if (formatDataResponse->common.msgFlags & CB_RESPONSE_FAIL)
	{
		(void)SetEvent(mfc->clipboardRequestEvent);
		return CHANNEL_RC_OK;
	}

	for (UINT32 index = 0; index < mfc->numServerFormats; index++)
	{
		if (mfc->requestedFormatId == mfc->serverFormats[index].formatId)
			format = &(mfc->serverFormats[index]);
	}

	if (!format)
	{
		(void)SetEvent(mfc->clipboardRequestEvent);
		return CHANNEL_RC_OK;
	}

	if (format->formatName && (strcmp(format->formatName, type_FileGroupDescriptorW) == 0))
	{
		(void)SetEvent(mfc->clipboardRequestEvent);
		return mac_cliprdr_handle_remote_file_list(mfc, formatDataResponse);
	}

	if (format->formatName)
		formatId = ClipboardRegisterFormat(mfc->clipboard, format->formatName);
	else
		formatId = format->formatId;

	const size_t size = formatDataResponse->common.dataLen;

	ClipboardSetData(mfc->clipboard, formatId, formatDataResponse->requestedFormatData, size);

	(void)SetEvent(mfc->clipboardRequestEvent);

	if ((formatId == CF_TEXT) || (formatId == CF_OEMTEXT) || (formatId == CF_UNICODETEXT))
	{
		formatId = ClipboardRegisterFormat(mfc->clipboard, "text/plain");

		UINT32 dstSize = 0;
		char *data = ClipboardGetData(mfc->clipboard, formatId, &dstSize);

		if (!data)
			return CHANNEL_RC_OK;

		dstSize = strnlen(data, dstSize); /* we need the size without the null terminator */

		NSString *str = [[NSString alloc] initWithBytes:(void *)data
		                                         length:dstSize
		                                       encoding:NSUTF8StringEncoding];
		free(data);

		if (!str)
			return CHANNEL_RC_OK;

		NSArray *types = [[NSArray alloc] initWithObjects:NSPasteboardTypeString, nil];
		[view->pasteboard_wr declareTypes:types owner:view];
		[view->pasteboard_wr setString:str forType:NSPasteboardTypeString];
		[str release];
		[types release];
	}

	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT
mac_cliprdr_server_file_contents_request(CliprdrClientContext *cliprdr,
                                         const CLIPRDR_FILE_CONTENTS_REQUEST *fileContentsRequest)
{
	WINPR_ASSERT(cliprdr);
	WINPR_ASSERT(fileContentsRequest);

	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	wClipboardDelegate *delegate = ClipboardGetDelegate(mfc->clipboard);
	if (!delegate)
		return CHANNEL_RC_OK;

	UINT rc = CHANNEL_RC_OK;

	if (fileContentsRequest->dwFlags & FILECONTENTS_SIZE)
	{
		wClipboardFileSizeRequest request = { 0 };
		request.streamId = fileContentsRequest->streamId;
		request.listIndex = fileContentsRequest->listIndex;
		rc = delegate->ClientRequestFileSize(delegate, &request);
	}
	else if (fileContentsRequest->dwFlags & FILECONTENTS_RANGE)
	{
		wClipboardFileRangeRequest request = { 0 };
		request.streamId = fileContentsRequest->streamId;
		request.listIndex = fileContentsRequest->listIndex;
		request.nPositionLow = fileContentsRequest->nPositionLow;
		request.nPositionHigh = fileContentsRequest->nPositionHigh;
		request.cbRequested = fileContentsRequest->cbRequested;
		rc = delegate->ClientRequestFileRange(delegate, &request);
	}
	else
	{
		rc = ERROR_INVALID_PARAMETER;
	}

	if (rc != CHANNEL_RC_OK)
		return mac_cliprdr_send_file_contents_failure(delegate, fileContentsRequest->streamId);

	return CHANNEL_RC_OK;
}

/**
 * Function description
 *
 * @return 0 on success, otherwise a Win32 error code
 */
static UINT mac_cliprdr_server_file_contents_response(
    CliprdrClientContext *cliprdr, const CLIPRDR_FILE_CONTENTS_RESPONSE *fileContentsResponse)
{
	WINPR_ASSERT(cliprdr);
	WINPR_ASSERT(fileContentsResponse);

	mfContext *mfc = (mfContext *)cliprdr->custom;
	WINPR_ASSERT(mfc);

	if (fileContentsResponse->common.msgFlags & CB_RESPONSE_FAIL)
		return CHANNEL_RC_OK;

	for (UINT32 index = 0; index < mfc->remoteFileCount; index++)
	{
		mfClipboardRemoteFile *file = &mfc->remoteFiles[index];

		if (file->complete || (file->streamId != fileContentsResponse->streamId) || !file->localPath)
			continue;

		FILE *fp = winpr_fopen(file->localPath, "ab");
		if (!fp)
			return CHANNEL_RC_OK;

		if (fileContentsResponse->cbRequested > 0)
			fwrite(fileContentsResponse->requestedData, 1, fileContentsResponse->cbRequested, fp);

		fclose(fp);

		file->received += fileContentsResponse->cbRequested;
		if (file->received >= file->size)
		{
			file->complete = TRUE;
			return mac_cliprdr_request_next_remote_file(mfc);
		}

		return mac_cliprdr_request_remote_file_range(mfc, file);
	}

	return CHANNEL_RC_OK;
}

static UINT mac_cliprdr_send_file_contents_response(wClipboardDelegate *delegate, UINT32 streamId,
                                                    UINT16 flags, const BYTE *data, UINT32 size)
{
	if (!delegate || !delegate->custom)
		return ERROR_BAD_ARGUMENTS;

	mfContext *mfc = (mfContext *)delegate->custom;
	if (!mfc->cliprdr)
		return ERROR_INVALID_STATE;

	CLIPRDR_FILE_CONTENTS_RESPONSE response = WINPR_C_ARRAY_INIT;
	response.common.msgType = CB_FILECONTENTS_RESPONSE;
	response.common.msgFlags = flags;
	response.common.dataLen = sizeof(UINT32) + size;
	response.streamId = streamId;
	response.cbRequested = size;
	response.requestedData = data;
	return mfc->cliprdr->ClientFileContentsResponse(mfc->cliprdr, &response);
}

static UINT mac_cliprdr_send_file_contents_failure(wClipboardDelegate *delegate, UINT32 streamId)
{
	return mac_cliprdr_send_file_contents_response(delegate, streamId, CB_RESPONSE_FAIL, nullptr, 0);
}

static UINT mac_cliprdr_file_size_success(wClipboardDelegate *delegate,
                                          const wClipboardFileSizeRequest *request, UINT64 fileSize)
{
	BYTE data[sizeof(UINT64)] = { 0 };
	Data_Write_UINT64(data, fileSize);
	return mac_cliprdr_send_file_contents_response(delegate, request->streamId, CB_RESPONSE_OK, data,
	                                               sizeof(data));
}

static UINT mac_cliprdr_file_size_failure(wClipboardDelegate *delegate,
                                          const wClipboardFileSizeRequest *request,
                                          UINT errorCode)
{
	return mac_cliprdr_send_file_contents_failure(delegate, request->streamId);
}

static UINT mac_cliprdr_file_range_success(wClipboardDelegate *delegate,
                                           const wClipboardFileRangeRequest *request,
                                           const BYTE *data, UINT32 size)
{
	return mac_cliprdr_send_file_contents_response(delegate, request->streamId, CB_RESPONSE_OK, data,
	                                               size);
}

static UINT mac_cliprdr_file_range_failure(wClipboardDelegate *delegate,
                                           const wClipboardFileRangeRequest *request,
                                           UINT errorCode)
{
	return mac_cliprdr_send_file_contents_failure(delegate, request->streamId);
}

void mac_cliprdr_init(mfContext *mfc, CliprdrClientContext *cliprdr)
{
	cliprdr->custom = (void *)mfc;
	mfc->cliprdr = cliprdr;
	mfc->remoteFileStreamIdNext = 1;

	mfc->clipboard = ClipboardCreate();
	mfc->clipboardRequestEvent = CreateEvent(nullptr, TRUE, FALSE, nullptr);
	wClipboardDelegate *delegate = ClipboardGetDelegate(mfc->clipboard);
	if (delegate)
	{
		delegate->custom = mfc;
		delegate->ClipboardFileSizeSuccess = mac_cliprdr_file_size_success;
		delegate->ClipboardFileSizeFailure = mac_cliprdr_file_size_failure;
		delegate->ClipboardFileRangeSuccess = mac_cliprdr_file_range_success;
		delegate->ClipboardFileRangeFailure = mac_cliprdr_file_range_failure;
	}

	cliprdr->MonitorReady = mac_cliprdr_monitor_ready;
	cliprdr->ServerCapabilities = mac_cliprdr_server_capabilities;
	cliprdr->ServerFormatList = mac_cliprdr_server_format_list;
	cliprdr->ServerFormatListResponse = mac_cliprdr_server_format_list_response;
	cliprdr->ServerLockClipboardData = mac_cliprdr_server_lock_clipboard_data;
	cliprdr->ServerUnlockClipboardData = mac_cliprdr_server_unlock_clipboard_data;
	cliprdr->ServerFormatDataRequest = mac_cliprdr_server_format_data_request;
	cliprdr->ServerFormatDataResponse = mac_cliprdr_server_format_data_response;
	cliprdr->ServerFileContentsRequest = mac_cliprdr_server_file_contents_request;
	cliprdr->ServerFileContentsResponse = mac_cliprdr_server_file_contents_response;
}

void mac_cliprdr_uninit(mfContext *mfc, CliprdrClientContext *cliprdr)
{
	cliprdr->custom = nullptr;
	mfc->cliprdr = nullptr;
	mac_cliprdr_clear_remote_files(mfc);

	ClipboardDestroy(mfc->clipboard);
	(void)CloseHandle(mfc->clipboardRequestEvent);
}
