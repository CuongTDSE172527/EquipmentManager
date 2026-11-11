# EquipmentManager

Ứng dụng quản lý trang thiết bị ngoại tuyến cho Windows 10/11 x64 và Android 8 trở lên. Toàn bộ giao diện bằng tiếng Việt, không cần máy chủ. Từ 0.4.0, người dùng đăng nhập bằng tài khoản cục bộ trên từng máy. Mỗi máy có database SQLite riêng; chuyển dữ liệu bằng sao lưu/khôi phục.

## Mới trong 0.4.3 Beta — sửa cập nhật OTA trên Windows

Cập nhật trong app trên Windows không còn dừng ở thông báo "Windows chưa sẵn sàng cập nhật". **Máy Windows đang chạy 0.4.1 hoặc 0.4.2 cần cài tay 0.4.3 một lần** (tải `EquipmentManager-0.4.3-windows-setup.exe` trong Releases, chạy và cài đè; dữ liệu giữ nguyên). Từ 0.4.3, OTA trên Windows hoạt động lại. Android không bị ảnh hưởng. Chi tiết trong [CHANGELOG](CHANGELOG.md).

## Mới trong 0.4.2 Beta — sửa file Excel

File Excel app xuất ra (báo cáo, kế hoạch, mẫu nhập) không còn bị Excel báo "We found a problem with some content" và tự sửa `styles.xml`; hàng tiêu đề có nền xám đúng thiết kế. Chi tiết trong [CHANGELOG](CHANGELOG.md).

## Mới trong 0.4.1 Beta — bảo trì thư viện

Nâng `file_picker` 13, `csv` 8, `package_info_plus` 10, `pointycastle` 4, `sqlite3` 3.8, Gradle 9.8.2, AGP 9.4.1, Kotlin 2.4.21; GitHub Actions chạy Node.js 24. Không gói Dart nào có lỗ hổng đã công bố (kiểm tra theo OSV). Không đổi dữ liệu hay cách dùng. Chi tiết trong [CHANGELOG](CHANGELOG.md).

## Mới trong 0.4.0 Beta — tài khoản, bảo mật, nền đồng bộ

- **Lần mở đầu sau khi cập nhật:** tạo tài khoản **Quản trị** và cất **mã khôi phục**. Dữ liệu hiện có giữ nguyên. Từ đó luôn phải đăng nhập.
- **Đăng ký, đăng nhập, đăng xuất, hồ sơ.**
  - Người khác tự đăng ký và chờ Quản trị duyệt, hoặc Quản trị tạo tài khoản với mật khẩu tạm.
  - Có ba vai trò: **Quản trị**, **Cán bộ kỹ thuật** (sửa dữ liệu, sao lưu) và **Chỉ xem** (xem, xuất báo cáo).
  - Đổi mật khẩu, mã khôi phục và hồ sơ trong *Cài đặt → Hồ sơ của tôi*.
- **Bảo mật:**
  - Mật khẩu băm PBKDF2 (210.000 vòng).
  - Sai 5 lần thì tạm khóa tài khoản, thời gian khóa tăng dần.
  - **Tự khóa** khi không dùng, mỗi người tự chọn thời gian (mặc định 10 phút, tắt được).
  - **Nhật ký thao tác** ghi ai làm gì, lúc nào; Quản trị xem và xuất Excel được.
  - **Sao lưu mã hóa AES-256** bằng mật khẩu sao lưu riêng (file `.backup.enc`).
- **Nền đồng bộ (chưa gửi dữ liệu đi đâu):**
  - Mọi bản ghi có phiên bản, thời điểm, người sửa và mã thiết bị; xóa để lại tombstone; có hàng chờ thay đổi.
  - Có giao diện `SyncTransport` để sau này nối máy chủ đám mây hoặc máy chủ nội bộ.
- SQLite **schema 4**, tự nâng khi mở. Định dạng sao lưu vẫn là 3; tài khoản và nhật ký không nằm trong bản sao lưu.
- Bản 0.3.0 trở về trước không đọc được file sao lưu `.enc`. Nếu cần mở bằng bản cũ, chọn *Không mã hóa* khi sao lưu.

