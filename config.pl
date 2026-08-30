# =========================================================================
# CẤU HÌNH TRUNG TÂM TỐI ƯU HÓA HỆ THỐNG SBUILD THẾ HỆ MỚI (UNSHARE)
# =========================================================================
$chroot_mode = 'unshare';
$build_dep_resolver = 'apt';

$unshare_mmdebstrap_auto_create = 1; 
$unshare_mmdebstrap_keep_tarball = 1;

# 1. ĐỌC CẤU HÌNH ĐỘNG TỪ BIẾN MÔI TRƯỜNG DO SCRIPT BASH TRUYỀN VÀO
my $use_lto     = $ENV{'LTO'} // "0";
my $version_tag = $ENV{'VERSION_TAG'} // "v3"; 
my $base_flag   = $ENV{'OPT_FLAG'} // "O3"; 

my $opt_flags;
my $ld_flags;
my $rust_flags; 
my $deb_maint_options;

# 2. TỰ ĐỘNG PHÂN TÍCH KIẾN TRÚC THEO VERSION_TAG
my $march_flag;
if ($version_tag eq "v3") {
    $march_flag = "-march=x86-64-v3 -mtune=tigerlake -msha -maes -mpclmul -mrdrnd -mrdseed -mfsgsbase -mfxsr -mxsave -mxsaveopt -mxsavec -mxsaves -mclflushopt -mclwb -mshstk -mvaes -mvpclmulqdq -mgfni -mno-avx512f -mno-avx512vl -mno-avx512bw -mno-avx512dq -mno-avx512cd -mno-avx512ifma -mno-avx512vbmi -mno-avx512vbmi2 -mno-avx512vnni -mno-avx512bitalg -mno-avx512vpopcntdq -mno-avx512vp2intersect -mprefer-vector-width=256";
    $rust_flags = "-C target-cpu=x86-64-v3 -C llvm-args=-mcpu=tigerlake -C target-feature=+aes,+pclmulqdq,+rdrand,+rdseed,+fsgsbase,+fxsr,+xsave,+xsaveopt,+xsavec,+xsaves,+clflushopt,+clwb,+shstk,+vaes,+vpclmulqdq,+gfni,-avx512f,-avx512vl,-avx512bw,-avx512dq,-avx512cd,-avx512ifma,-avx512vbmi,-avx512vbmi2,-avx512vnni,-avx512bitalg,-avx512vpopcntdq,-avx512vp2intersect";
}
elsif ($version_tag eq "v4") {
    $march_flag = "-march=native -mprefer-vector-width=512";
    $rust_flags = "-C target-cpu=native"; 
}
else {
    $march_flag = "-march=x86-64-$version_tag -mtune=tigerlake";
    $rust_flags = "-C target-cpu=x86-64-$version_tag -C llvm-args=-mcpu=tigerlake";
}

# 3. XỬ LÝ LTO VÀ ĐỒNG BỘ CỜ CHO CẢ LINKER VÀ RUST
if ($use_lto eq "1") {
    $opt_flags  = "-$base_flag $march_flag -flto=auto -fuse-linker-plugin";
    $ld_flags   = "-Wl,-O1 -Wl,--as-needed -flto=auto";
    $rust_flags = "$rust_flags -C linker-plugin-lto"; 
    $deb_maint_options = "optimize=+lto";
} else {
    $opt_flags  = "-$base_flag $march_flag";
    $ld_flags   = "-Wl,-O1 -Wl,--as-needed";
    $deb_maint_options = "optimize=-lto";
}

# 4. ÁP DỤNG ĐỒNG BỘ VÀO MÔI TRƯỜNG SBUILD
my $custom_append = $ENV{'CUSTOM_CFLAGS_APPEND'} // "";
if ($custom_append ne "") {
    $opt_flags = "$opt_flags $custom_append";
}

$build_environment = {
    'DEB_CFLAGS_APPEND'       => $opt_flags,
    'DEB_CXXFLAGS_APPEND'     => $opt_flags,
    'DEB_LDFLAGS_APPEND'      => $ld_flags,
    'RUSTFLAGS'               => $rust_flags, 
    'DEB_BUILD_MAINT_OPTIONS' => $deb_maint_options,
    'CMAKE_CXX_SCAN_FOR_MODULES' => "OFF",
};

if ($ENV{'DEB_BUILD_OPTIONS'}) { $build_environment->{'DEB_BUILD_OPTIONS'} = $ENV{'DEB_BUILD_OPTIONS'}; }
if ($ENV{'DEB_BUILD_PROFILES'}) { $build_environment->{'DEB_BUILD_PROFILES'} = $ENV{'DEB_BUILD_PROFILES'}; }

# =========================================================================
# 🌟 ĐOẠN KHẮC PHỤC: TỰ ĐỘNG KHỞI TẠO REPO ĐỘNG CHO CHẾ ĐỘ UNSHARE
# =========================================================================
# 5. Khai báo liên kết thư mục local-repo từ máy Host vào container ảo
our $bindmounts = [ "$ENV{HOME}/local-repo:/local-repo" ];

# 6. Chèn trực tiếp cấu hình danh sách Repo sạch thông qua lệnh thực thi Hook an toàn
our $chroot_setup_commands = [
    # Ghi đè file Pin cho glibc / apt preference
    'printf "Package: *\nPin: origin \"\"\nPin-Priority: 1001\n" > /etc/apt/preferences.d/pin-glibc',
    
    # Khởi tạo danh sách repo nền cho Debian Trixie (Đảm bảo đầy đủ components)
    'echo "deb http://deb.debian.org/debian trixie main non-free-firmware contrib non-free" > /etc/apt/sources.list.d/trixie.list',
    'echo "deb-src http://deb.debian.org/debian trixie main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/trixie.list',
    'echo "deb http://deb.debian.org/debian-security trixie-security main non-free-firmware contrib non-free" >> /etc/apt/sources.list.d/trixie.list',
    'echo "deb-src http://deb.debian.org/debian-security trixie-security main non-free-firmware contrib non-free" >> /etc/apt/sources.list.d/trixie.list',
    
    # Kiểm tra biến môi trường để nạp repo Backports từ ma trận JSON
    $ENV{'IS_BP'} eq "1" ? (
        'echo "deb http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware" > /etc/apt/sources.list.d/bp-sources.list',
        'echo "deb-src http://deb.debian.org/debian trixie-backports main contrib non-free non-free-firmware" >> /etc/apt/sources.list.d/bp-sources.list'
    ) : (),

    # Kiểm tra và nạp danh sách các repo phụ (extra_repos) hoặc trỏ về kho local-repo mặc định
    $ENV{'MATRIX_EXTRA_REPOS'} ne "" ? (
        'echo "' . $ENV{'MATRIX_EXTRA_REPOS'} . '" > /etc/apt/sources.list.d/local-repo.list'
    ) : (
        'echo "deb [trusted=yes] file:///local-repo ./" > /etc/apt/sources.list.d/local-repo.list'
    ),

    # Khởi chạy chuỗi lệnh setup mở rộng (Pin gói, update nâng cao từ file JSON)
    $ENV{'MATRIX_CHROOT_SETUP'} ne "" ? $ENV{'MATRIX_CHROOT_SETUP'} : 'apt-get update'
];

$unshare_mmdebstrap_keep_tarball = 1;
if ($ENV{'SBUILD_TMPDIR'}) { $unshare_tmpdir_template = $ENV{'SBUILD_TMPDIR'} . '/tmp.XXXXXXXXXX'; }

1;
