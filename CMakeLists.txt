cmake_minimum_required(VERSION 3.10)
project(my-dummy-package VERSION 1.0.0 LANGUAGES C)

# Tạo một file thực thi nhỏ từ mã nguồn C
add_executable(my-dummy-binary main.c)

# Định nghĩa vị trí cài đặt file binary sau khi biên dịch xong vào hệ thống
install(TARGETS my-dummy-binary DESTINATION bin)
