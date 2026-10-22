# VNode PHP Updaters

Hai script Bash độc lập để kiểm tra và cập nhật PHP theo từng control panel. Mỗi script chỉ hỗ trợ đúng panel ghi trong tên và yêu cầu quyền `root`.

## DirectAdmin

Script `vnode-direct-php-updater` rà package PHP đã cài qua RPM/APT, đối chiếu phiên bản mới nhất trong kho, chỉ hiện package cần cập nhật, hỏi xác nhận rồi cập nhật và xác minh kết quả. Script không gọi DirectAdmin CustomBuild.

PHP source-managed trong `/usr/local/phpXX` được nhận diện riêng. Vì không sử dụng CustomBuild, script không tự build hoặc thay thế các runtime source-managed; nếu chúng cần cập nhật, script nêu phiên bản đối chiếu rồi dừng trước khi cập nhật package nào.

Chạy trực tiếp trên máy chủ:

```bash
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT && curl -fsSL "https://raw.githubusercontent.com/vnodecloud/vnode-php-panel-updater/main/vnode-direct-php-updater" -o "$tmp" && bash "$tmp"
```

## CyberPanel

Script `vnode-cyberpanel-php-updater` rà runtime LiteSpeed PHP dưới `/usr/local/lsws/lsphpXX`, đối chiếu các package `lsphp` đã cài qua RPM/APT, chỉ hiện package cần cập nhật, hỏi xác nhận rồi cập nhật và xác minh kết quả. Các runtime không thuộc package manager khiến script dừng trước khi thay đổi package.

Chạy trực tiếp trên máy chủ:

```bash
tmp="$(mktemp)" && trap 'rm -f "$tmp"' EXIT && curl -fsSL "https://raw.githubusercontent.com/vnodecloud/vnode-php-panel-updater/main/vnode-cyberpanel-php-updater" -o "$tmp" && bash "$tmp"
```

## Hành vi chung

- Hiển thị tiến trình bằng tiếng Việt và thông tin hệ điều hành.
- Chỉ hiển thị package PHP có phiên bản mới hơn trong kho đã cấu hình.
- Không cập nhật nếu người vận hành không xác nhận.
- Chỉ cập nhật package PHP liên quan đến panel; không chạy nâng cấp toàn hệ điều hành.
- Ghi log trình quản lý package vào `/var/log/vnode-direct-php-updater.log` hoặc `/var/log/vnode-cyberpanel-php-updater.log`.
- Cần Bash, quyền `root`, `curl` trên máy chạy lệnh tải script, và APT hoặc RPM với DNF/YUM.

Để kiểm tra nội dung trước khi chạy, tải script về máy chủ và đọc file thay vì dùng lệnh chạy nhanh. Hai script tải từ nhánh `main`; có thể ghim URL vào Git tag/release khi cần chạy một phiên bản cố định.
