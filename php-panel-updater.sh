#!/usr/bin/env bash
set -o pipefail
export LC_ALL=C

progress() { printf '\n[%s] %s\n' "$1" "$2"; }

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then echo "LỖI: hãy chạy script bằng quyền root (sudo $0)." >&2; exit 1; fi
if command -v flock >/dev/null 2>&1; then
    exec 9>/run/lock/php-panel-updater.lock
    flock -n 9 || { echo "LỖI: đang có một phiên script cập nhật PHP khác chạy." >&2; exit 1; }
fi
progress 'BƯỚC 1/8' 'Nhận diện hệ điều hành và control panel'
if [[ -r /etc/os-release ]]; then . /etc/os-release; OS_NAME="${PRETTY_NAME:-${NAME:-Linux}}"; else OS_NAME="Linux (unknown distribution)"; fi

PANEL=""; PANEL_VERSION="unknown"
if [[ -x /usr/local/directadmin/directadmin || -d /usr/local/directadmin/data ]]; then
    PANEL="DirectAdmin"; PANEL_VERSION=""
    for da_version_arg in version v; do
        da_version_output=$(/usr/local/directadmin/directadmin "$da_version_arg" 2>/dev/null | head -n1 || true)
        if [[ -n "$da_version_output" && "$da_version_output" != Usage:* ]]; then PANEL_VERSION="$da_version_output"; break; fi
    done
    [[ -n "$PANEL_VERSION" ]] || PANEL_VERSION="không rõ phiên bản"
elif [[ -d /usr/local/CyberCP ]]; then PANEL="CyberPanel"
elif [[ -d /www/server/panel ]]; then PANEL="aaPanel"
elif [[ -d /usr/local/hestia ]]; then PANEL="HestiaCP"; PANEL_VERSION=$(/usr/local/hestia/bin/v-list-sys-info 2>/dev/null | awk -F': ' '/VERSION/ {print $2; exit}' || true)
elif [[ -d /usr/local/vesta ]]; then PANEL="VestaCP"
elif [[ -d /home/clp/htdocs/app || -x /usr/bin/clpctl ]]; then PANEL="CloudPanel"
elif [[ -d /usr/local/fastpanel2 || -d /usr/local/fastpanel ]]; then PANEL="FastPanel"
elif [[ -d /etc/webmin && ( -f /etc/webmin/miniserv.conf || -f /usr/share/webmin/miniserv.pl ) ]]; then PANEL="Webmin"
fi
if [[ -z "$PANEL" ]]; then echo "Không hỗ trợ: không phát hiện control panel nằm trong danh sách."; exit 2; fi

progress 'BƯỚC 2/8' 'Nhận diện web server'
WEB_SERVER="unknown"
for svc in lsws openlitespeed httpd apache2 nginx; do
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$svc" 2>/dev/null; then
        case "$svc" in lsws|openlitespeed) WEB_SERVER="OpenLiteSpeed";; httpd|apache2) WEB_SERVER="Apache";; nginx) WEB_SERVER="Nginx";; esac; break
    fi
done
if [[ "$WEB_SERVER" == unknown ]]; then
    for proc in lshttpd openlitespeed httpd apache2 nginx; do
        if pgrep -x "$proc" >/dev/null 2>&1; then
            case "$proc" in lshttpd|openlitespeed) WEB_SERVER="OpenLiteSpeed";; httpd|apache2) WEB_SERVER="Apache";; nginx) WEB_SERVER="Nginx";; esac; break
        fi
    done
fi
echo "Hệ điều hành     : $OS_NAME"
echo "Control panel    : $PANEL${PANEL_VERSION:+ ($PANEL_VERSION)}"
echo "Web server       : $WEB_SERVER"

