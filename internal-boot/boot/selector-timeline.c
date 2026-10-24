/* GPL-2.0-only. This diagnostic reads PCI identity and BAR0 only.
 * The 1 MiB PROM read uses the same Mem.Read width/chunks as full-release.c.
 * It never invokes a driver detach, PCI Attributes, device write, or child EFI.
 */
#include "selector-timeline.h"
#include "../unlock/machine-profile.h"
#include "../unlock/sha256.h"
#include <Protocol/PciIo.h>

#if !defined(GU_SELECTOR_TIMELINE) || !defined(GU_DIAGNOSTIC_ONLY) || defined(GU_FULL_UNLOCK) || !defined(GU_PROFILE_Z690_3060TI)
#error Selector timeline must be a separate read-only Z690 diagnostic image
#endif

typedef struct {
  EFI_STATUS Ss0Status,Ss1Status;
  UINT32 Ss0,Ss1;
} SAMPLE;
typedef struct {char Bytes[192];UINTN Used;BOOLEAN Overflow;} LINE;
static EFI_GUID PciGuid=EFI_PCI_IO_PROTOCOL_GUID;
static EFI_PCI_IO_PROTOCOL *Target;
static EFI_SYSTEM_TABLE *System;

static VOID Append(LINE *l,const char *s) {
  while(*s) {
    if(l->Used>=sizeof(l->Bytes)){l->Overflow=TRUE;return;}
    l->Bytes[l->Used++]=*s++;
  }
}
static VOID Hex(LINE *l,UINT64 value,UINTN digits) {
  for(UINTN i=0;i<digits;i++) {
    if(l->Used>=sizeof(l->Bytes)){l->Overflow=TRUE;return;}
    l->Bytes[l->Used++]="0123456789abcdef"[(value>>((digits-i-1)*4))&15];
  }
}
static EFI_STATUS Emit(EFI_FILE_PROTOCOL *log,LINE *l) {
  if(!log || !log->Write || !log->Flush || l->Overflow)return EFI_BAD_BUFFER_SIZE;
  Append(l,"\r\n");
  if(l->Overflow)return EFI_BAD_BUFFER_SIZE;
  UINTN n=l->Used;
  EFI_STATUS s=log->Write(log,&n,l->Bytes);
  if(s!=EFI_SUCCESS)return s;
  if(n!=l->Used)return EFI_DEVICE_ERROR;
  return log->Flush(log);
}
static SAMPLE ReadSelectors(VOID) {
  SAMPLE v={EFI_NOT_READY,EFI_NOT_READY,0xdeadbeefU,0xdeadbeefU};
  if(!Target || !Target->Mem.Read)return v;
  v.Ss0Status=Target->Mem.Read(Target,EfiPciIoWidthUint32,0,0x82381c,1,&v.Ss0);
  v.Ss1Status=Target->Mem.Read(Target,EfiPciIoWidthUint32,0,0x823820,1,&v.Ss1);
  return v;
}
static EFI_STATUS LogSample(EFI_FILE_PROTOCOL *log,const char *phase,const SAMPLE *v) {
  LINE l={0};
  Append(&l,"selector-timeline phase=");Append(&l,phase);
  Append(&l," ss0-status=0x");Hex(&l,v->Ss0Status,16);
  Append(&l," ss0=0x");Hex(&l,v->Ss0,8);
  Append(&l," ss1-status=0x");Hex(&l,v->Ss1Status,16);
  Append(&l," ss1=0x");Hex(&l,v->Ss1,8);
  EFI_STATUS s=Emit(log,&l);
  if(s!=EFI_SUCCESS)return s;
  return v->Ss0Status!=EFI_SUCCESS?v->Ss0Status:v->Ss1Status;
}
static EFI_STATUS FindTarget(EFI_SYSTEM_TABLE *t) {
  if(!t || !t->BootServices || !t->BootServices->LocateHandleBuffer || !t->BootServices->FreePool)return EFI_INVALID_PARAMETER;
  EFI_HANDLE *handles=NULL;UINTN count=0,matches=0;
  EFI_STATUS s=t->BootServices->LocateHandleBuffer(ByProtocol,&PciGuid,NULL,&count,&handles);
  if(s!=EFI_SUCCESS || !handles || count>4096) {
    if(handles)t->BootServices->FreePool(handles);
    return s==EFI_SUCCESS?EFI_BAD_BUFFER_SIZE:s;
  }
  for(UINTN i=0;i<count;i++) {
    EFI_PCI_IO_PROTOCOL *io=NULL;
    UINTN segment=0,bus=0,device=0,function=0;
    s=t->BootServices->HandleProtocol(handles[i],&PciGuid,(VOID **)&io);
    if(s!=EFI_SUCCESS || !io || !io->GetLocation || !io->Pci.Read || !io->Mem.Read)continue;
    s=io->GetLocation(io,&segment,&bus,&device,&function);
    if(s!=EFI_SUCCESS || segment || bus!=1 || device || function)continue;
    UINT32 cfg[12]={0};
    s=io->Pci.Read(io,EfiPciIoWidthUint32,0,12,cfg);
    if(s!=EFI_SUCCESS || cfg[0]!=GU_BOARD_ID || cfg[11]!=GU_BOARD_SUBSYSTEM ||
       cfg[2]!=0x030000a1U || cfg[4]!=(UINT32)GU_BAR0_BASE ||
       !(cfg[1]&2U) || (cfg[1]&4U))continue;
    matches++;Target=io;
  }
  EFI_STATUS freed=t->BootServices->FreePool(handles);
  if(freed!=EFI_SUCCESS)return freed;
  return matches==1?EFI_SUCCESS:matches?EFI_COMPROMISED_DATA:EFI_NOT_FOUND;
}
EFI_STATUS GuSelectorTimelineBegin(EFI_SYSTEM_TABLE *t,EFI_FILE_PROTOCOL *log) {
  Target=NULL;System=NULL;
  EFI_STATUS s=FindTarget(t);
  if(s!=EFI_SUCCESS)return s;
  System=t;
  /* Sample before any timeline file write or full graph traversal. */
  SAMPLE early=ReadSelectors();
  LINE l={0};Append(&l,"selector-timeline exact-target=10de:2489 subsystem=1043:8827 bar0=0x");
  Hex(&l,GU_BAR0_BASE,8);
  s=Emit(log,&l);if(s!=EFI_SUCCESS)return s;
  return LogSample(log,"early",&early);
}
EFI_STATUS GuSelectorTimelineWait(EFI_SYSTEM_TABLE *t,EFI_FILE_PROTOCOL *log) {
  if(!Target || !System || t!=System || !t->BootServices || !t->BootServices->Stall)return EFI_NOT_READY;
  EFI_STATUS s=t->BootServices->Stall(5000000);
  if(s!=EFI_SUCCESS)return s;
  return GuSelectorTimelineSample(log,"after-5s");
}
EFI_STATUS GuSelectorTimelineSample(EFI_FILE_PROTOCOL *log,const char *phase) {
  if(!Target || !phase)return EFI_NOT_READY;
  SAMPLE v=ReadSelectors();
  return LogSample(log,phase,&v);
}
EFI_STATUS GuSelectorTimelineProm(EFI_SYSTEM_TABLE *t,EFI_FILE_PROTOCOL *log) {
  if(!Target || !System || t!=System || !t->BootServices || !t->BootServices->AllocatePool || !t->BootServices->FreePool)return EFI_NOT_READY;
  UINT8 *data=NULL;
  EFI_STATUS s=t->BootServices->AllocatePool(EfiBootServicesData,0x100000,(VOID **)&data);
  if(s!=EFI_SUCCESS || !data)return s==EFI_SUCCESS?EFI_OUT_OF_RESOURCES:s;
  /* No file or console callback between these two selector samples. */
  SAMPLE before=ReadSelectors();
  EFI_STATUS prom=before.Ss0Status!=EFI_SUCCESS?before.Ss0Status:before.Ss1Status;
  if(prom==EFI_SUCCESS)for(UINTN off=0;off<0x100000 && prom==EFI_SUCCESS;off+=65536)
    prom=Target->Mem.Read(Target,EfiPciIoWidthUint8,0,0x300000+off,65536,data+off);
  SAMPLE after=ReadSelectors();
  UINT8 digest[32]={0};
  if(prom==EFI_SUCCESS)GuSha256(data,0x100000,digest);
  EFI_STATUS freed=t->BootServices->FreePool(data);
  EFI_STATUS logged=LogSample(log,"pre-prom",&before);
  if(logged!=EFI_SUCCESS)return logged;
  LINE l={0};Append(&l,"selector-timeline prom-read-status=0x");Hex(&l,prom,16);
  if(prom==EFI_SUCCESS) {
    Append(&l," sha256=");
    for(UINTN i=0;i<32;i++)Hex(&l,digest[i],2);
  }
  logged=Emit(log,&l);if(logged!=EFI_SUCCESS)return logged;
  logged=LogSample(log,"post-prom",&after);if(logged!=EFI_SUCCESS)return logged;
  if(prom!=EFI_SUCCESS)return prom;
  return freed;
}
