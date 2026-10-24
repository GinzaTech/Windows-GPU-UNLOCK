/* Exercise the production ColdCheck with the two captured Z690 selectors. */
#include "test_3090_experimental.c"
#undef main
#ifndef GU_PROFILE_Z690_3060TI
#error This test requires the exact Z690 RTX3060Ti profile.
#endif
#ifndef GU_ENTRY_LATCHED_SS1_FULL
#error This test requires the full entry-latched write policy.
#endif

static void z690_cold_setup(UINT32 ss0,UINT32 ss1,BOOLEAN prom_verified) {
  /* The shared mock initializes a 3090 transaction. Replace only its cold
     register inputs; no firmware asset or GPU write is used by ColdCheck. */
  test_entry_ss0=GU_PROFILE_COLD_SS0;test_entry_ss1=GU_PROFILE_COLD_SS1;
  app_setup(APP_SUCCESS);
  registers[0]=GU_CHIP_ID;registers[0x1183a4/4]=GU_DEVICE_MEMORY_SIZE;
  registers[SS0/4]=ss0;registers[SS1/4]=ss1;
  GuInit(&bs,&pci);Gu.bar_base=GU_BAR0_BASE;Gu.bar_size=sizeof(registers);
  Gu.display_ok=TRUE;Table=&st;CHECK(!EFI_ERROR(GuIoOpen(H(1),&st)));
  Gu.prom_verified=prom_verified;
}
static void z690_cold_cleanup(void) {
  CHECK(!fake.mmio_writes && !fake.pci_writes && !fake.maps && !fake.flrs);
  CHECK(!EFI_ERROR(GuIoClose()));dispose_host_fixture();
}
int main(void) {
  UINT32 latched0=0,latched1=0;
  CHECK(GU_PROFILE_COLD_SS0==0x54372112U &&
        GU_PROFILE_COLD_SS0_ALTERNATE==0x54372012U && GU_PROFILE_COLD_SS1==4U);
  CHECK(GU_PROFILE_COLD_SS0_ALLOWED(GU_PROFILE_COLD_SS0) &&
        GU_PROFILE_COLD_SS0_ALLOWED(GU_PROFILE_COLD_SS0_ALTERNATE) &&
        !GU_PROFILE_COLD_SS0_ALLOWED(0x04500056U));
  z690_cold_setup(GU_PROFILE_COLD_SS0,GU_PROFILE_COLD_SS1,FALSE);
  CHECK(EFI_ERROR(ColdCheck()) && !Gu.profile_verified);
  CHECK(!GuGetEntrySelectors(&latched0,&latched1));z690_cold_cleanup();

  const UINT32 wrong[][2]={{GU_PROFILE_COLD_SS0^1U,GU_PROFILE_COLD_SS1},
                           {GU_PROFILE_COLD_SS0_ALTERNATE^1U,GU_PROFILE_COLD_SS1},
                           {0x04500056U,GU_PROFILE_COLD_SS1},
                           {GU_PROFILE_COLD_SS0,GU_PROFILE_COLD_SS1^1U},
                           {0x03000062U,6U}};
  for(UINTN i=0;i<sizeof(wrong)/sizeof(wrong[0]);i++) {
    z690_cold_setup(wrong[i][0],wrong[i][1],TRUE);
    /* A generic latch alone is insufficient: ColdCheck must reject the
       otherwise well-formed but unmeasured pair before authorization. */
    CHECK(ColdCheck()==EFI_NOT_READY && !Gu.profile_verified);
    CHECK(!GuGetEntrySelectors(&latched0,&latched1));
    CHECK(GuLatchEntrySelectors(wrong[i][0],wrong[i][1]));
    CHECK(!Gu.profile_verified);z690_cold_cleanup();
  }

  const UINT32 approved[]={GU_PROFILE_COLD_SS0,GU_PROFILE_COLD_SS0_ALTERNATE};
  for(UINTN i=0;i<sizeof(approved)/sizeof(approved[0]);i++) {
    z690_cold_setup(approved[i],GU_PROFILE_COLD_SS1,TRUE);
    CHECK(!EFI_ERROR(ColdCheck()) && Gu.profile_verified);
    CHECK(GuGetEntrySelectors(&latched0,&latched1) &&
          latched0==approved[i] && latched1==GU_PROFILE_COLD_SS1);
    /* Even the other approved value may not replace this run's live latch. */
    registers[SS0/4]=approved[1-i];
    CHECK(ColdCheck()==EFI_NOT_READY && !Gu.profile_verified);
    CHECK(GuGetEntrySelectors(&latched0,&latched1) &&
          latched0==approved[i] && latched1==GU_PROFILE_COLD_SS1);
    z690_cold_cleanup();

    z690_cold_setup(approved[i],GU_PROFILE_COLD_SS1,TRUE);
    CHECK(!EFI_ERROR(ColdCheck()) && Gu.profile_verified);
    registers[SS1/4]^=1U;
    CHECK(ColdCheck()==EFI_NOT_READY && !Gu.profile_verified);
    z690_cold_cleanup();
  }
  puts("PASS two observed Z690 cold pairs accepted; unobserved values, changed live latch, missing PROM and changed SS1 rejected before effects");
  return 0;
}