progress 'BƯỚC 3/8' 'Quét PHP runtime trong các đường dẫn panel và selector phổ biến'
declare -a SELECTOR_PATHS=() SOURCE_PATHS=() AA_SOURCE_VERSIONS=() HESTIA_PHP_BIN=() DA_SOURCE_BINS=()
add_runtime() {
    local bin="$1" ver old entry owner rel
    [[ -x "$bin" ]] || return 0
    ver=$("$bin" -n -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null | head -n1)
    [[ -n "$ver" ]] || ver="không rõ phiên bản"
    entry="$ver|$bin"
    for old in "${SELECTOR_PATHS[@]:-}"; do [[ "$old" == "$entry" ]] && return 0; done
    SELECTOR_PATHS+=("$entry")
    owner=""
    rel=$(readlink -f "$bin" 2>/dev/null || printf '%s' "$bin")
    if command -v rpm >/dev/null 2>&1; then owner=$(rpm -qf "$rel" 2>/dev/null || true)
    elif command -v dpkg-query >/dev/null 2>&1; then owner=$(dpkg-query -S "$rel" 2>/dev/null | head -n1 || true); fi
    if [[ "$bin" == /www/server/php/*/bin/php ]]; then
        rel=${bin#/www/server/php/}; rel=${rel%%/*}
        [[ "$rel" =~ ^[0-9]{2}$ ]] && AA_SOURCE_VERSIONS+=("${rel:0:1}.${rel:1:1}|$bin")
        SOURCE_PATHS+=("$ver|$bin|aaPanel App Store")
    elif [[ "$bin" == /usr/local/hestia/php/sbin/hestia-php ]]; then
        HESTIA_PHP_BIN+=("$bin")
        SOURCE_PATHS+=("$ver|$bin|HestiaCP updater")
    elif [[ "$PANEL" == "DirectAdmin" && "$bin" == /usr/local/php*/bin/php ]]; then
        DA_SOURCE_BINS+=("$ver|$bin")
        SOURCE_PATHS+=("$ver|$bin|DirectAdmin PHP source (CustomBuild bị cấm)")
    elif [[ -z "$owner" ]]; then SOURCE_PATHS+=("$ver|$bin|không thuộc package RPM/APT")
    fi
}
for bin in /usr/local/lsws/lsphp*/bin/php /www/server/php/*/bin/php /opt/alt/php*/usr/bin/php /opt/php*/bin/php /usr/local/php*/bin/php /usr/local/hestia/php/sbin/hestia-php /usr/bin/php[0-9].[0-9]; do
    [[ -e "$bin" ]] && add_runtime "$bin"