Chi tiết: [Tài khoản và bảo mật](docs/BAO-MAT.md), kể cả các giới hạn (database trên máy chưa mã hóa, không có cửa sau khi mất mật khẩu Quản trị), và [Khuôn mẫu đồng bộ](docs/SYNC.md).

## Mới trong 0.3.0 Beta — tệp đính kèm

Từ 0.3.0, các bản 0.x phát hành như **bản chính thức có nhãn Beta** trên GitHub (không còn Pre-release), nên kể cả khi tắt **Bao gồm bản thử nghiệm** vẫn nhận được. App hiện “Beta” cạnh số phiên bản.

- **Tệp đính kèm:** **Thiết bị → chọn thiết bị → Tệp đính kèm → Thêm tệp**. Nhận PDF, ảnh (JPG/PNG/WEBP/HEIC), Word, Excel; tối đa 25 MB mỗi tệp. Đặt tên hiển thị, ghi chú và gắn với một hạng mục hoặc công việc trong sổ bảo trì. Bấm vào tệp để mở bằng ứng dụng mặc định; menu có **Lưu bản sao**, **Sửa thông tin**, **Xóa tệp**. Xóa hạng mục/công việc không xóa tệp (tệp chuyển về thiết bị); xóa thiết bị thì xóa cả tệp của thiết bị đó.
- Tệp được lưu trong database (SQLite **schema 3**, tự nâng khi mở). Sao lưu chuyển sang **ZIP định dạng 3** (`backup.json` + tệp đính kèm); vẫn khôi phục được JSON định dạng 1/2, kể cả các bản tự động của 0.2.0. Khôi phục bản 1/2 sẽ thay toàn bộ dữ liệu, nên tệp đính kèm hiện có cũng bị thay (đã có bản tự lưu trước khi khôi phục).
- Sao lưu tự động giữ tối đa 10 bản và tối đa khoảng 500 MB, luôn giữ 2 bản mới nhất. Sao lưu trước cập nhật OTA cũng là ZIP kèm tệp.
- Bản 0.2.0 trở về trước không đọc được sao lưu ZIP; giữ bản sao lưu cũ nếu cần quay lại.

## Mới trong 0.2.0

Cập nhật từ 0.1.4 qua **Cài đặt → Cập nhật ứng dụng** (giữ **Bao gồm bản thử nghiệm** bật). Không đổi schema SQLite (vẫn 2) và định dạng sao lưu (vẫn 2).

- **Hàng chờ Cần xác nhận:** Tổng quan hiện số mốc cần xác nhận; bấm **Xác nhận** để lọc riêng. Mỗi mốc có **Xác nhận dữ liệu**: xem trạng thái sau xác nhận, rồi chọn **Xác nhận đúng** (giữ nguyên hạn, ghi ngày xác nhận vào ghi chú) hoặc **Sửa hạn**. Theo dõi hạn có thêm bộ lọc **Chỉ mốc cần xác nhận**.
- **Tự sao lưu xoay vòng:** khi mở app, nếu đã quá chu kỳ (mặc định 7 ngày, chỉnh trong Cài đặt), app lưu một bản JSON vào `backups/auto` trong thư mục dữ liệu và giữ 10 bản gần nhất. Database trống thì bỏ qua để không đẩy mất bản có dữ liệu. Khôi phục bằng **Dữ liệu & báo cáo → Khôi phục từ bản sao lưu tự động**. Mọi lần khôi phục đều tự lưu dữ liệu hiện tại trước; không lưu được thì dừng. Bản tự động nằm cùng máy, nên vẫn phải sao lưu ra ngoài; nhắc trên Tổng quan chỉ tính bản sao lưu ra ngoài.
- **Kế hoạch đến hạn theo kỳ:** **Dữ liệu & báo cáo → Xuất kế hoạch đến hạn** cho tháng này/tháng sau/quý này/quý sau. Gom theo đơn vị thực hiện, có thể kèm mục quá hạn chưa xử lý, thêm sheet **Tổng hợp** theo đơn vị và chi phí lần trước để tham khảo. Mốc cần xác nhận được xếp theo ngày gốc và ghi rõ; mục chưa có ngày không đưa vào kế hoạch.
- **Tự kiểm tra cập nhật (mặc định tắt):** bật trong **Cài đặt → Cập nhật ứng dụng**. Khi mở app, tối đa 1 lần/ngày, app chỉ báo có bản mới trên Tổng quan và thanh điều hướng; tải/cài vẫn do người dùng bấm. Tùy chọn **Bao gồm bản thử nghiệm** nay được lưu lại.

