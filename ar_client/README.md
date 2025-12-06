# Memories

An AR app that brings your photo albums to life. Point your phone at a printed photo and watch the video memory play right on top of it.

Built this because I wanted something like those Harry Potter moving photos, but for real family memories.

## What it does

- Scan any photo from your album and the associated video plays as an AR overlay
- "Freeze Frame" mode lets you lock the video to screen so you don't have to hold your arm up the whole time
- Haptic buzz when it detects a photo
- Smooth animations, rounded corners, the whole premium feel

## The problem it solves

Holding your phone over a photo album for 2+ minutes while watching a video is tiring. The freeze button lets you scan, lock, put the album down, and watch comfortably from the couch.

## Setup

You'll need:

- Flutter SDK
- A Firebase project
- Android device that supports ARCore

```
# Get your google-services.json from Firebase console
# Put it in android/app/

flutter pub get
flutter run
```

## How it's built

Flutter handles the UI and Firebase stuff. The actual AR tracking runs in native Kotlin using ARCore + SceneView. They talk through a method channel.

```
Flutter (Dart)
    |
    | Method Channel
    v
Native Android (Kotlin)
    - ARCore for tracking
    - TextureView for video
    - CardView for rounded corners
```

## Project layout

```
lib/
  main.dart
  src/
    screens/
      ar_camera_screen.dart   # launch screen
      photo_list_screen.dart  # browse photos
    services/
      firestore_service.dart
      resource_cache_service.dart

android/app/src/main/java/.../
  ARActivity.kt    # where the AR magic happens
  MainActivity.kt  # flutter bridge
```

## Tech

- Flutter 3.x
- Firebase Firestore
- Cloudinary (media hosting)
- ARCore + SceneView
- Kotlin

## Notes

- Works best with printed photos, decent lighting
- First scan downloads the video, then it's cached locally
- When you show a new photo, it auto-unlocks from freeze mode and switches

## License

MIT
