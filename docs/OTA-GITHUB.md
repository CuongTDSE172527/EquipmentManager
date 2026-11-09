# Nghiên cứu cập nhật qua GitHub

Ngày đối chiếu tài liệu: 09/11/2026. Áp dụng cho Windows 10/11 x64 và Android 8+, repo **riêng tư** `CuongTDSE172527/EquipmentManager`.

## Kết luận cho 0.1.3

Có thể dùng GitHub Releases để phân phối bản cập nhật qua Internet. 0.1.3 hoàn thành nghiên cứu; **chưa có chức năng tự kiểm tra, tải hoặc cài cập nhật trong app**. Cách dùng hiện tại: đăng nhập GitHub trên trình duyệt, tải bản phát hành rồi cài đè. Dữ liệu SQLite được nâng schema khi mở app. Hãy sao lưu trước khi nâng cấp; không gỡ app cũ.

Đề xuất bước tiếp theo là cập nhật **theo yêu cầu của người dùng**, tải toàn bộ APK/bộ cài EXE, xác minh tệp rồi chuyển cho trình cài của hệ điều hành. Dữ liệu và các chức năng quản lý tiếp tục hoạt động ngoại tuyến. Không cần đưa database lên GitHub.

## Điểm cần giải quyết

| Vấn đề | Kết quả nghiên cứu / lựa chọn đề xuất |
|---|---|
| Repo riêng tư | API đọc release và asset cần xác thực có quyền Contents: read. Không nhúng token của chủ repo vào APK/EXE. Có thể giữ bước tải bằng trình duyệt đã đăng nhập; nếu tích hợp trong app thì dùng xác thực riêng của người sử dụng, lưu bí mật trong Android Keystore / Windows Credential Manager. Quyền tối thiểu phải được rà soát khi chọn GitHub App hoặc token theo repo. |
| Bản thử 0.x | `/releases/latest` bỏ qua prerelease và draft. Phải dùng danh sách releases, phân trang, loại draft, chọn kênh thử/ổn định và so sánh phiên bản theo số; không so sánh chuỗi hoặc chỉ lấy phần tử đầu. |
| Tải asset | Dùng ID asset qua API với `Accept: application/octet-stream`, xử lý cả HTTP 200 và 302. Không chuyển tiếp Authorization sang máy chủ khác khi redirect. Đường dẫn có hạn chỉ dùng lúc tải, không lưu làm URL cập nhật cố định. |
| Android | APK phải giữ applicationId và khóa ký, versionCode tăng dần. Android 8+ yêu cầu cho phép nguồn cài ngoài. Luồng đề xuất luôn đưa người dùng tới trình cài xác nhận, xử lý từ chối/hủy. Google Play In-App Updates không phải cơ chế cập nhật cho APK phân phối qua GitHub. |
| Windows | Dùng bộ cài Inno hiện có để cài đè, giữ AppId và thư mục dữ liệu. Sau khi xác nhận và sao lưu, đóng app trước khi thay DLL/EXE; mở lại rồi kiểm tra phiên bản/schema. ZIP portable cần tiến trình cập nhật riêng để đợi app thoát và có khả năng khôi phục tệp nếu thay thế lỗi. |
| MSIX | App Installer hỗ trợ kiểm tra/cài cập nhật, nhưng MSIX phải được ký và chứng chỉ được máy tin cậy. Chưa phù hợp để thay bộ cài EXE hiện tại trong khi ký số Windows còn ngoài phạm vi. |

Nguồn chính thức: [GitHub Releases API](https://docs.github.com/en/rest/releases/releases), [Release Assets API](https://docs.github.com/en/rest/releases/assets), [xác thực ứng dụng GitHub](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps), [phân phối APK ngoài cửa hàng](https://developer.android.com/distribute/marketing-tools/alternative-distribution), [ký APK](https://source.android.com/docs/security/features/apksigning), [Play In-App Updates](https://developer.android.com/guide/playcore/in-app-updates), [App Installer](https://learn.microsoft.com/en-us/windows/msix/app-installer/update-settings), [ký MSIX](https://learn.microsoft.com/en-us/windows/msix/package/signing-package-overview).

## Luồng đề xuất cho phiên bản triển khai OTA

1. Người dùng bấm **Kiểm tra cập nhật**. App kiểm tra kết nối với timeout; khi mất mạng vẫn tiếp tục sử dụng dữ liệu cục bộ.
2. Đọc release theo kênh đã chọn, so sánh SemVer/versionCode, chọn đúng nền tảng và kiến trúc. Chặn hạ phiên bản để tránh mở schema mới bằng app cũ.
3. Hiện phiên bản, thay đổi, kích thước tải; chỉ tải sau khi người dùng chọn. Tải vào tệp tạm, hỗ trợ hủy và báo thiếu dung lượng.
4. Kiểm tra SHA-256 so với asset/manifest và danh tính gói; với Android kiểm tra chứng chỉ ký. Đề xuất bổ sung manifest được ký bằng khóa cập nhật riêng và công khai khóa xác minh trong app để tăng khả năng phát hiện manifest bị thay. Checksum lấy cùng nguồn giúp kiểm tra toàn vẹn, không thay thế chữ ký của nhà phát hành.
5. Sao lưu SQLite bằng chức năng sao lưu nhất quán, rồi mở trình cài. Không tự ghi đè database. Không đưa token vào đối số tiến trình, log hoặc báo cáo lỗi.
6. Mở app mới, chạy migration, xác nhận phiên bản và dữ liệu. Thử đầy đủ hủy tải/cài, token hết hạn, asset thiếu, hash sai, bản thử/ổn định, thiếu dung lượng và lỗi migration trước khi bật OTA cho người dùng.

Các phương án triển khai cần chốt sau nghiên cứu: giữ tải riêng tư bằng trình duyệt; tích hợp xác thực GitHub từng người dùng; hoặc tạo kho **chỉ chứa bộ cài công khai**. Phương án công khai cần chủ repo chủ động cho phép vì thay đổi khả năng truy cập bộ cài. 0.1.3 giữ nguyên repo riêng tư và cách phân phối hiện tại.