## Cập nhật qua GitHub (từ 0.1.4)

Repo hiện **Public**. Cài đè 0.1.4 một lần từ Releases, rồi dùng **Cài đặt → Cập nhật ứng dụng → Kiểm tra cập nhật → Tải bản cập nhật → Cài đặt bản cập nhật** cho các bản sau. Từ 0.3.0 các bản Beta không còn là Pre-release; với 0.1.4–0.2.0 cần giữ **Bao gồm bản thử nghiệm** bật. App xác minh bộ cài và tự sao lưu toàn bộ dữ liệu trước khi mở trình cài; không cài nếu xác minh/sao lưu lỗi. Android có thể hỏi quyền cài ứng dụng từ EquipmentManager. Windows hỗ trợ EXE và ZIP tại thư mục đang dùng, đóng app để thay tệp rồi mở lại.

OTA chỉ dùng mạng khi bạn chọn kiểm tra/tải. Không gửi dữ liệu thiết bị lên GitHub và không cần token. Xem [hướng dẫn OTA, sao lưu và xử lý lỗi](docs/OTA-GITHUB.md).

## Lịch sử bảo trì / sửa chữa (từ 0.1.3)

Mở **Thiết bị → chọn thiết bị → Lịch sử bảo trì / sửa chữa → Ghi công việc** để ghi lại việc đã làm, gồm bảo dưỡng hoặc sửa chữa, nội dung, ngày thực hiện, chi phí, đơn vị và chi tiết. Có thể sửa/xóa các công việc nhập tay, tìm kiếm, lọc theo loại/năm và xem tổng chi phí đã ghi. Các lần hoàn thành hạng mục bảo dưỡng/sửa chữa cũ cũng xuất hiện trong sổ; chúng vẫn giữ nguyên lịch sử gốc. Ghi công việc nhập tay không gia hạn hay hoàn thành hạng mục.

Báo cáo **Danh sách hạng mục và lịch sử thực hiện** có thêm sheet **Bảo trì sửa chữa**. Sheet này lọc theo đơn vị và trạng thái quản lý thiết bị; bộ lọc trạng thái hạn chỉ áp dụng cho các sheet hạng mục/lịch sử hoàn thành.

Bản 0.1.3 thay logo, giảm chuyển động và giảm tính toán lặp ở danh sách thiết bị. Xem [thay đổi đầy đủ](CHANGELOG.md). Để nâng từ bản cũ, sao lưu rồi cài đè APK/EXE; giữ cùng khóa Android và không gỡ app cũ. Database tự nâng schema lên 2; vẫn khôi phục được backup phiên bản 1. Backup mới dùng định dạng 2 và cần app 0.1.3 trở lên; nếu cần quay về app cũ, dùng bản sao lưu đã tạo trước nâng cấp.

Logo gốc ở `assets/brand/logo.svg`; tạo lại PNG/ICO bằng `flutter test tool/generate_brand_test.dart`.

## Cài và sử dụng

