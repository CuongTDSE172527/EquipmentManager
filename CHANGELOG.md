# Thay đổi

## 0.4.3 Beta

Bản sửa lỗi, không đổi dữ liệu hay cách dùng. Trên Windows cần cài tay một lần (xem bên dưới); Android cập nhật bằng OTA như thường.

- **Sửa cập nhật OTA trên Windows** báo "Windows chưa sẵn sàng cập nhật. Ứng dụng vẫn mở, chưa thay tệp."
  - Nguyên nhân: app chạy helper cập nhật bằng `powershell.exe` ở chế độ tách rời (`ProcessStartMode.detached`, không có console). Trên Windows 11 hiện tại, Windows PowerShell 5.1 treo ngay lúc khởi động trong chế độ này, trước khi chạy dòng script nào. Sau 30 giây app bỏ cuộc. Đã tái hiện trên máy thật: chế độ tách rời treo, chế độ thường chạy xong trong 0,5 giây và vẫn chạy tiếp sau khi app thoát.
  - Sửa: chạy helper ở chế độ thường và đọc bỏ stdout/stderr.
  - Kiểm thử CI cũ gọi helper từ một PowerShell có sẵn console nên không gặp lỗi. Thêm kiểm thử gọi helper qua đúng đường Dart của app, chạy trong job Windows của CI và của workflow phát hành.
  - **Máy Windows đang dùng 0.4.x phải cài bản này bằng tay một lần** (tải bộ cài từ Releases, cài đè, dữ liệu giữ nguyên), vì bản đang cài vẫn dùng cách gọi cũ. Android không bị ảnh hưởng.

## 0.4.2 Beta

Bản sửa lỗi, không đổi dữ liệu hay cách dùng. Cập nhật thẳng từ 0.4.x bằng OTA.

- **Sửa lỗi Excel báo "We found a problem with some content" rồi tự sửa `styles.xml`** khi mở mọi file app xuất ra (kế hoạch, theo dõi, phụ lục, hạng mục/lịch sử) và mẫu nhập. Lỗi có từ 0.1.x.
  - Nguyên nhân: thư viện `excel` chỉ ghi màu nền dạng ARGB 8 ký tự bắt đầu bằng `FF`. Màu nền tiêu đề `E2E8F0` (6 ký tự) bị bỏ, nhưng vẫn được đếm và vẫn có ô trỏ tới.
  - Sửa: dùng mã màu 8 ký tự (`FFE2E8F0`, `FFFFFFFF`, `FFD9D9D9`). Hàng tiêu đề giờ có nền xám như thiết kế.
  - Thêm kiểm thử đọc `styles.xml` của mọi file xuất ra, kiểm tra số lượng khai báo, chỉ số font/nền/viền/định dạng số và mã màu.

## 0.4.1 Beta

Bản bảo trì: nâng thư viện và công cụ build, không đổi dữ liệu hay cách dùng. Cập nhật thẳng từ 0.4.0 bằng OTA.

- **Rà lỗ hổng**: đối chiếu toàn bộ 88 gói Dart trong `pubspec.lock` với cơ sở dữ liệu OSV, không gói nào có lỗ hổng đã công bố. Hai lỗ hổng cũ của `archive` chỉ ảnh hưởng bản dưới 3.3.8, app dùng 3.6.1.
- **Android**: Gradle 9.3.1 → 9.8.2 (kèm kiểm tra SHA-256 của bộ cài Gradle), Android Gradle Plugin 9.1.0 → 9.4.1, Kotlin 2.4.0 → 2.4.21. Chuyển sang Built-in Kotlin của AGP 9 (`android.builtInKotlin=true`) theo yêu cầu của Flutter, tránh lỗi build ở các bản Flutter sau.
- **SQLite gốc vẫn là 3.54.0**. Bản 3.54.1 sửa một lỗi tràn bộ nhớ trên bản build 32-bit, nhưng gói `sqlite3` cho Dart chưa có bản kèm 3.54.1. Ảnh hưởng thấp: app chỉ chạy câu lệnh SQL của chính nó và không mở file database lạ. Sẽ nâng khi gói có bản mới.
- **GitHub Actions chạy Node.js 24**: `actions/checkout@v6`, `upload-artifact@v7`, `download-artifact@v8`, `setup-java@v5`, `gradle/actions/setup-gradle@v5`. Giữ `setup-gradle` ở v5 vì v6 kèm điều khoản sử dụng thương mại cho phần lưu cache.
- **Nâng thư viện**:
  - `file_picker` 10 → 13: API tĩnh mới, đọc tệp đã chọn qua `readAsBytes()`; kiểm tra dung lượng trước khi đọc.
  - `csv` 6 → 8: đọc CSV bằng `CsvDecoder`, giữ dòng trống để số dòng báo lỗi khớp file gốc.
  - `package_info_plus` 9 → 10, `pointycastle` 3.9 → 4.0, `sqlite3` 3.5 → 3.8.
  - Chỉ chọn bản đã phát hành ít nhất 2 tuần, kể cả gói phụ thuộc gián tiếp.
