# Báo cáo thử nghiệm RTX 3060 Ti trên Windows

[English](WINDOWS-RTX3060TI-RESULTS.en.md) · [Hướng dẫn cài đặt](WINDOWS-RTX3060TI.vi.md)

## Phạm vi và phương pháp

Ngày 25-10-2026 (Asia/Bangkok), một máy ASUS TUF GAMING Z690-PLUS WIFI D4, BIOS 2602, Core i7-14700K, Windows 11 Pro, RTX 3060 Ti `10DE:2489 / 1043:8827`, VBIOS `94.04.6B.00.11` đã chạy mục UEFI headless bằng F8. Driver NVIDIA trong cả hai phép đo là 617.42; giới hạn điện giữ nguyên **200 W**. Đây là bằng chứng cho **một máy, một lượt unlock**, không phải kiểm chứng mọi 3060 Ti.

Cùng file `benchmark/rtx3060ti/measure.py` (SHA-256 `557CDFF46B3F83F5E1BEB1EB55EB1E7479B71EDDB397BA7B0BAF323BDA174C6B`) gọi CUDA 12.6 và cuBLAS 12.6 để đo phép nhân ma trận 4096 × 4096. Mỗi chế độ có 2 giây làm nóng, 30 mẫu CUDA event, 3 lượt; bảng dùng trung vị. Bộ so sánh đã khớp phiên bản Python 3.12.8, hash DLL, danh tính GPU và cấu hình bài đo giữa trước/sau.

| Chế độ GEMM | Trước (TFLOPS) | Chẩn đoán chỉ đọc (TFLOPS) | Sau unlock (TFLOPS) | Sau / Trước |
| --- | ---: | ---: | ---: | ---: |
| FP32 pedantic | 10,23 | 11,20 | 10,66 | 1,042× |
| TF32 Tensor, cộng dồn FP32 | 16,70 | 17,99 | 34,62 | **2,072×** |
| FP16 Tensor, cộng dồn FP32 | 35,21 | 35,35 | 66,91 | **1,900×** |
| BF16 Tensor, cộng dồn FP32 | 35,12 | 35,36 | 67,13 | **1,912×** |

Ba lượt sau unlock cho khoảng trung vị: FP32 10,55–10,90; TF32 34,58–34,84; FP16 66,48–67,21; BF16 66,73–67,25 TFLOPS. Lượt chẩn đoán chỉ đọc vẫn ở mức Tensor cũ, hỗ trợ kết luận rằng mức tăng lớn xuất hiện sau giao dịch unlock. FP32 của lượt chỉ đọc cao hơn cả bản sau, vì thế **không có bằng chứng FP32 tăng ổn định**.

## Bằng chứng UEFI và Windows

Log wrapper `HLS000005.TXT` ghi SS0 lạnh `0x54372012`, SS1 `0x4`, qua preflight, tách ba EDID child và NVIDIA GOP, rồi xác nhận sẵn sàng gọi child. Báo cáo child `AUTO000000/REPORT.TXT` ghi SS0/SS1 `0x88888888/0x8` trước **và** sau PCIe FLR, `transaction result=0`, `started=1`, `quiesced=1`, `fault=0`, `retained=0`, `maps=0`, `FLR=1`, `FINAL status=0 ... clean=1`. Wrapper tiếp tục vào Windows; `nvidia-smi` nhận card và bài đo sau chạy hoàn tất. Tại cuối bài đo, GPU đạt 99% tải, khoảng 192 W, 60 °C. Windows Boot Manager được trả về vị trí đầu tiên; mục unlock vẫn chỉ chạy khi chọn F8.

Nguồn dữ liệu cục bộ:

- Mốc trước, nằm trong mã nguồn: [`benchmark/rtx3060ti/baseline/20261024T164051Z-before-19d2e439/summary.json`](../benchmark/rtx3060ti/baseline/20261024T164051Z-before-19d2e439/summary.json).
- Mốc sau: `benchmark/results/rtx3060ti/20261024T183204Z-after-84d1f28f/summary.json`, SHA-256 `CE366261222471E930FA6AF6E6508989172EF111B2CF7E6B154BBD3CC2B40FF6`.
- Log child: `research/results/rtx3060ti-headless/20261024T183145Z-1f74077a/AUTO000000/REPORT.TXT`, SHA-256 `2017C986CC1F394290FC64440398CA8C9BCF0F1EE1C4B063E99CE1DE4D3C2838`.
- Log wrapper: `research/results/rtx3060ti-headless/20261024T183145Z-1f74077a/HLS000005.TXT`, SHA-256 `3454C2458B02DFE1C8AF79922C43A7A4CF770109CA79151D131B255190E40F59`.

Các log UEFI và kết quả sau là dữ liệu **riêng của máy thử nghiệm**, không đóng gói vào bản phát hành công khai. Hash và bảng đã lọc cho phép đối chiếu với bản cục bộ mà không công bố toàn bộ capture. Phép đo GEMM không suy ra FPS game, lợi ích ứng dụng thực, ngủ/khôi phục, khởi động tự động lặp lại hay độ ổn định dài hạn. Chưa đo game trên máy này.