1. Mở [Releases](https://github.com/CuongTDSE172527/EquipmentManager/releases), tải bản mới nhất sau khi workflow thành công.
2. Windows: chạy `EquipmentManager-<phiên-bản>-windows-setup.exe`. Nếu SmartScreen báo ứng dụng chưa được nhận diện, kiểm tra đúng repo này, chọn **More info / Thông tin khác → Run anyway / Vẫn chạy**. Bản hiện tại chưa ký số Windows. Nếu máy cơ quan chặn bằng chính sách, liên hệ quản trị viên. Bộ cài và ZIP kèm thư viện Visual C++ cần thiết.
3. Windows không cài đặt: giải nén toàn bộ ZIP vào thư mục cố định, mở `EquipmentManager.exe`. Giữ nguyên các DLL và thư mục `data` đi kèm. Dữ liệu người dùng nằm trong thư mục ứng dụng của tài khoản Windows, không nằm cạnh EXE.
4. Android: tải APK, cho phép cài từ ứng dụng tải tệp khi điện thoại hỏi, rồi cài đặt. Những lần sau cài APK mới đè lên bản cũ với cùng khóa ký. Không gỡ bản cũ nếu chưa sao lưu.
5. Mở **Dữ liệu & báo cáo → Tải mẫu nhập Excel**, điền bảng Theo dõi / Phụ lục rồi nhập. Có thể chọn nhiều file cùng lúc. Sửa mọi lỗi và chọn cách nhập/ghép cho từng dòng trong bản xem trước. Có thể lưu báo cáo đối chiếu trước khi nhập.
6. Trong **Cài đặt**, chỉnh tên cơ quan, tổ/đội, số ngày báo trước, giờ nhắc; bật thông báo và bấm **Gửi thông báo thử**.
7. Sao lưu ít nhất mỗi tháng và trước khi đổi máy/khôi phục. Giữ bản sao lưu ở ổ khác hoặc nơi được đơn vị cho phép.

Các ô thống kê đếm **hạng mục**, riêng Tổng thiết bị đếm thiết bị đang sử dụng. Thiết bị đã bàn giao, chuyển tăng cường hoặc ngừng sử dụng không được đưa vào thống kê/cảnh báo; dùng bộ lọc Trạng thái quản lý để xem lại. Windows có Ctrl+N thêm mới, Ctrl+F tìm kiếm; bảng hạng mục phân trang 10 dòng và sắp xếp bằng tiêu đề cột.

Hạn `05/2026` nghĩa là hết ngày 31/05/2026. Ô trống là **Cần cập nhật**, không phải Còn hạn. “ACV mua tập trung” và “Không áp dụng” không cảnh báo. Mỗi thao tác Gia hạn/Hoàn thành ghi một lịch sử, cùng ngày thực hiện, chi phí và đơn vị. Với bảo hiểm/kiểm định, kỳ tiếp tính từ hạn cũ; bảo dưỡng/sửa chữa/khác tính từ ngày thực hiện. Chu kỳ mặc định 0; người dùng phải nhập chu kỳ thực tế, ứng dụng không đoán từ tài liệu.

## Nhắc hạn khi đóng ứng dụng

Android dùng AlarmManager gọi Dart nền, đọc SQLite và tính số quá hạn/sắp đến hạn vào mỗi lần chạy; không cần mở màn hình ứng dụng. Callback đặt lịch cho ngày tiếp theo và có đăng ký khởi động lại sau reboot. Android 13+ cần quyền thông báo; quyền Báo thức/lời nhắc giúp chạy sát giờ. Khi không có quyền báo thức chính xác, hệ điều hành có thể nhắc trễ. Buộc dừng, thu hồi quyền hoặc hạn chế pin của hãng máy có thể ngăn nhắc nền: mở lại ứng dụng, bật quyền và kiểm tra thông báo thử. Thay đổi ngày/giờ hệ thống: mở lại ứng dụng để đăng ký lại lịch.

Windows đăng ký Task Scheduler theo tài khoản hiện tại, gọi `EquipmentManager.exe --notify-only` mà không hiện cửa sổ, có lịch hằng ngày và khi đăng nhập. Tác vụ kiểm tra bù sau giờ đã chọn, chống gửi lặp trong cùng ngày. Máy phải đang bật, bạn đã đăng nhập và Windows cho phép thông báo; máy tắt hoặc chế độ tập trung có thể khiến thông báo không xuất hiện đúng lúc. Sau khi chuyển thư mục ZIP hoặc chuyển máy, vào Cài đặt tắt/bật nhắc hạn để đăng ký lại. Gỡ bộ cài sẽ xóa tác vụ nhắc, giữ dữ liệu người dùng.

**Phải nghiệm thu trên thiết bị thật:** đặt giờ nhắc vài phút sau, đóng cửa sổ / vuốt ứng dụng khỏi màn hình gần đây, chờ nhận thông báo; bấm thông báo phải mở danh sách cảnh báo. Thử lại sau khởi động máy và khi không cấp quyền báo thức chính xác. Unit test và CI build không thay thế kiểm tra quyền/chính sách pin của từng máy.

## Mã nguồn và kiểm tra

Flutter **3.47.9**, Dart đi kèm SDK; phiên bản thư viện khóa trong `pubspec.lock`.

```text
lib/domain/     Model, lịch ngày/tháng, trạng thái, gia hạn, phân tích nhập liệu
lib/data/       Drift/SQLite, quan hệ, giao dịch, migration, sao lưu
lib/services/   Đọc/ghi Excel/CSV, thông báo, vị trí dữ liệu
lib/ui/         Màn hình, biểu mẫu, bộ lọc, danh mục, đăng nhập, tài khoản
lib/sync/       Khuôn mẫu đồng bộ (SyncTransport, SyncEngine)
test/          Nghiệp vụ, repository, nhập/xuất, widget desktop/điện thoại
installer/     Inno Setup, bản dịch tiếng Việt, gỡ lịch nhắc
tool/          Mẫu Excel, phiên bản, kiểm tra nguồn cục bộ, thiết lập ký
```

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool integration_test
flutter analyze --fatal-infos
flutter test --coverage
dart run tool/generate_templates.dart
```

Chỉ chạy test/analyze trên máy phát triển; APK và bộ cài được build bằng GitHub Actions. Mở `EquipmentManager.code-workspace` để làm việc riêng với dự án này. Trên Windows, Flutter có thể yêu cầu Developer Mode để tạo symlink plugin; đó là yêu cầu môi trường phát triển, không cần cho người cài bản phát hành. Script `tool/flutter.ps1` dành cho SDK cục bộ của workspace này; các máy khác dùng lệnh `flutter` trong PATH.

Database dùng khóa ngoại xóa dây chuyền, WAL và busy timeout. Hoàn thành hạng mục + ghi lịch sử và nhập dữ liệu đều nằm trong giao dịch. Khôi phục kiểm tra dữ liệu trước, rollback toàn bộ nếu có lỗi. Dữ liệu JSON sao lưu có `format`/`version` để từ chối định dạng không hỗ trợ.

## Phát hành tự động

Repo hiện **Public** theo lựa chọn của chủ repo để OTA đọc Release không cần tài khoản/token. Dữ liệu thật và khóa ký vẫn ở ngoài Git trong `private/`. Push/PR vào `main` chạy format, analyze, test và build thử hai nền tảng. Tag hoặc workflow phát hành cũng chạy lại các kiểm tra này; chỉ tạo Release khi cả APK và Windows thành công.

```sh
git add .
git commit -m "Mô tả thay đổi"
git push origin main
git tag v0.1.5
git push origin v0.1.5
```

Trong GitHub → Actions → **Phát hành EquipmentManager → Run workflow**, có thể nhập phiên bản để build thử; để **Tạo Release** tắt nếu chỉ muốn tải artifacts thử. Khi chạy bằng tag, phiên bản luôn lấy từ tag. APK release phải có khóa ký; thiếu Secrets thì job thất bại, không dùng khóa debug.

`versionCode = major × 1.000.000 + minor × 1.000 + patch` (minor, patch tối đa 999). Luôn phát hành phiên bản tăng theo thứ tự số, không tái sử dụng tag cũ; workflow từ chối phiên bản không lớn hơn các Release đã có. Bản v0.1.0 có versionCode 1000, v0.1.1 là 1001. Windows dùng cùng versionName từ tag, số build dùng bộ đếm workflow để phù hợp trường phiên bản của Windows. Artifacts gồm APK đã ký, EXE cài đặt, ZIP đầy đủ và mẫu Excel. Ghi chú Release tự sinh từ commit/PR.

Xuất bản yêu cầu tag đã có trên GitHub; thường chỉ cần push tag như trên. Nếu các job checks/android/windows đều thành công nhưng bước tạo Release gặp lỗi, có thể chạy **Hoàn tất phát hành từ artifacts đã kiểm tra** với ID lần chạy và phiên bản. Workflow này xác minh artifacts thuộc đúng SHA của tag và cả ba job bắt buộc đều qua trước khi xuất bản; không cần build lại hoặc cấp token cá nhân.

## Khóa ký Android và GitHub Secrets

Khóa riêng của bản đầu đã được tạo trong `private/signing` trên máy triển khai, và 4 Secrets đã được cấu hình sau khi chủ repo cho phép. **Sao lưu cả `equipmentmanager.keystore` và `signing-credentials.json` ngay** vào nơi an toàn (ví dụ kho mật khẩu và ổ lưu trữ mã hóa). Không đẩy thư mục này lên Git, không đính kèm khóa trong Release. Mất khóa thì không cập nhật đè lên APK đã cài được. GitHub Secrets không cho tải lại giá trị gốc để làm bản sao lưu.

Nếu tự thiết lập ở repo khác:

1. Cài JDK 17 có `keytool` (chỉ cần khi tạo khóa, không cần Android Studio).
2. Tạo khóa một lần; nhập mật khẩu khi lệnh hỏi:

   ```powershell
   keytool -genkeypair -keystore equipmentmanager.keystore -storetype PKCS12 -alias equipmentmanager -keyalg RSA -keysize 3072 -validity 10950
   ```

3. Chuyển nội dung keystore thành base64 trong PowerShell:

   ```powershell
   [Convert]::ToBase64String([IO.File]::ReadAllBytes((Resolve-Path .\equipmentmanager.keystore))) | Set-Clipboard
   ```

4. Repo → Settings → Secrets and variables → Actions → New repository secret. Tạo:

   | Tên | Giá trị |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | Chuỗi base64 vừa sao chép |
   | `KEYSTORE_PASSWORD` | Mật khẩu keystore |
   | `KEY_ALIAS` | `equipmentmanager` |
   | `KEY_PASSWORD` | Mật khẩu khóa; với PKCS12 dùng cùng mật khẩu keystore |

5. Xóa nội dung clipboard, lưu bản sao khóa và mật khẩu an toàn. Chỉ người tin cậy được quyền sửa/chạy workflow có Secrets. Không thay khóa giữa các bản cập nhật.

## Tài liệu nguồn và dữ liệu thật

Tài liệu Word được xử lý cục bộ để lập bản đối chiếu trong `private/`. Không nhúng dữ liệu nguồn vào mã, mẫu Excel hay Git. Giữ một bản Excel nguyên trạng, lập bản sửa riêng sau khi chủ dữ liệu xác nhận. Các dòng sai cột/ngày/năm bị chặn; mọi liên kết thiết bị phải được duyệt trước khi nhập. Báo cáo duyệt, SQLite kiểm thử và bản sao lưu có dữ liệu thật chỉ nằm trong `private/`, không nằm trong Release.

Workflow **Kiểm tra nhắc nền Android** chạy tay trên emulator API 26 và 33, dùng dữ liệu giả. Harness đặt alarm, host đóng tiến trình ứng dụng, rồi kiểm tra callback `dailyReminder` thực sự đăng thông báo tổng hợp. Harness dùng điểm vào riêng, không được phát hành. Kết quả/log kiểm thử nằm trong artifacts của workflow này. Vẫn cần kiểm tra quyền, chế độ pin và bấm thông báo trên điện thoại sử dụng thực tế.

Phụ thuộc chính: Drift/SQLite, excel (MIT), csv, flutter_local_notifications, android_alarm_manager_plus, file_picker, intl. `installer/Vietnamese.isl` lấy từ [bản dịch cộng đồng của Inno Setup](https://github.com/jrsoftware/issrc/blob/main/Files/Languages/Unofficial/Vietnamese.isl), giữ nguyên chú thích tác giả.