- Chưa nâng được `archive` 4, `xml` 7, `equatable` 3 vì `excel` 4.0.6 còn khóa bản cũ. `material_color_utilities`, `test_api` và `meta` do Flutter SDK quyết định.

## 0.4.0 Beta

- **Tài khoản cục bộ**:
  - Lần mở đầu tạo Quản trị kèm mã khôi phục.
  - Đăng ký chờ duyệt, đăng nhập, đăng xuất, hồ sơ cá nhân, đổi mật khẩu, mã khôi phục dùng một lần.
  - Quản trị tạo tài khoản với mật khẩu tạm, duyệt, đổi vai trò, khóa/mở, đặt lại mật khẩu; luôn giữ ít nhất một Quản trị.
- **Vai trò** Quản trị / Cán bộ kỹ thuật / Chỉ xem: giao diện ẩn thao tác không được phép, controller chặn lại lần nữa.
- **Bảo mật**:
  - PBKDF2-HMAC-SHA256 210.000 vòng, chạy ngoài luồng giao diện.
  - Tạm khóa sau 5 lần sai, thời gian khóa tăng dần; thông báo lỗi không lộ tên tài khoản có tồn tại hay không.
  - Tự khóa theo lựa chọn của từng người (cả khi quay lại từ nền); màn hình khóa giữ nguyên biểu mẫu đang nhập.
- **Nhật ký thao tác** cho đăng nhập, thay đổi dữ liệu, nhập, sao lưu, khôi phục, cài đặt, tài khoản; xem, tìm, xuất Excel; giữ 50.000 dòng.
- **Sao lưu mã hóa** AES-256-GCM với PBKDF2 310.000 vòng (`.backup.enc`); phát hiện file bị sửa; vẫn nhận `.zip`/`.json`.
- **Nền đồng bộ**:
  - Bảng `sync_state` (phiên bản, tombstone, hàng chờ), mã thiết bị.
  - `SyncTransport`/`SyncEngine` với quy tắc bản mới nhất thắng; chưa có máy chủ nên không gửi dữ liệu.
  - Đặc tả ở `docs/SYNC.md`.
- SQLite schema 4 (tự nâng từ 1–3). Tài khoản, nhật ký, trạng thái đồng bộ không nằm trong bản sao lưu.
- Thêm thư viện `pointycastle` 3.9.1 (thuần Dart).
- Sửa lỗi mã hóa ký tự ở mô tả `pubspec.yaml` và chuỗi tiếng Việt trong một kiểm thử của 0.3.0.

## 0.3.0 Beta

- **Tệp đính kèm** cho thiết bị: PDF, ảnh, Word, Excel tối đa 25 MB; tên hiển thị, ghi chú, gắn với hạng mục hoặc công việc sổ bảo trì; mở bằng ứng dụng mặc định (Android qua FileProvider), lưu bản sao, sửa, xóa. Xóa hạng mục/công việc giữ tệp; xóa thiết bị xóa tệp.
- SQLite **schema 3** (bảng `attachments`, tự nâng từ 1/2). Sao lưu **ZIP định dạng 3** cho sao lưu tay, tự động và trước OTA; kiểm tra SHA-256 và kích thước từng tệp trước khi thay dữ liệu; vẫn đọc JSON 1/2.
- Sao lưu tự động giới hạn tổng dung lượng (~500 MB, luôn giữ 2 bản mới nhất), vẫn liệt kê/khôi phục bản JSON của 0.2.0.
- Phát hành 0.x dạng **bản chính thức có nhãn Beta** (Latest) thay vì Pre-release; app hiện nhãn Beta.

