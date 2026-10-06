# ساخت فایل نصب ویدورا روی ویندوز

این بسته کد نسخهٔ ۰.۱.۱۰ و ابزارهای دانلود ویندوز x64 را دارد. فایل نصب نهایی روی ویندوز ساخته می‌شود.

## آماده‌سازی، فقط برای بار اول

۱. ویندوز ۱۰ یا ۱۱ با پردازندهٔ Intel یا AMD داشته باشید و Developer Mode را در Settings فعال کنید.

۲. [Flutter](https://docs.flutter.dev/install/archive) نسخهٔ **3.41.2 برای Windows** را دریافت و مثلاً در `C:\flutter` استخراج کنید. مسیر `C:\flutter\bin` را به PATH اضافه کنید. پس از این کار پنجرهٔ ترمینال را دوباره باز کنید.

۳. [Visual Studio Community یا Build Tools](https://visualstudio.microsoft.com/downloads/) را نصب کنید. گزینهٔ **Desktop development with C++**، ابزارهای MSVC و Windows SDK باید انتخاب شده باشند. Visual Studio Code به‌تنهایی کافی نیست.

۴. [Inno Setup](https://jrsoftware.org/isdl.php) نسخهٔ **6.7 یا جدیدتر** را نصب کنید.

برای بررسی آماده‌بودن محیط، دستور `flutter doctor -v` را اجرا کنید. بخش Windows و Visual Studio باید آماده باشند. اتصال اینترنت برای دریافت وابستگی‌های Flutter در اولین ساخت لازم است؛ ابزارهای دانلود داخل همین بسته هستند.

## ساخت

بسته را کامل از ZIP استخراج کنید؛ مثلاً در `C:\Vidora`. روی **build_windows.cmd** دوبار کلیک کنید. ابتدا ابزارها و آزمون‌ها بررسی می‌شوند و سپس فایل نصب ساخته می‌شود.

اگر Inno Setup را در مسیر دیگری نصب کرده‌اید، در PowerShell از پوشهٔ پروژه اجرا کنید:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/package_windows.ps1 -Iscc 'C:/path/to/ISCC.exe'
```

دو فایل در پوشهٔ `dist` ساخته می‌شوند:

- `Vidora-Setup-Windows-x64-0.1.10.exe`: نصب عادی برنامه برای کاربر فعلی، همراه با میان‌بر و امکان حذف.
- `Vidora-Windows-x64-0.1.10.zip`: نسخهٔ قابل‌حمل. همهٔ محتویات را کنار هم نگه دارید و `local_video.exe` را اجرا کنید.

کامپیوتری که فقط برنامه را استفاده می‌کند به Flutter، Visual Studio، Python یا Inno Setup نیاز ندارد. فایل‌های همراه برنامه را حذف نکنید.
