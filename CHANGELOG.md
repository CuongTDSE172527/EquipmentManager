# Thay đổi

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
