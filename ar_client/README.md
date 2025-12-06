# Memories - AR Photo Album

Transform physical photos into AR experiences with video overlays using **ARCore + Flutter**!

## ✨ Features

- 📸 **AR Video Overlay** - Point your phone at a photo to see videos play on top
- 🔒 **Freeze Frame** - Lock video to screen for comfortable viewing
- 🎬 **Cinematic Effects** - Smooth unfold animations and audio fade
- 📳 **Haptic Feedback** - Feel when photos are detected
- 🎨 **Premium UI** - Rounded video corners, scan guides, and polished design

## 📱 How It Works

1. **Browse Photos**: See AR-enabled photos from Firebase
2. **Tap to Start**: Downloads and caches image/video locally
3. **Point Camera**: ARCore detects the photo in real-time
4. **Watch Video**: AR video overlay plays over detected photo
5. **Freeze Frame**: Lock video to screen for comfortable viewing (solves arm fatigue!)
6. **New Photo**: Automatically unlocks and switches when new photo detected

## 🎯 Quick Start

### 1. Firebase Setup

1. Create a Firebase project at [console.firebase.google.com](https://console.firebase.google.com)
2. Add an Android app with package name `com.example.ar_client`
3. Download `google-services.json` and place it in `android/app/`
4. Enable Firestore Database
5. Generate Firebase options:
   ```bash
   dart pub global activate flutterfire_cli
   flutterfire configure
   ```

### 2. Install & Run

```bash
flutter pub get
flutter run
```

## 🏗️ Architecture

**Hybrid Design: Flutter UI + Native Android AR Engine**

```
┌─────────────────────────────────────────────────┐
│                  Flutter UI                      │
│  (Photo List, Resource Caching, Firebase)       │
└─────────────────┬───────────────────────────────┘
                  │ Method Channel
┌─────────────────▼───────────────────────────────┐
│             Native Android (Kotlin)              │
│  ARCore + SceneView + TextureView Video         │
└─────────────────────────────────────────────────┘
```

## 🚀 Key Features

### AR Experience
- ✅ **ARCore** hardware-accelerated tracking
- ✅ **Real-time** photo detection
- ✅ **Cinematic unfold** animation on detection
- ✅ **Audio fade** in/out effects

### Freeze Frame (New!)
- ✅ **Lock button** to freeze video on screen
- ✅ **Comfortable viewing** - put the photo album down
- ✅ **Auto-unlock** when new photo detected
- ✅ **Accessibility** - bridges AR discovery with video consumption

### Premium UX
- ✅ **Haptic feedback** on detection
- ✅ **Rounded corners** on video (16dp)
- ✅ **Scan guide** overlay with pulse animation
- ✅ **Loading indicators**

## 🛠️ Tech Stack

| Layer | Technology |
|-------|------------|
| UI | Flutter 3.x |
| Backend | Firebase Firestore |
| Media CDN | Cloudinary |
| AR Engine | ARCore + SceneView |
| Video | TextureView + MediaPlayer |
| Styling | CardView (rounded corners) |

## 📝 Project Structure

```
ar_client/
├── lib/
│   ├── main.dart
│   └── src/
│       ├── screens/
│       │   ├── ar_camera_screen.dart
│       │   └── photo_list_screen.dart
│       └── services/
│           ├── firestore_service.dart
│           └── resource_cache_service.dart
│
└── android/app/src/main/
    ├── java/com/example/ar_client/
    │   ├── ARActivity.kt          # AR Engine
    │   └── MainActivity.kt        # Flutter Bridge
    └── res/
        ├── layout/activity_ar.xml
        └── drawable/              # Icons & UI assets
```

## 🧪 Testing

### Requirements
- Android device with ARCore support
- Camera permission
- Photos uploaded via admin dashboard
- Printed photos or high-quality screen display

### Test Flow
1. Launch app → See photo list
2. Tap photo → Wait for download
3. Point at printed photo → Video plays
4. Tap lock button → Video freezes to screen
5. Show new photo → Auto-unlocks and switches

## 📄 License

MIT License - Feel free to use for your projects!

---

**Made with ❤️ using Flutter + ARCore**
