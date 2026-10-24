# Cài bản thử nghiệm RTX 3060 Ti trên Windows

[English](WINDOWS-RTX3060TI.en.md) · [Báo cáo hiệu năng](WINDOWS-RTX3060TI-RESULTS.vi.md)

## Phạm vi đã kiểm chứng

Bản Windows này đã chạy **một lượt** trên ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, Windows 11 x64, RTX 3060 Ti `10DE:2489 / 1043:8827` với VBIOS `94.04.6B.00.11`. Chương trình UEFI hoàn tất giao dịch, Windows nhận lại màn hình NVIDIA và phép đo CUDA xác nhận tốc độ Tensor tăng. Xem [báo cáo và giới hạn chứng cứ](WINDOWS-RTX3060TI-RESULTS.vi.md).

`windows/Install-RTX3060Ti.ps1` tự động hóa kiểm tra, build và đăng ký **mục thử F8** cho hồ sơ phần cứng đã kiểm chứng. Bộ cài kiểm tra đúng bo mạch, BIOS, mã PCI của card, trạng thái GPU và hai ESP; EFI còn kiểm tra PROM và cách bố trí firmware khi chạy. VBIOS trong bảng là giá trị **đã quan sát**, chưa phải điều kiện lọc của bộ cài. Chưa có bằng chứng để hứa rằng mọi máy Windows dùng 3060 Ti đều chạy được. Một bản EFI đã build cũng không thể dùng nguyên xi trên máy khác vì chứa GUID phân vùng cục bộ.

| Cấu hình | Tình trạng |
| --- | --- |
| ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, RTX 3060 Ti `10DE:2489 / 1043:8827`, VBIOS `94.04.6B.00.11` | Đã xác nhận một lần chạy UEFI, boot Windows và phép đo CUDA trên máy thử nghiệm. |
| Máy khác có cùng mã bo mạch, BIOS và PCI GPU | Chưa kiểm chứng; bộ cài có thể qua bước kiểm tra nhưng EFI vẫn có thể dừng ở preflight. |
| Bo mạch, BIOS hoặc mã PCI GPU khác | Chưa kiểm chứng; bộ cài từ chối hồ sơ khác. |

## Điều kiện trước khi bắt đầu

- Sao lưu dữ liệu và bảo đảm vào được ASUS F8 → **Windows Boot Manager**. Có bàn phím và màn hình nối với RTX.
- UEFI x64; Secure Boot **Off** vì EFI thử nghiệm chưa ký. C: phải giải mã BitLocker hoàn toàn và trạng thái bảo vệ phải Off. Bộ cài chỉ kiểm tra các điều kiện này, không tự sửa chúng. Giữ khóa khôi phục BitLocker trước mọi thay đổi BIOS.
- Một EFI System Partition (ESP) **riêng**, GPT, FAT32, ít nhất 1 GiB, gắn chữ ổ còn trống như `U:`. Không dùng, format hoặc xóa ESP đang chứa Windows Boot Manager. Bộ cài không tạo, thu nhỏ hoặc format phân vùng.
- PowerShell quản trị, Git nếu lấy mã bằng clone, Python 3.9+ và LLVM `clang`/`lld-link` 20.1.8. Các tệp firmware NVIDIA cần được chuẩn bị hợp pháp theo [hướng dẫn nguồn và hash](ASSETS.en.md); mã nguồn phát hành không kèm firmware, PROM, driver hay EFI riêng của máy.
- Muốn so sánh hiệu năng, cài các DLL CUDA/cuBLAS đã khóa hash bằng `benchmark/rtx3060ti/setup.ps1` trước khi đo.

Từ PowerShell quản trị, kiểm tra máy và xác định **đúng** hai ESP:

```powershell
Get-CimInstance Win32_BaseBoard | Select-Object Product
Get-CimInstance Win32_BIOS | Select-Object SMBIOSBIOSVersion
nvidia-smi --query-gpu=name,pci.device_id,pci.sub_device_id,vbios_version --format=csv,noheader
Get-Partition | Format-Table DiskNumber,PartitionNumber,DriveLetter,Size,GptType,Guid,IsSystem
Get-Volume -DriveLetter U | Format-List FileSystem,Size,Path
Get-BitLockerVolume -MountPoint C: | Format-List VolumeStatus,ProtectionStatus
Confirm-SecureBootUEFI
```

Chỉ tiếp tục khi `U:` đúng là ESP **riêng** đã chuẩn bị, `IsSystem=False`; bộ cài tự tìm và kiểm tra ESP Windows (`IsSystem=True`). Nếu máy không khớp hồ sơ ở trên, dừng tại kết quả `-Plan`; không sửa mã kiểm tra để ép cài.

## Lấy mã nguồn, chuẩn bị mốc trước

Mở bản checkout chứa chính tài liệu này và `windows/Install-RTX3060Ti.ps1`; nhánh mặc định cũ trên GitHub có thể chưa có bộ cài. Từ thư mục gốc của checkout, chạy:

```powershell
if (-not (Test-Path .\windows\Install-RTX3060Ti.ps1)) {
  throw 'Checkout này chưa có bộ cài RTX 3060 Ti.'
}
# Chuẩn bị 5 file .bin trong thư mục .\assets theo docs/ASSETS.en.md.
.\benchmark\rtx3060ti\setup.ps1
python .\benchmark\rtx3060ti\measure.py --phase before
```

