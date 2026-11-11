# Tài khoản và bảo mật — từ 0.4.0

## Tài khoản trên từng máy

- Lần mở đầu tiên sau khi cập nhật lên 0.4.0, app yêu cầu **tạo tài khoản Quản trị**. Dữ liệu đang có được giữ nguyên.
- Người tạo nhận một **mã khôi phục** (20 ký tự). Mã chỉ hiện một lần; hãy chép ra giấy và cất riêng.
- Tài khoản nằm trong database của từng máy. Tài khoản **không có trong file sao lưu**: khôi phục dữ liệu từ máy khác không thay đổi người được đăng nhập.
- Người khác bấm **Đăng ký tài khoản** ở màn hình đăng nhập. Tài khoản ở trạng thái *Chờ duyệt* cho đến khi Quản trị duyệt và cấp vai trò.
- Quản trị cũng có thể tạo tài khoản trực tiếp với mật khẩu tạm. Người dùng phải đổi mật khẩu tạm ở lần đăng nhập đầu và nhận mã khôi phục khi đổi.

| Quyền | Quản trị | Cán bộ kỹ thuật | Chỉ xem |
|---|:-:|:-:|:-:|
| Xem dữ liệu, xuất báo cáo Excel | ✓ | ✓ | ✓ |
| Thêm/sửa/xóa thiết bị, hạng mục, sổ bảo trì, tệp; gia hạn; xác nhận; nhập Excel | ✓ | ✓ | |
| Sao lưu toàn bộ dữ liệu | ✓ | ✓ | |
| Khôi phục dữ liệu | ✓ | | |
| Cài đặt nhắc hạn, sao lưu tự động, danh mục, tiêu đề báo cáo | ✓ | | |
| Tải và cài bản cập nhật | ✓ | | |
| Quản lý tài khoản, xem nhật ký thao tác | ✓ | | |

Luôn phải còn ít nhất một Quản trị đang hoạt động: app không cho hạ vai trò hoặc khóa Quản trị cuối cùng.

## Mật khẩu, tạm khóa, tự khóa

- Mật khẩu: tối thiểu 8 ký tự, có chữ và số, không chứa tên đăng nhập. App chỉ lưu giá trị băm PBKDF2-HMAC-SHA256 210.000 vòng với muối ngẫu nhiên; mã khôi phục cũng được băm như vậy.
- Nhập sai mật khẩu 5 lần liên tiếp: tài khoản tạm khóa 5 phút. Mỗi lần bị khóa tiếp theo, thời gian tăng gấp đôi, tối đa 60 phút. Quản trị có thể mở tạm khóa sớm.
- Tên đăng nhập không tồn tại và mật khẩu sai nhận cùng một thông báo, nên không dò được tên tài khoản.
- **Tự khóa** là lựa chọn của từng người trong *Cài đặt → Hồ sơ của tôi*: Tắt, 1, 5, 10 (mặc định), 15, 30 hoặc 60 phút. App khóa sau khoảng thời gian không thao tác, hoặc khi mở lại sau khi để nền quá thời gian đó. Màn hình khóa giữ nguyên biểu mẫu đang nhập; mở khóa bằng mật khẩu của chính người đó.
- **Quên mật khẩu:** dùng mã khôi phục ở màn hình đăng nhập (mỗi mã dùng một lần, app cấp mã mới), hoặc nhờ Quản trị đặt lại mật khẩu tạm.

## Nhật ký thao tác

App ghi lại đăng nhập, đăng xuất, đăng nhập sai, tạm khóa, mọi thao tác thêm/sửa/xóa, gia hạn, xác nhận, nhập Excel, sao lưu, khôi phục, đổi cài đặt và các thay đổi tài khoản, kèm người thực hiện và thời điểm. Quản trị xem và tìm trong *Cài đặt → Quản trị → Nhật ký thao tác*, xuất được ra Excel. Nhật ký giữ 50.000 dòng mới nhất và không có trong file sao lưu.

## Sao lưu mã hóa

- **Sao lưu toàn bộ dữ liệu** mặc định tạo file `.backup.enc`, mã hóa AES-256-GCM bằng một mật khẩu sao lưu riêng (tối thiểu 10 ký tự). Khóa sinh bằng PBKDF2-SHA256 310.000 vòng.
- Sửa bất kỳ byte nào trong file sẽ khiến khôi phục báo lỗi, không có chuyện khôi phục âm thầm dữ liệu hỏng.
- **Mất mật khẩu sao lưu thì không mở được file.** Không dùng lại mật khẩu đăng nhập.
- Vẫn có thể chọn *Không mã hóa*, tạo file `.zip` như 0.3.0. Khôi phục nhận `.enc`, `.zip` và `.json`.
- Bản sao lưu tự động và bản sao lưu trước khi cập nhật **không mã hóa**, vì app phải tự khôi phục được chúng mà không hỏi mật khẩu. Chúng nằm trong thư mục dữ liệu riêng của app.

## Giới hạn cần biết

- Database SQLite trên máy **chưa được mã hóa**. Vai trò và mật khẩu ngăn thao tác nhầm hoặc trái phép *trong app*, nhưng không ngăn được người có quyền đọc thư mục dữ liệu của tài khoản Windows hoặc của điện thoại đã root. Hãy đặt mật khẩu cho tài khoản Windows (nên bật BitLocker) và khóa màn hình điện thoại.
- Không có "cửa sau". Nếu mất cả mật khẩu lẫn mã khôi phục của Quản trị duy nhất, không ai đặt lại được. Nên tạo **ít nhất hai Quản trị** và cất mã khôi phục ở nơi an toàn.
- Nhắc hạn nền vẫn chạy khi chưa đăng nhập, nhưng thông báo chỉ hiện số lượng hạng mục, không hiện chi tiết.
- Excel xuất ra không mã hóa; hãy lưu ở nơi phù hợp.

## Cập nhật thư viện

- Mỗi bản phát hành đối chiếu các gói Dart trong `pubspec.lock` với cơ sở dữ liệu lỗ hổng [OSV](https://osv.dev). Từ 0.4.1, không gói nào có lỗ hổng đã công bố.
- Chỉ dùng bản thư viện và công cụ build đã phát hành ít nhất 2 tuần, kể cả gói phụ thuộc gián tiếp, để tránh bản lỗi hoặc gói độc chưa bị phát hiện.
- SQLite gốc trong app là 3.54.0. Bản 3.54.1 sửa một lỗi tràn bộ nhớ chỉ có trên bản build 32-bit (một số điện thoại Android cũ). App chỉ chạy câu lệnh SQL của chính nó và không mở file database từ bên ngoài, nên rủi ro thấp. Sẽ nâng khi gói `sqlite3` cho Dart có bản kèm 3.54.1.
