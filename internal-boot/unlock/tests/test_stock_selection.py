"""Reject ambiguous production build selection before creating artifacts."""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
CLANG = sys.argv[1]
BASE = [CLANG, '-std=c11', '-fsyntax-only', '-x', 'c', '-',
        '-I../../deps/edk2/MdePkg/Include',
        '-I../../deps/edk2/MdePkg/Include/X64']
EXP = '-DGU_EXPERIMENTAL_3090'
ORIGINAL = '-DGU_STOCK_PROFILE_ORIGINAL_03100062'
OBSERVED = '-DGU_STOCK_PROFILE_OBSERVED_03000062'
LATCHED = '-DGU_ENTRY_LATCHED_SS1_PRESERVE'
FULL = '-DGU_ENTRY_LATCHED_SS1_FULL'
Z690 = '-DGU_PROFILE_Z690_3060TI'
B660 = '-DGU_PROFILE_B660M_3070TI'
B650 = '-DGU_PROFILE_B650M_3090FE'
CASES = [([], True), ([EXP, ORIGINAL], True), ([EXP, OBSERVED], True),
         ([EXP, LATCHED], True), ([LATCHED], False),
         ([EXP, FULL], True), ([FULL], False),
         ([EXP, LATCHED, FULL], False),
         ([EXP, LATCHED, ORIGINAL], False), ([EXP, LATCHED, OBSERVED], False),
         ([EXP, LATCHED, ORIGINAL, OBSERVED], False),
         ([EXP], False), ([EXP, ORIGINAL, OBSERVED], False),
         ([ORIGINAL], False), ([OBSERVED], False),
         ([EXP, '-DGU_STOCK_PROFILE_UNKNOWN'], False),
         ([EXP, ORIGINAL, '-DGU_STOCK_PROFILE_SS0=0x03000062U'], False),
         ([EXP, OBSERVED, '-DGU_STOCK_PROFILE_NAME="original03100062"'], False),
         (['-ffreestanding', '-DGU_HOST_WRITE_TEST'], False),
         ([Z690, EXP, FULL], True), ([Z690, B660, EXP, FULL], False),
         ([Z690, B650, EXP, FULL], False)]
for defines, expected in CASES:
    result = subprocess.run(BASE + defines, cwd=ROOT, input='#include "port.h"\n',
                            text=True, capture_output=True)
    assert (result.returncode == 0) == expected, (defines, result.stderr)

profile = subprocess.run([CLANG, '-std=c11', '-dM', '-E', '-x', 'c', '-'] +
                         BASE[-2:] + [Z690, EXP, FULL], cwd=ROOT,
                         input='#include "port.h"\n', text=True,
                         capture_output=True)
assert profile.returncode == 0, profile.stderr
defines = profile.stdout
for value in ('#define GU_BOARD_ID 0x248910deU',
              '#define GU_BOARD_SUBSYSTEM 0x88271043U',
              '#define GU_BAR0_BASE 0x84000000ULL',
              '#define GU_BAR0_END 0x84ffffffULL',
              '#define GU_CHIP_ID 0xb74000a1U',
              '#define GU_DEVICE_MEMORY_SIZE 0x2000U',
              '#define GU_PROFILE_COLD_SS0 0x54372112U',
              '#define GU_PROFILE_COLD_SS0_ALTERNATE 0x54372012U',
              '#define GU_PROFILE_COLD_SS0_ALLOWED(value)',
              '#define GU_PROFILE_COLD_SS1 0x4U',
              '#define GU_CONSOLE_AGGREGATE 1',
              '#define GU_CONSOLE_MULTI_CHILD 1',
              '#define GU_STOCK_PROFILE_NAME "entryLatchedSs1Full"'):
    assert value in defines, value
for old_profile in (B650, B660):
    previous = subprocess.run(
        [CLANG, '-std=c11', '-dM', '-E', '-x', 'c', '-'] + BASE[-2:] +
        [old_profile, EXP, FULL], cwd=ROOT, input='#include "port.h"\n',
        text=True, capture_output=True)
    assert previous.returncode == 0, previous.stderr
    assert '#define GU_CONSOLE_MULTI_CHILD 0' in previous.stdout
    assert 'GU_PROFILE_COLD_SS0' not in previous.stdout
    assert 'GU_PROFILE_COLD_SS0_ALTERNATE' not in previous.stdout
    assert 'GU_PROFILE_COLD_SS0_ALLOWED' not in previous.stdout
    assert 'GU_PROFILE_COLD_SS1' not in previous.stdout

parameter_rejections = 0
for script in ('build.ps1', 'test-all.ps1'):
    for args in (['-ExperimentalUnlock'],
                 ['-ExperimentalUnlock', '-StockProfile', 'unknown'],
                 ['-StockProfile', 'original03100062'],
                  ['-StockProfile', 'observed03000062'],
                  ['-StockProfile', 'entryLatchedSs1Preserve'],
                  ['-StockProfile', 'entryLatchedSs1Full'],
                 ['-ExperimentalUnlock', '-StockProfile', '']):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy',
                                 'Bypass', '-File', str(ROOT / script)] + args,
                                cwd=ROOT, text=True, capture_output=True)
        assert result.returncode != 0, (script, args, result.stdout, result.stderr)
        parameter_rejections += 1
print(f'PASS {len(CASES)} compile-time selector cases + {parameter_rejections} build/test parameter rejections')