done
if command -v php >/dev/null 2>&1; then add_runtime "$(command -v php)"; fi
if ((${#SELECTOR_PATHS[@]})); then
    echo "Các PHP runtime có thể dùng trong selector (theo binary/đường dẫn panel):"
    for entry in "${SELECTOR_PATHS[@]}"; do IFS='|' read -r ver path <<< "$entry"; printf '  %-12s %s\n' "$ver" "$path"; done
else echo "Không tìm thấy PHP runtime ở các đường dẫn selector phổ biến."; fi

if ((${#SOURCE_PATHS[@]})); then
    echo "PHP runtime cài từ mã nguồn hoặc do panel quản lý riêng:"
    for entry in "${SOURCE_PATHS[@]}"; do IFS='|' read -r ver path manager <<< "$entry"; printf '  %-12s %-44s %s\n' "$ver" "$path" "$manager"; done
fi

progress 'BƯỚC 4/8' 'Làm mới metadata kho và đối chiếu package PHP'
declare -a PKG_NAMES=() PKG_CURRENT=() PKG_LATEST=() PKG_VERSION=() UPDATE_PKGS=()
declare -a AA_UPDATES=() AA_BEFORE=() AA_LATEST=() HESTIA_UPDATES=() HESTIA_BEFORE=() HESTIA_LATEST=() SOURCE_BLOCKED=()
pkg_version_from_name() {
    local name="$1"
    if [[ "$name" =~ ^lsphp([0-9]{2}) ]]; then echo "${BASH_REMATCH[1]:0:1}.${BASH_REMATCH[1]:1:1}"
    elif [[ "$name" =~ ^(ea-php|alt-php)([0-9])([0-9]) ]]; then echo "${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    elif [[ "$name" =~ ^php([0-9])\.([0-9]) ]]; then echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    elif [[ "$name" =~ ^php([0-9])([0-9])($|-) ]]; then echo "${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    else echo "system"; fi
}
if command -v rpm >/dev/null 2>&1; then
    PM="dnf"; command -v dnf >/dev/null 2>&1 || PM="yum"
    if [[ "$PM" == dnf ]]; then dnf -q makecache --refresh >/dev/null 2>&1 || true; else yum -q makecache >/dev/null 2>&1 || true; fi
    while IFS='|' read -r name current; do
        [[ -n "$name" && "$name" =~ ^(php|php[0-9]|ea-php|alt-php|lsphp[0-9]|remi-php|rh-php) ]] || continue
        if [[ "$PM" == dnf ]]; then latest=$(dnf -q repoquery --available --latest-limit=1 --qf '%{version}-%{release}.%{arch}' "$name" 2>/dev/null | head -n1)
        else latest=$(yum -q --showduplicates list "$name" 2>/dev/null | awk 'NR>1 {v=$2} END{print v}'); fi
        [[ -n "$latest" ]] || latest="$current (không có bản trong kho)"
        PKG_NAMES+=("$name"); PKG_CURRENT+=("$current"); PKG_LATEST+=("$latest"); PKG_VERSION+=("$(pkg_version_from_name "$name")")
        [[ "$latest" != "$current" && "$latest" != *"không có bản trong kho"* ]] && UPDATE_PKGS+=("$name")
    done < <(rpm -qa --qf '%{NAME}|%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -t '|' -k1,1)
elif command -v dpkg-query >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    PM="apt"; apt-get update -qq >/dev/null 2>&1 || true
    while IFS='|' read -r name current; do
        [[ -n "$name" && "$name" =~ ^(php|php[0-9]|libapache2-mod-php|libphp[0-9]|hestia-php$) ]] || continue
        candidate=$(apt-cache policy "$name" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')
        [[ -n "$candidate" && "$candidate" != '(none)' ]] || candidate="$current (không có bản trong kho)"
        PKG_NAMES+=("$name"); PKG_CURRENT+=("$current"); PKG_LATEST+=("$candidate"); PKG_VERSION+=("$(pkg_version_from_name "$name")")
        if [[ "$candidate" != "$current" && "$candidate" != *"không có bản trong kho"* ]]; then
            if [[ "$name" == hestia-php ]]; then HESTIA_UPDATES+=("$name"); HESTIA_BEFORE+=("$current"); HESTIA_LATEST+=("$candidate")
            else UPDATE_PKGS+=("$name"); fi
        fi
    done < <(dpkg-query -W -f='${binary:Package}|${Version}\n' 2>/dev/null | sort -t '|' -k1,1)
else echo "LỖI: đã nhận diện panel nhưng không tìm thấy trình quản lý gói RPM/APT được hỗ trợ."; exit 3; fi

if ((${#AA_SOURCE_VERSIONS[@]})); then
    progress 'BƯỚC 5/8' 'Kiểm tra phiên bản PHP do aaPanel App Store quản lý'
    if [[ "$PANEL" != "aaPanel" ]] || [[ ! -x /www/server/panel/install/install_soft.sh ]] || ! command -v bt >/dev/null 2>&1; then
        SOURCE_BLOCKED+=("Không tìm thấy updater native aaPanel phù hợp cho PHP source đã cài")
    else
        for item in "${AA_SOURCE_VERSIONS[@]}"; do
            IFS='|' read -r minor bin <<< "$item"
            current=$("$bin" -n -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null | head -n1)
            json=$(curl -fsS --max-time 15 "https://www.php.net/releases/index.php?json&version=$minor" 2>/dev/null || true)
            latest=""
            if [[ -n "$json" ]] && command -v python3 >/dev/null 2>&1; then latest=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true); fi
            if [[ -z "$latest" ]]; then SOURCE_BLOCKED+=("Không truy vấn được phiên bản mới nhất cho PHP $minor trong kho công khai"); continue; fi
            printf '\nPHP aaPanel (source) | PHP %s | hiện tại %s | mới nhất trên kho PHP chính thức %s\n' "$minor" "$current" "$latest"
            if [[ "$current" != "$latest" ]]; then AA_UPDATES+=("$minor|$bin"); AA_BEFORE+=("$current"); AA_LATEST+=("$latest"); fi
        done
    fi
fi

if ((${#DA_SOURCE_BINS[@]})); then
    progress 'BƯỚC 5/8' 'Đối chiếu PHP source-managed của DirectAdmin với bản phát hành PHP mới nhất'
    printf '%-12s %-12s %-12s %s\n' 'PHP' 'ĐANG CÀI' 'MỚI NHẤT' 'ĐƯỜNG DẪN'
    printf '%-12s %-12s %-12s %s\n' '------------' '------------' '------------' '----------------------------------------'
    for item in "${DA_SOURCE_BINS[@]}"; do
        IFS='|' read -r current bin <<< "$item"
        if [[ ! "$current" =~ ^([0-9]+\.[0-9]+)\.[0-9]+$ ]]; then
            printf '%-12s %-12s %-12s %s\n' 'không rõ' "$current" 'không rõ' "$bin"
            SOURCE_BLOCKED+=("Không đọc được phiên bản PHP source-managed tại $bin")
            continue
        fi
        minor="${BASH_REMATCH[1]}"
        json=$(curl -fsS --max-time 15 "https://www.php.net/releases/index.php?json&version=$minor" 2>/dev/null || true)
        latest=""
        if [[ -n "$json" ]] && command -v python3 >/dev/null 2>&1; then latest=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version", ""))' 2>/dev/null || true); fi
        if [[ -z "$latest" ]]; then
            printf '%-12s %-12s %-12s %s\n' "$minor" "$current" 'không truy vấn được' "$bin"
            SOURCE_BLOCKED+=("Không tra được phiên bản PHP mới nhất cho PHP $minor tại php.net")
            continue
        fi
        printf '%-12s %-12s %-12s %s\n' "$minor" "$current" "$latest" "$bin"
        if [[ "$current" != "$latest" ]]; then
            SOURCE_BLOCKED+=("DirectAdmin PHP $minor đang ở $current; bản PHP mới nhất là $latest. Đây là PHP source-managed; CustomBuild đang bị cấm nên script không thể cập nhật an toàn runtime này.")
        fi
    done
fi

if ((${#HESTIA_PHP_BIN[@]})) && { [[ "$PANEL" != "HestiaCP" ]] || [[ ! -x /usr/local/hestia/bin/v-update-sys-hestia ]]; }; then
    SOURCE_BLOCKED+=("Không tìm thấy updater native HestiaCP cho PHP riêng của panel")
fi

if ((${#HESTIA_PHP_BIN[@]})); then
    progress 'BƯỚC 5/8' 'Đối chiếu PHP riêng của HestiaCP với updater native'
    for bin in "${HESTIA_PHP_BIN[@]}"; do
        current=$($bin -n -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null | head -n1)
        printf '  Đã phát hiện Hestia PHP %s tại %s; updater native sẽ được gọi và xác minh sau khi xác nhận.\n' "${current:-không rõ}" "$bin"
    done
fi

for entry in "${SOURCE_PATHS[@]}"; do
    IFS='|' read -r ver path manager <<< "$entry"
    [[ "$manager" == "aaPanel App Store" || "$manager" == "HestiaCP updater" || "$manager" == "DirectAdmin PHP source (CustomBuild bị cấm)" ]] && continue
    SOURCE_BLOCKED+=("PHP $ver tại $path không có adapter cập nhật native đã xác thực")
done

progress 'BƯỚC 6/8' 'Hiển thị bảng phiên bản đang cài và bản mới nhất có sẵn'
printf '\nCác package PHP và phiên bản mới nhất trong kho (%s; metadata kho đã làm mới):\n' "$PM"
package_diff_count=0
package_available_count=0
for i in "${!PKG_NAMES[@]}"; do
    [[ "${PKG_LATEST[$i]}" == *"không có bản trong kho"* ]] && continue
    ((package_available_count+=1))
    [[ "${PKG_LATEST[$i]}" != "${PKG_CURRENT[$i]}" ]] && ((package_diff_count+=1))
done
if ((package_diff_count)); then
    printf '%-10s %-32s %-28s %-28s\n' 'PHP' 'PACKAGE' 'ĐANG CÀI' 'MỚI NHẤT TRONG KHO'
    printf '%-10s %-32s %-28s %-28s\n' '----------' '--------------------------------' '----------------------------' '----------------------------'
    for i in "${!PKG_NAMES[@]}"; do
        [[ "${PKG_LATEST[$i]}" != "${PKG_CURRENT[$i]}" && "${PKG_LATEST[$i]}" != *"không có bản trong kho"* ]] || continue
        printf '%-10s %-32s %-28s %-28s\n' "${PKG_VERSION[$i]}" "${PKG_NAMES[$i]}" "${PKG_CURRENT[$i]}" "${PKG_LATEST[$i]}"
    done
elif ((package_available_count)); then
    echo "Các package PHP đã cài đều đang ở phiên bản mới nhất có sẵn trong kho."
    if ((package_available_count < ${#PKG_NAMES[@]})); then echo "Một số package không có phiên bản để đối chiếu trong kho."; fi
elif ((${#PKG_NAMES[@]})); then
    echo "Không có package PHP nào tìm thấy phiên bản đối chiếu trong kho."
else
    if ((${#SELECTOR_PATHS[@]})); then
        echo "Đã phát hiện ${#SELECTOR_PATHS[@]} PHP runtime ở BƯỚC 3, nhưng không có package PHP RPM/APT tương ứng; xem bảng PHP source-managed ở trên."
    else
        echo "Không phát hiện package PHP do trình quản lý gói của hệ điều hành quản lý."
    fi
fi
echo
if ((${#SOURCE_BLOCKED[@]})); then
    progress 'BƯỚC 7/8' 'Kiểm tra khả năng cập nhật đầy đủ trước khi thay đổi hệ thống'
    echo "DỪNG AN TOÀN: chưa thể bảo đảm cập nhật đầy đủ mọi PHP cài từ source, vì:"
    for reason in "${SOURCE_BLOCKED[@]}"; do printf '  - %s\n' "$reason"; done
    echo "Chưa cập nhật package nào. Cần bổ sung adapter native đã kiểm chứng cho các mục trên."
    exit 5
fi
if ((${#UPDATE_PKGS[@]} == 0 && ${#AA_UPDATES[@]} == 0 && ${#HESTIA_UPDATES[@]} == 0)); then echo "Không có bản cập nhật PHP nào."; exit 0; fi
progress 'BƯỚC 7/8' 'Chờ xác nhận cập nhật'
echo "Chỉ cập nhật các PHP runtime được liệt kê. DirectAdmin CustomBuild không được gọi."
read -r -p "Xác nhận cập nhật các phiên bản PHP trên? [y/N] " answer
case "$answer" in y|Y|yes|YES|Yes|c|C|co|Co|CO|có|Có|CÓ) ;; *) echo "Đã hủy; chưa cập nhật PHP nào."; exit 0;; esac

progress 'BƯỚC 8/8' 'Cập nhật PHP theo updater native của panel hoặc package manager'
declare -a BEFORE=()
for pkg in "${UPDATE_PKGS[@]}"; do
    if [[ "$PM" == apt ]]; then BEFORE+=("$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo unknown)")
    else BEFORE+=("$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null || echo unknown)"); fi
done
update_rc=0
for i in "${!HESTIA_UPDATES[@]}"; do
    hestia_log="/var/log/php-panel-updater-hestia-php.log"
    echo "Tiến trình HestiaCP PHP ($((i + 1))/${#HESTIA_UPDATES[@]}): đang gọi updater native; log: $hestia_log"
    /usr/local/hestia/bin/v-update-sys-hestia hestia-php >"$hestia_log" 2>&1 || update_rc=1
    after=$(dpkg-query -W -f='${Version}' hestia-php 2>/dev/null || echo unknown)
    if [[ "$after" != unknown && "$after" == "${HESTIA_LATEST[$i]}" ]]; then
        echo "PHP riêng của HestiaCP: ${HESTIA_BEFORE[$i]} -> $after (đã cập nhật)"
    else
        echo "PHP riêng của HestiaCP: chưa xác nhận cập nhật; xem $hestia_log"
        update_rc=1
    fi
done
for i in "${!AA_UPDATES[@]}"; do
    IFS='|' read -r minor bin <<< "${AA_UPDATES[$i]}"
    aa_log="/var/log/php-panel-updater-aapanel-${minor//./}.log"
    echo "Tiến trình aaPanel PHP ($((i + 1))/${#AA_UPDATES[@]}): đang gọi updater native cho PHP $minor; log: $aa_log"
    if ! bt "update/0/php/$minor" >"$aa_log" 2>&1; then update_rc=1; fi
done
if ((${#UPDATE_PKGS[@]})); then
    package_log="/var/log/php-panel-updater-packages.log"
    echo "Đang cập nhật package PHP; log chi tiết: $package_log"
    if [[ "$PM" == apt ]]; then DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade "${UPDATE_PKGS[@]}" >"$package_log" 2>&1 || update_rc=$?
    elif [[ "$PM" == dnf ]]; then dnf upgrade -y "${UPDATE_PKGS[@]}" >"$package_log" 2>&1 || update_rc=$?
    else yum update -y "${UPDATE_PKGS[@]}" >"$package_log" 2>&1 || update_rc=$?; fi
fi

for i in "${!AA_UPDATES[@]}"; do
    IFS='|' read -r minor bin <<< "${AA_UPDATES[$i]}"
    after=$("$bin" -n -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null | head -n1)
    [[ -n "$after" && "$after" == "${AA_LATEST[$i]}" ]] && echo "PHP aaPanel $minor: ${AA_BEFORE[$i]} -> $after (đã cập nhật đúng bản mới nhất)" || { echo "PHP aaPanel $minor: phiên bản sau cập nhật ($after) chưa khớp bản mới nhất (${AA_LATEST[$i]}); xem /var/log/php-panel-updater-aapanel-${minor//./}.log"; update_rc=1; }
done

progress 'XÁC MINH' 'Đọc lại phiên bản sau cập nhật và lập bảng kết quả'
printf '\nKết quả cập nhật package PHP:\n'
printf '%-10s %-32s %-28s %-28s %-20s\n' 'PHP' 'PACKAGE' 'TRƯỚC' 'SAU' 'KẾT QUẢ'
printf '%-10s %-32s %-28s %-28s %-20s\n' '----------' '--------------------------------' '----------------------------' '----------------------------' '--------------------'
failed=0
for i in "${!UPDATE_PKGS[@]}"; do
    pkg="${UPDATE_PKGS[$i]}"
    if [[ "$PM" == apt ]]; then after=$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null || echo unknown)
    else after=$(rpm -q --qf '%{VERSION}-%{RELEASE}.%{ARCH}' "$pkg" 2>/dev/null || echo unknown); fi
    result="ĐÃ CẬP NHẬT"
    [[ "$after" == "${BEFORE[$i]}" || "$after" == unknown ]] && { result="LỖI/CHƯA ĐỔI"; failed=1; }
    printf '%-10s %-32s %-28s %-28s %-12s\n' "$(pkg_version_from_name "$pkg")" "$pkg" "${BEFORE[$i]}" "$after" "$result"
done
if ((update_rc != 0 || failed)); then echo "Một số cập nhật lỗi hoặc phiên bản không đổi. Hãy kiểm tra file log được nêu phía trên."; exit 4; fi
echo "Đã xác nhận cập nhật thành công các phiên bản PHP được yêu cầu."
