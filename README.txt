EXAM BROWSER (Flutter - Android + Windows)

CARA PAKAI
1. Ekstrak zip, jalankan setup.bat (butuh Flutter di PATH).
2. Android : jalankan build_apk.bat
   Windows : jalankan build_windows.bat
   (Windows butuh Visual Studio + "Desktop development with C++" dan WebView2 Runtime)

UBAH PENGATURAN
Buka main.dart, bagian ExamConfig:
- exitPin        : PIN pengawas (default 1234, GANTI!)
- maxViolations  : batas pelanggaran sebelum terkunci
- allowedHosts   : daftar situs yang boleh dibuka (whitelist)
- presets        : tombol cepat di halaman awal

PROTEKSI
Android:
- Layar dikunci (screen pinning), tombol home/recent diblokir
- Screenshot & screen recording diblokir (FLAG_SECURE)
- Layar tetap menyala, mode fullscreen immersive
- Keluar aplikasi dicatat sebagai pelanggaran
- Tombol back diblokir
Windows:
- Fullscreen + selalu di atas, tombol close butuh PIN
- Pindah jendela (Alt+Tab) dicatat sebagai pelanggaran
Keduanya:
- Whitelist domain, navigasi ke situs lain diblokir
- Klik kanan, copy/cut, dan shortcut devtools diblokir
- Terlalu banyak pelanggaran -> layar terkunci sampai pengawas memasukkan PIN

BATASAN (jujur)
- Screen pinning Android meminta konfirmasi pengguna. Untuk kunci penuh tanpa
  konfirmasi, aplikasi harus dijadikan Device Owner / lewat MDM.
- Di Windows, tombol Windows dan Ctrl+Alt+Del tidak bisa diblokir dari aplikasi
  biasa; hanya terdeteksi lewat kehilangan fokus.
- Ini lapisan pencegahan, bukan jaminan mutlak. Tetap perlu pengawasan.