## 0.2.0 — thử nghiệm

- Hàng chờ **Cần xác nhận**: thẻ trên Tổng quan, bộ lọc riêng, thao tác Xác nhận dữ liệu (xem trạng thái sau xác nhận; Xác nhận đúng giữ nguyên hạn và ghi ngày xác nhận vào ghi chú, hoặc Sửa hạn). Lịch sử hoàn thành không bị ghi thêm.
- **Tự sao lưu xoay vòng** khi mở app: mặc định 7 ngày/lần, giữ 10 bản trong `backups/auto`, bỏ qua database trống. Khôi phục từ bản tự động trong Dữ liệu & báo cáo. Mọi lần khôi phục đều tự lưu dữ liệu hiện tại trước. Nhắc sao lưu ra ngoài vẫn tính riêng.
- **Kế hoạch đến hạn theo kỳ** (tháng này/sau, quý này/sau) xuất Excel: gom theo đơn vị thực hiện, tùy chọn kèm mục quá hạn, sheet Tổng hợp. Hạn MM/yyyy tính đến cuối tháng; thiết bị không còn sử dụng, mục loại trừ/đã xong/chưa có ngày không vào kế hoạch.
- **Tự kiểm tra cập nhật** khi mở app, mặc định tắt, tối đa 1 lần/ngày, chỉ báo có bản mới. Lưu lựa chọn Bao gồm bản thử nghiệm.
- Không đổi schema SQLite (2) và định dạng sao lưu (2); cài đặt mới nằm trong payload cài đặt và có giá trị mặc định khi đọc dữ liệu cũ.
- Workflow phát hành thử helper Windows từ bộ cài 0.1.4.

## 0.1.4 — 09/11/2026

- OTA từ GitHub public trong Cài đặt: kiểm tra/kênh/thay đổi/kích thước, tải có tiến độ và hủy.
- Xác minh asset, dung lượng, SHA-256; chặn URL lạ và cài lại/hạ phiên bản. Android kiểm tra applicationId, phiên bản, khóa ký, xử lý quyền nguồn ngoài và mở trình cài hệ thống.
- Tự sao lưu trước cài. Windows đóng app để helper cài đè EXE hoặc cập nhật ZIP tại chỗ; rollback ZIP khi sao chép lỗi, giữ sao lưu.
- Kiểm thử native Android 8/13 và helper ZIP/EXE trong workflow Windows. Không nhúng token; dữ liệu tiếp tục ngoại tuyến.
- Cần cài đè 0.1.4 lần đầu để có OTA cho các bản sau.

## 0.1.3 — 09/11/2026

- Thêm sổ bảo trì/sửa chữa trong chi tiết từng thiết bị: ghi công việc cũ, ngày thực hiện, đơn vị, chi phí VND, chi tiết/phụ tùng/kết quả; sửa và xóa công việc nhập tay.
- Cùng màn hình hiển thị các lần hoàn thành hạng mục bảo dưỡng/sửa chữa sẵn có; tìm nội dung, đơn vị, ghi chú, lọc loại/năm và cộng chi phí đã ghi.
- Công việc nhập tay giữ nguyên hạn theo dõi; thêm vào sao lưu/khôi phục và sheet Excel “Bảo trì sửa chữa”. Nâng schema SQLite lên 2, tiếp nhận backup phiên bản 1.
- Logo vector mới dùng đồng nhất trên Android, Windows và trong app.
- Bỏ chuyển cảnh trang/hộp thoại, chuyển động thanh điều hướng/đổi theme, hiệu ứng gợn nút và Hero của nút thêm. Giữ phản hồi chọn, hover, focus và thanh tiến trình tác vụ.
- Tính số cảnh báo theo thiết bị một lượt thay vì tính/sắp xếp lại toàn bộ danh sách cho từng dòng; tái sử dụng theme.
- Nghiên cứu OTA GitHub cho repo riêng tư; chi tiết ở [docs/OTA-GITHUB.md](docs/OTA-GITHUB.md). Chưa tích hợp tự tải/cài trong app.

## 0.1.2

- Giữ độ chính xác tháng/năm khi nhập ô Excel kiểu ngày nhưng chỉ hiển thị tháng/năm.
