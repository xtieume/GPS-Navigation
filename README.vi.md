# GPSNav

GPSNav mô phỏng vị trí cho iOS 16.0 trở lên đã jailbreak, hỗ trợ arm64/arm64e, rootless và rootful. Tác giả: Tieu Me.

## Tính năng và cách dùng

- Ở chế độ **Fixed**, chạm hoặc nhấn giữ bản đồ để chọn tọa độ, sau đó bật **Spoof location**. Với **Random**, điểm đã chọn là tâm; đặt bán kính (mét) và khoảng thời gian (giây) trong **Random**.
- Ở chế độ **Route**, chạm điểm A rồi B. MapKit tìm đường; trong **Speed / route**, chọn đi bộ hoặc ô tô, tốc độ km/h và lặp đảo chiều. Bật giả lập sau khi tải xong tuyến. Chạm tiếp để chọn tuyến mới.
- Tìm địa điểm và chọn kết quả; **Search history** lưu 20 lần tìm gần nhất. **Bookmarks** và **Routes** cho phép lưu, áp dụng và xóa. Trong Settings có danh sách bundle ID không giả lập và thông tin ứng dụng.
- SpringBoard tiếp tục mô phỏng khi ứng dụng ở nền và khôi phục tiến độ sau respring. Bản đồ hiển thị vị trí engine công bố.

## Cài đặt

Chọn gói rootless `iphoneos-arm64` hoặc rootful `iphoneos-arm` phù hợp với jailbreak. Chuyển tệp deb vào thiết bị và cài bằng Sileo hoặc Filza. Respring để nạp tweak vào SpringBoard rồi khởi động lại các ứng dụng cần dùng. Bật tính năng nạp tweak của jailbreak nếu cần. Gỡ bằng trình quản lý gói.

## Giới hạn

- Cần jailbreak và bộ nạp tweak tương thích; đây không phải ứng dụng App Store. Chưa kiểm thử hoạt động trên thiết bị trong quá trình build.
- Chỉ thay thế vị trí qua Core Location manager trong các ứng dụng được nạp tweak; nguồn vị trí khác, daemon, kiểm tra phía máy chủ, hướng la bàn và ứng dụng chặn nạp tweak không bị ảnh hưởng. Ứng dụng có thể phát hiện vị trí giả hoặc dữ liệu không nhất quán.
- Danh sách loại trừ được đọc một lần khi ứng dụng khởi chạy. Sandbox có thể chặn đọc plist, khi đó ứng dụng không được loại trừ; hãy khởi động lại ứng dụng sau khi chỉnh sửa.
- Tìm kiếm và chỉ đường MapKit cần mạng và tùy khu vực. Chế độ ngẫu nhiên nhảy giữa các điểm. Tuyến cập nhật theo giây và có thể đi tắt qua các đoạn rất ngắn.
- Ứng dụng cần quyền riêng của jailbreak để ghi tệp cấu hình ngoài sandbox. Vị trí và tiến độ được lưu riêng trong cùng thư mục preferences để tránh ghi đè cấu hình.

## Build

Cài Xcode với iPhoneOS SDK, Theos tại `~/theos`, cùng `ldid`, GNU make và `dpkg` (`brew install ldid make dpkg`). Chạy trong thư mục không có khoảng trắng:

```sh
export THEOS="$HOME/theos"
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean
make package FINALPACKAGE=1
```

Các gói nằm trong `packages/`. Theos không hỗ trợ khoảng trắng trong đường dẫn dự án; nếu cần, sao chép dự án đến đường dẫn không có khoảng trắng trước khi build. Kiểm thử tính toán tọa độ bằng `cc tests/geo_test.c Shared/Geo.c -lm -o /tmp/gpsnav-geo-test && /tmp/gpsnav-geo-test`.

Giấy phép MIT: [LICENSE](LICENSE).
