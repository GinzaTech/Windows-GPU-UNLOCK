/* GPL-2.0-only. Probe interface; CAPTURE layout must match diagnostic.c. */
#pragma once
#include <Uefi.h>
#include <Protocol/SimpleFileSystem.h>
typedef struct CAPTURE_S {
  EFI_SYSTEM_TABLE *Table;
  EFI_FILE_PROTOCOL *File;
  EFI_STATUS Io;
  BOOLEAN Complete;
  UINTN Used,Total;
  char Buffer[4096];
} CAPTURE;
EFI_STATUS GuProbeGpu(EFI_SYSTEM_TABLE *t,CAPTURE *c);
VOID GuProbeSetOutput(EFI_FILE_PROTOCOL *Root,UINTN Run);

