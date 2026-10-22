# vNode PHP Panel Updater

Bash script kiểm tra các PHP runtime và package PHP trên máy chủ Linux có control panel, hiển thị bản đang cài cùng bản mới nhất trong kho, rồi chỉ cập nhật sau khi người vận hành xác nhận.

## Chạy nhanh

Trên máy chủ khách hàng, chạy lệnh sau trong terminal tương tác:

```bash
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT && curl -fsSL "https://raw.githubusercontent.com/vnodecloud/vnode-php-panel-updater/main/php-panel-updater.sh" -o "$tmp" && sudo bash "$tmp"
```

Lệnh này tải script vào file tạm rồi chạy bằng `sudo`; file tạm được xóa khi lệnh kết thúc. Cần có `curl` và quyền `sudo`. Có thể tải script, đọc nội dung và kiểm tra trước khi chạy:

```bash
curl -fsSLO "https://raw.githubusercontent.com/vnodecloud/vnode-php-panel-updater/main/php-panel-updater.sh"
less php-panel-updater.sh
sudo bash php-panel-updater.sh
```

Script yêu cầu quyền root và hiển thị câu hỏi xác nhận trước khi cài đặt package. Chỉ trả lời xác nhận khi đã xem danh sách cập nhật và hiểu tác động với máy chủ.

## Chức năng

- Nhận diện hệ điều hành, control panel và web server đang chạy.
- Quét PHP runtime ở các đường dẫn selector phổ biến của panel.
- Liệt kê phiên bản package PHP đang cài và phiên bản mới nhất có trong kho hệ điều hành. Bảng chỉ hiện package có phiên bản trong kho khác bản đang cài.
- Với runtime do aaPanel App Store quản lý và PHP riêng của HestiaCP, dùng updater native tương ứng khi script nhận diện được.
- Cập nhật package qua APT, DNF hoặc YUM sau khi người vận hành xác nhận.
- Hiển thị tiến trình từng bước, xác minh phiên bản sau cập nhật và ghi log chi tiết vào `/var/log/php-panel-updater-*.log`.
- Dừng trước khi cập nhật package nếu phát hiện PHP runtime cài riêng mà chưa có phương thức cập nhật native được script hỗ trợ.

## Control panel nhận diện

DirectAdmin, CyberPanel, aaPanel, VestaCP, CloudPanel, FastPanel, HestiaCP và Webmin. 

## Lưu ý

- Script chỉ quét các đường dẫn PHP đã biết. Runtime được cài ở đường dẫn tùy chỉnh có thể không được phát hiện.
- Các phiên bản mới nhất được xác định theo kho package mà hệ điều hành đang cấu hình. Với PHP do aaPanel quản lý riêng, script tra phiên bản phát hành PHP và xác minh kết quả sau khi updater chạy.
- Lệnh chạy nhanh lấy nội dung hiện tại trên nhánh `main`. Để khách hàng dùng một bản cố định, hãy phát hành GitHub Release/tag và đổi `main` trong URL thành tag, ví dụ `v1.0.0`.
- Chạy script với quyền root có thể thay đổi package và dịch vụ trên máy chủ. Hãy đọc nội dung script và sao lưu máy chủ theo quy trình vận hành của bạn trước khi xác nhận cập nhật.

## Tệp

- `php-panel-updater.sh` — script kiểm tra và cập nhật PHP.
- `README.md` — hướng dẫn sử dụng.