Giữ nguyên file `measure.py`, thư viện CUDA, driver, giới hạn điện, độ phân giải và điều kiện tải nền giữa hai lượt đo. Phép đo trước tạo `benchmark/results/rtx3060ti/<thời gian>-before-.../summary.json`.

## Kiểm tra kế hoạch và cài

Ví dụ dưới đây dùng ESP riêng `U:` và LLVM trong `PATH`:

```powershell
.\windows\Install-RTX3060Ti.ps1 -Plan -UnlockDriveLetter U

# Tùy chọn: build và kiểm tra hash trước, chưa đặt file lên ESP.
.\windows\Install-RTX3060Ti.ps1 -BuildOnly -UnlockDriveLetter U `
  -Clang clang -LldLink lld-link -Python python

# Chỉ chạy khi kế hoạch xác nhận đúng máy, đúng hai ESP; lệnh cài sẽ kiểm tra 5 asset.
.\windows\Install-RTX3060Ti.ps1 -Install -UnlockDriveLetter U `
  -AssetsDirectory '.\assets' `
  -Clang clang -LldLink lld-link -Python python
```

`-Plan` (mặc định nếu không chọn chế độ) chỉ kiểm tra và in kế hoạch. `-BuildOnly` build nhưng không cài; `-Install` build hai EFI theo cấu hình cục bộ, đối chiếu hash, đặt trên ESP riêng và thêm mục **GPU Headless UNLOCK - EXPERIMENTAL** vào menu firmware. Chạy lại `-Install` với cặp EFI giống hệt chỉ xác minh; cặp đã cài khác hash sẽ bị từ chối. Windows Boot Manager vẫn đứng đầu; cài đặt không tự reboot và không bật chế độ unlock mặc định mỗi lần mở máy. Giữ cấu hình và bản sao BCD cục bộ để khôi phục; chúng không thuộc gói phát hành.

## Thử trên phần cứng

Đo trước xong, lưu công việc và **tắt hẳn** máy. Bật lại, bấm F8 trên màn hình ASUS và chọn **GPU Headless UNLOCK - EXPERIMENTAL**. Không chọn mục chẩn đoán chỉ đọc. Chương trình tự chạy một lần; không cần nhấn U. Màn hình RTX có thể tắt trong lúc tách driver UEFI, rồi Windows tiếp tục trực tiếp khi hoàn tất.

Nếu hiện `STOP / POWER OFF` hoặc màn hình đứng quá ba phút, giữ nút nguồn để tắt hẳn. Bật lại và chọn F8 → Windows Boot Manager; không lặp lại lần unlock trong cùng phiên firmware. Boot vào Windows được **chưa đủ** để kết luận thành công: phải thấy báo cáo child `AUTO......\REPORT.TXT` ghi `transaction result=0`, `FLR=1`, `clean=1`, sau đó xác nhận driver và bài đo.

Trong PowerShell quản trị sau khi Windows vào lại:

```powershell
Get-ChildItem U:\RTX3090-UNLOCK -Recurse -Filter REPORT.TXT |
  Sort-Object LastWriteTime -Descending |
  Select-Object FullName,LastWriteTime
.\windows\Install-RTX3060Ti.ps1 -RecoverWindowsFirst
nvidia-smi
```

Mở `REPORT.TXT` của lượt thử vừa chạy để kiểm tra các dòng kết quả. Script `Collect-Headless3060Ti.ps1` trong nghiên cứu cũ gắn cứng định danh của máy thử nghiệm nên không dùng làm công cụ thu log chung.

Chỉ sau khi log xác nhận giao dịch sạch và GPU hoạt động trong Windows, đo sau bằng **cùng** `measure.py`:

```powershell
python .\benchmark\rtx3060ti\measure.py --phase after
$before = Get-ChildItem .\benchmark\results\rtx3060ti -Directory |
  Where-Object Name -Like '*-before-*' | Sort-Object Name -Descending | Select-Object -First 1
$after = Get-ChildItem .\benchmark\results\rtx3060ti -Directory |
  Where-Object Name -Like '*-after-*' | Sort-Object Name -Descending | Select-Object -First 1
python .\benchmark\rtx3060ti\compare.py `
  (Join-Path $before.FullName 'summary.json') `
  (Join-Path $after.FullName 'summary.json')
```

Nếu không còn mốc `before` hoặc môi trường đã đổi, đo lại từ đầu theo cặp điều kiện tương đồng; không gắn nhãn một lượt chỉ đọc là kết quả sau unlock.

## Khôi phục và giới hạn

Windows Boot Manager vẫn là mục mặc định. Nếu cần khôi phục thứ tự ưu tiên sau một thay đổi sau này, chạy `windows/Install-RTX3060Ti.ps1 -RecoverWindowsFirst` bằng PowerShell quản trị. Lệnh này không xóa ESP, EFI, asset hoặc log. Trên máy khác, bản cài sẽ từ chối cấu hình chưa được lập hồ sơ; cần chẩn đoán chỉ đọc, mẫu phần cứng riêng và thử nghiệm có kiểm soát trước khi hỗ trợ thêm.

Bài đo này là GEMM CUDA, không phải FPS game; chưa có thử nghiệm khởi động tự động lặp lại, ngủ/khôi phục hay độ ổn định lâu dài. Không nâng giới hạn điện hoặc thay VBIOS để suy diễn mức tăng hiệu năng từ báo cáo này.
