# Cập nhật OTA qua GitHub — từ 0.1.4

Repo `CuongTDSE172527/EquipmentManager` đã được chủ repo chuyển sang **Public**. App đọc GitHub Releases và tải bộ cài qua HTTPS, không cần tài khoản/token. Dữ liệu thiết bị và bản sao lưu không được gửi lên mạng.

## Cách dùng

0.1.3 và các bản trước chưa có OTA. Hãy sao lưu rồi **cài đè 0.1.4 một lần**. Từ 0.1.4:

1. Mở **Cài đặt → Cập nhật ứng dụng → Kiểm tra cập nhật** khi có Internet.
2. Từ 0.3.0, bản Beta phát hành như bản chính thức nên luôn được tìm thấy. Bật **Bao gồm bản thử nghiệm** nếu muốn nhận thêm bản Pre-release (0.1.x–0.2.0 thuộc kênh này).
3. Xem phiên bản, kích thước, thay đổi rồi bấm **Tải bản cập nhật**. Có thể hủy khi tải. Tệp dở hoặc sai hash bị loại bỏ.
4. Android: nếu chưa có quyền, bấm **Cho phép cài từ EquipmentManager**, bật quyền trong Android rồi quay lại app.
5. Bấm **Cài đặt bản cập nhật → Sao lưu và cài đặt**. Chỉ mở trình cài sau khi sao lưu thành công. Android hiện trình cài hệ thống để bạn xác nhận; hủy màn hình đó giữ bản đang dùng.
6. Windows: đóng các cửa sổ EquipmentManager khác. App sao lưu, thoát, cập nhật rồi mở lại. Bản đã cài dùng EXE; portable dùng ZIP, thay tệp tại thư mục đang chạy. Không di chuyển/xóa app hoặc bộ cài trong lúc cập nhật.

Cập nhật theo lựa chọn của người dùng, không ép cài. Từ 0.2.0 có tùy chọn **Tự kiểm tra khi mở ứng dụng** (mặc định tắt): tối đa 1 lần/ngày, chỉ đọc danh sách Releases và báo có bản mới; không tự tải hay cài, lỗi mạng thì im lặng và thử lại lần mở sau. Lựa chọn **Bao gồm bản thử nghiệm** được lưu và dùng cho cả kiểm tra tự động. Mất mạng không ảnh hưởng quản lý cục bộ. Cần đủ dung lượng cho bộ cài, giải nén và sao lưu.

## Dữ liệu và sao lưu

Trước khi cài, thiết bị, hạn, lịch sử bảo trì/sửa chữa, lịch sử hoàn thành, danh mục và cài đặt được đọc trong một giao dịch SQLite rồi ghi JSON. Không ghi được sao lưu thì dừng cập nhật.

Tệp nằm trong thư mục dữ liệu app: `backups/before-update-<phiên-bản>-<mốc-thời-gian>.backup.zip` (từ 0.3.0; ZIP gồm `backup.json` và tệp đính kèm, bản cũ hơn là `.backup.json`). Đường dẫn cụ thể hiện trong phần cập nhật. Windows mặc định: `%APPDATA%\vn.cah\EquipmentManager\backups`. Android lưu trong thư mục riêng; vẫn nên dùng **Dữ liệu & báo cáo → Sao lưu** để giữ thêm bản ở nơi khác trước khi đổi máy/gỡ app.

Cài đè giữ SQLite. Không gỡ app cũ. Không hạ versionCode: app cũ có thể không đọc được schema mới.

## Kiểm tra trước cài

- Repository cố định, đọc releases có phân trang, loại draft, lọc kênh, so sánh phiên bản theo số. Không dùng `/releases/latest` vì bỏ qua prerelease.
- Chỉ nhận đúng tên asset theo phiên bản/nền tảng, trạng thái uploaded, dung lượng hợp lệ và digest SHA-256. Metadata thiếu/sai thì dừng.
- Tải luồng vào `.part`, giới hạn kích thước/thời gian và các máy chủ HTTPS chuyển tiếp của GitHub. Không gửi Authorization. Chỉ đổi tên khi đúng kích thước và hash; kiểm tra lại trước cài.
- Android kiểm tra native: file trong thư mục cập nhật riêng, hash, applicationId, versionName/versionCode mới hơn, chứng chỉ ký trùng app hiện tại. FileProvider chỉ chia sẻ thư mục cập nhật. Android tiếp tục xác minh APK khi cài.
- Windows helper xác minh hash, chờ app thoát rồi thay tệp. ZIP được kiểm tra đường dẫn giải nén/phiên bản EXE, sao lưu tệp cũ và rollback khi sao chép lỗi. EXE gọi Inno cài đè đúng thư mục. Giữ tệp riêng đặt cạnh portable.

Windows ghi `update-status.json`, `installer.log` (EXE) cạnh bộ cài trong `updates/<phiên-bản>`. Nếu không tự khắc phục được, cài đè lại bộ cài đã tải hoặc tải lại từ Release. Sao lưu dữ liệu vẫn được giữ. Rollback ZIP xử lý lỗi sao chép phát hiện được; không bảo đảm tự phục hồi khi mất điện giữa chừng.

EXE chưa ký số: SHA-256 kiểm tra toàn vẹn so với metadata GitHub qua HTTPS, không phải chữ ký độc lập nếu repo bị chiếm quyền. Ký số Windows/manifest ký riêng là hướng tăng cường sau này. APK giữ khóa ký hiện có.

## Kiểm thử / phát hành

- `test/updates_test.dart`: phiên bản/kênh/nền tảng, phân trang, metadata sai, redirect, rate limit, streaming, cache, hủy, hash sai.
- `test/update_card_test.dart`: quyền, xác nhận, backup trước cài và chặn cài khi lỗi. `test/update_backup_test.dart`: khôi phục backup OTA.
- `tool/test_windows_update.ps1`: portable, giữ tệp người dùng, chặn hash sai, rollback khi DLL khóa. Release thử thêm cài đè EXE trên runner Windows tạm; TestSetup không chạy trên máy phát triển.
- Workflow **Kiểm tra cài OTA Android** dùng dữ liệu giả trên API 26/33: xác minh gói hợp lệ, chặn sai hash/phiên bản/khóa ký, mở quyền nguồn ngoài và trình cài, nâng versionCode rồi kiểm tra SQLite còn dữ liệu. APK harness không phát hành.

APK/EXE/ZIP chỉ build bằng GitHub Actions. Tag mới chạy kiểm tra, build, xác minh ký APK và thử helper Windows trước khi tạo Release. GitHub cung cấp digest từng asset. Không upload dữ liệu thật/khóa ký vào repo hay Release.

Tài liệu chính thức đối chiếu 09/11/2026: [GitHub Releases](https://docs.github.com/en/rest/releases/releases), [Release assets và SHA-256](https://docs.github.com/en/rest/releases/assets), [phân phối APK](https://developer.android.com/distribute/marketing-tools/alternative-distribution), [quyền cài gói](https://developer.android.com/reference/android/content/pm/PackageManager#canRequestPackageInstalls()), [FileProvider](https://developer.android.com/reference/androidx/core/content/FileProvider), [ký APK](https://source.android.com/docs/security/features/apksigning).
