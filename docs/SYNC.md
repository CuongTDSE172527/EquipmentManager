# Khuôn mẫu đồng bộ — từ 0.4.0

0.4.0 **chưa gửi dữ liệu đi đâu**. Bản này chuẩn bị nền dữ liệu và giao diện lập trình, để sau này nối máy chủ đám mây hoặc máy chủ nội bộ mà không phải đổi cấu trúc dữ liệu lần nữa.

## Đã có trong app

- **Mã thiết bị**: bảng `local_meta`, khóa `device_id` (UUID, sinh một lần). Mã này không có trong bản sao lưu, nên hai máy khôi phục cùng một file vẫn có mã khác nhau.
- **Trạng thái từng bản ghi**: bảng `sync_state(entity, id, version, updated_at, updated_by, device_id, deleted, dirty)`.
  - Mỗi lần thêm, sửa hoặc xóa: `version + 1`, `updated_at` theo UTC, `dirty = 1`.
  - Xóa để lại *tombstone* (`deleted = 1`).
  - Xóa thiết bị tạo tombstone cho mọi hạng mục, lịch sử, sổ bảo trì và tệp của thiết bị đó.
- **Đối tượng đồng bộ**, theo thứ tự cha trước con: `catalog`, `equipment`, `item`, `history`, `service`, `attachment`.
- **Không đồng bộ**: tài khoản, nhật ký thao tác, cài đặt của máy (giờ nhắc, giao diện, sao lưu tự động).
- **Khi nâng từ 0.3.0** (schema 3 → 4): mọi bản ghi hiện có được xếp hàng chờ gửi.
- **Khôi phục sao lưu** đặt lại hàng chờ: mọi bản ghi được gửi lại từ đầu. Bản ghi bị xóa *do khôi phục* không tạo tombstone. Vì vậy, nếu máy đã đồng bộ, cần "đồng bộ lại toàn bộ" theo quy trình của máy chủ.
- **Mã nguồn**:
  - `lib/domain/sync_model.dart`: `SyncChange` và quy tắc xung đột.
  - `lib/sync/sync_engine.dart`: `SyncTransport`, `SyncEngine`, `NotConfiguredTransport`.
  - Trong `EquipmentRepository`: `pendingChanges`, `markPushed`, `applyRemote`.
- **Kiểm thử** `test/sync_test.dart` mô phỏng hai máy đồng bộ qua một máy chủ trong bộ nhớ.

## Chu trình

1. **Push**: gửi các thay đổi `dirty`, mỗi lô 200. Máy chủ trả về những thay đổi đã nhận; app chỉ bỏ cờ `dirty` nếu bản ghi chưa bị sửa tiếp trong lúc gửi.
2. **Pull**: nhận các thay đổi sau `cursor` đã lưu, bỏ qua thay đổi do chính máy này tạo, rồi áp dụng. Bản ghi cha và thao tác thêm/sửa được áp dụng trước, thao tác xóa áp dụng sau, để ràng buộc khóa ngoại luôn đúng. `cursor` chỉ được lưu sau khi áp dụng xong.
3. **Xung đột**: *bản ghi mới nhất thắng*.
   - So `updatedAt` (UTC); nếu trùng thời điểm thì so `deviceId`. Mọi máy đều ra cùng một kết quả mà không cần trao đổi thêm.
   - Bản sửa chưa gửi trên máy này mà thua bản mới hơn từ máy khác sẽ được ghi vào báo cáo xung đột và nhật ký thao tác.

## Hợp đồng HTTP đề xuất cho máy chủ

Mọi yêu cầu đi qua HTTPS kèm `Authorization: Bearer <token>`. Khi có máy chủ, tài khoản nên chuyển sang do máy chủ quản lý; tài khoản cục bộ chỉ còn dùng để mở khóa khi ngoại tuyến.

```text
POST /api/v1/sync/push
  { "deviceId": "...", "changes": [SyncChange, ...] }
  → 200 { "accepted": [ { "entity": "...", "id": "...", "version": 3 }, ... ] }

GET  /api/v1/sync/pull?deviceId=...&cursor=<chuỗi do máy chủ cấp>
  → 200 { "changes": [SyncChange, ...], "cursor": "...", "hasMore": false }

PUT  /api/v1/attachments/{id}        (tải tệp riêng, kiểm SHA-256, hỗ trợ tải tiếp)
GET  /api/v1/attachments/{id}
```

`SyncChange` (JSON):

```json
{
  "entity": "equipment", "id": "uuid", "version": 3,
  "updatedAt": "2026-11-11T01:02:03.000Z", "updatedBy": "user-id",
  "deviceId": "uuid", "deleted": false,
  "payload": { "...": "bản ghi như trong file sao lưu" }
}
```

Máy chủ cần làm những việc sau:
- Giữ trạng thái mới nhất của mỗi `(entity, id)` theo cùng quy tắc xung đột.
- Ghi một luồng thay đổi có thứ tự; `cursor` là vị trí trong luồng đó.
- Giữ tombstone đủ lâu, ví dụ 180 ngày, để máy lâu không kết nối vẫn nhận được thao tác xóa.
- Tự kiểm tra quyền theo vai trò, không tin vào phía app.

Khuôn mẫu hiện gửi nội dung tệp đính kèm dạng base64 ngay trong `payload`. Máy chủ thật nên chuyển phần này sang `PUT /attachments` riêng.

## Thêm một cách kết nối

1. Viết lớp hiện thực `SyncTransport`, gồm hai hàm `push` và `pull`, theo hợp đồng ở trên, hoặc qua thư mục mạng nội bộ.
2. Thêm phần cấu hình địa chỉ máy chủ và đăng nhập máy chủ trong *Cài đặt → Quản trị → Đồng bộ*, rồi gọi `SyncEngine(repository, transport).run()`.
3. Viết kiểm thử theo mẫu `test/sync_test.dart` với máy chủ thật hoặc máy chủ giả.
