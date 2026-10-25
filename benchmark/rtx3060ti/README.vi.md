# Tự chạy benchmark tính toán RTX 3060 Ti

Nhấp đúp [Run-Benchmark.cmd](Run-Benchmark.cmd) trên Windows. Chọn **1** để xem số TFLOPS trước/sau đã đo: nếu có hai tệp gốc, công cụ chạy lại phép so sánh; nếu thiếu tệp `after` riêng tư, nó chỉ hiển thị bảng trong báo cáo đã công bố. Mục này không tạo tải GPU. Chọn **2** hoặc **3** để tự đo phiên Windows hiện tại; công cụ in TFLOPS của FP32, TF32, FP16 và BF16 ngay trên màn hình, rồi lưu `environment.json`, ba `trial-*.json` và `summary.json` trong `benchmark/results/rtx3060ti/`. Chọn **4** để so hai tệp `summary.json`, **5** để xem lại một tệp, **6** để mở thư mục dữ liệu, hoặc **7** để xem điện, nhiệt độ, xung và tải GPU tức thời.

Bài đo mới cần Python 3.12 x64 có trong `PATH`, driver NVIDIA và CUDA/cuBLAS DLL. Nếu thiếu DLL, launcher hỏi trước khi tải gói chính thức đã khóa SHA-256. `measure.py` hiện khóa đúng ID GPU, subsystem và bus của **máy thử nghiệm này**; máy RTX 3060 Ti khác sẽ bị từ chối thay vì cho kết quả không thể so sánh với mốc cũ.

## Đo trước/sau mới

1. Đưa GPU về xung gốc, tắt Automatic Tuning/OC, giữ cùng driver và giới hạn điện (máy thử nghiệm mặc định 200 W). Sau khi thử ép xung, khởi động lại Windows rồi **kiểm tra lại** rằng offset/xung đã về mặc định; phần mềm tuning có thể tự áp dụng lại. Đóng game, video và công việc GPU khác.
2. Vào Windows qua **Windows Boot Manager** bình thường, chạy launcher, chọn **2**. Giữ lại đường dẫn `summary.json` của lượt `before`.
3. Tắt máy hoàn toàn. Khi bật, dùng ASUS **F8 → GPU Headless UNLOCK - EXPERIMENTAL**. Chỉ coi là lượt unlock nếu log UEFI **mới của đúng lần boot** báo `transaction result=0`, `FLR=1`, `clean=1` và Windows nhận lại RTX 3060 Ti. Xem [hướng dẫn cài và kiểm tra](../../docs/WINDOWS-RTX3060TI.vi.md).
4. Chạy launcher, chọn **3**. Giữ lại đường dẫn `summary.json` của lượt `after`. Chọn **4**, dán chính xác hai đường dẫn để in bảng TFLOPS và tỷ số.

`before`/`after` chỉ là nhãn trong tệp đo; công cụ không tự xác nhận UEFI đã unlock. Phải dùng **cùng** [measure.py](measure.py), CUDA/cuBLAS, driver, mức điện, xung và điều kiện tải nền. [compare.py](compare.py) từ chối cặp khác mã nguồn benchmark, Python, DLL, GPU hoặc cấu hình bài đo; nó hiển thị khác biệt driver/điện để người đo kiểm tra. Đừng dùng `benchmark/run-benchmark.ps1` cho card này vì script đó dành cho RTX 3090.

Bài đo dùng phép nhân ma trận 4096 × 4096 bằng cuBLAS: làm nóng 2 giây, lấy 30 mẫu bằng CUDA event cho mỗi chế độ, lặp ba lượt và báo trung vị TFLOPS. Đây là **hiệu năng tính toán tổng hợp**, không phải FPS game. Chỉ hai phần tử đầu/cuối của kết quả được kiểm tra. [Báo cáo trước/sau đã đo và giới hạn chứng cứ](../../docs/WINDOWS-RTX3060TI-RESULTS.vi.md).
