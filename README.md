<div align="center">

# CMD Tasks

**مهام ومشاريع وعادات**

Tasks, projects and habits, all on your phone

`v0.1.0` · Android 7.0+ · no internet permission · no account, no server

</div>

> **Status: first release, NOT yet tested on a physical device.** Screenshots in the PDFs are automated UI test renders with demo data, not device screenshots.

## Download

Open the release page and pick **`cmd-tasks-0.1.0-arm64-v8a.apk`** for most phones (`armeabi-v7a` for older 32-bit phones, `x86_64` for emulators):

**https://github.com/moh500600/cmd-tasks/releases/tag/v0.1.0**

SHA-256 of the arm64-v8a file:

```
1b3182a5ca6ee251c2d19c4769a96230fbd65f2f342829b7c66485dc4bbde225
```

Android will ask you to allow installing from an unknown source. The APK is signed with a new CMD key made for this app.

## Documents

- [Visual README (PDF, 4 pages)](docs/CMD-Tasks-README-visual.pdf)
- [Showcase (PDF, 5 pages, 16:9)](docs/CMD-Tasks-Showcase.pdf)

## ما هو التطبيق

- **المهام** (Tasks): أولويات وتواريخ وتكرار وفئات وبحث.
- **المشاريع** (Projects): تجميع المهام في مشاريع مع نسبة الإنجاز.
- **العادات** (Habits): تتبع العادات اليومية والسلاسل.
- **التقويم** (Calendar): عرض المهام على أيام الشهر.
- **التذكيرات** (Reminders): تنبيهات قبل الموعد وملخص يومي على الجهاز.
- **التقارير** (Reports): إنجاز يومي وأسبوعي ورسم الإنتاجية.
- **المساعد المحلي** (On-device assistant): يفهم أوامر مثل "ذكّرني غدًا" بقواعد محلية، بدون إنترنت.
- **حسابات محلية** (Local accounts): حسابات تعيش على الجهاز فقط وكلمات مرور مجزّأة.

## What it does

- **Tasks**
- **Projects**
- **Habits**
- **Calendar**
- **Reminders**
- **Reports**
- **On-device assistant**
- **Local accounts**

## Privacy and limits

- All data lives in a database on your phone. The release manifest has no INTERNET permission, there is no cloud account, no backend and no hosted AI.
- المزامنة السحابية والخادم أُزيلا. بياناتك لا تغادر الجهاز.
- It installs **next to** the old app (new package id `com.cmdapps.tasks`). It does not replace it and does not move data automatically. Old server data was not touched.
- Sharing between people is done by exporting a file and importing it on the other phone.
- Deleting the app or its data deletes your data. Keep a backup file.
- Not tested on a physical device yet. Report problems in the repository issues.

## Build

Flutter project. CI (`.github/workflows/android.yml`) runs analyze, tests and a release build. The APKs in the release were re-signed locally with the CMD key.

## License

No license has been chosen yet.
