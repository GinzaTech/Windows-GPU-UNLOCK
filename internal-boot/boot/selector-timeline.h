/* GPL-2.0-only. Read-only selector timeline for the exact Z690/RTX3060Ti. */
#pragma once
#include <Uefi.h>
#include <Protocol/SimpleFileSystem.h>

EFI_STATUS GuSelectorTimelineBegin(EFI_SYSTEM_TABLE *Table,EFI_FILE_PROTOCOL *Log);
EFI_STATUS GuSelectorTimelineWait(EFI_SYSTEM_TABLE *Table,EFI_FILE_PROTOCOL *Log);
EFI_STATUS GuSelectorTimelineSample(EFI_FILE_PROTOCOL *Log,const char *Phase);
EFI_STATUS GuSelectorTimelineProm(EFI_SYSTEM_TABLE *Table,EFI_FILE_PROTOCOL *Log);
