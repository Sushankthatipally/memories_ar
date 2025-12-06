# AR Admin Dashboard - Flutter Web

A comprehensive Flutter Web admin dashboard for managing AR Album clients, photo uploads, video assignments, and client authentication for your studio.

## 🎯 Features

- **Admin Authentication** - Secure login for studio administrators
- **Client Management** - Create and manage client accounts with album assignments
- **Album Creation** - Create albums with unique IDs and client assignments
- **Media Upload** - Upload photos (target images) and videos with automatic mapping
- **Photo-Video Mapping** - Link printed photos to AR videos with unique target IDs
- **Client Access Control** - Role-based access ensuring clients only see their albums
- **Real-time Updates** - Firebase Firestore for instant synchronization
- **Secure Storage** - Firebase Storage for media files with proper access control

## 🏗️ System Architecture

### Database Structure (Firestore)

```
users/
  ├── {clientId}/
  │     ├── name: "Client Name"
  │     ├── email: "client@example.com"
  │     ├── albumID: "album001"
  │     ├── role: "client"
  │     └── createdOn: timestamp
  │
  └── {adminId}/
        ├── email: "admin@studio.com"
        └── role: "admin"

albums/
  └── {albumId}/
        ├── albumName: "Wedding Album"
        ├── owner: "clientId"
        ├── createdBy: "adminId"
        ├── albumCode: "ABC123"
        ├── createdOn: timestamp
        │
        └── photos/ (subcollection)
              ├── {targetId}/
              │     ├── targetID: "p1"
              │     ├── imageURL: "https://..."
              │     ├── videoURL: "https://..."
              │     └── createdOn: timestamp
              │
              └── {targetId}/...
```

## 📋 Prerequisites

- Flutter SDK (3.0.0 or higher)
- Firebase Account
- Firebase CLI (for configuration)
- FlutterFire CLI
- Code editor (VS Code recommended)

## 🚀 Installation & Setup

### Step 1: Install Dependencies

Run the installation script:

**Windows (PowerShell):**

```powershell
.\setup_environment.ps1
```

Or manually:

```powershell
flutter pub get
```

### Step 2: Firebase Project Setup

1. **Create Firebase Project**

   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Click "Add project"
   - Follow the setup wizard

2. **Enable Firebase Services**

   **Authentication:**

   - Navigate to Authentication → Get Started
   - Enable "Email/Password" sign-in method
   - Create an admin user (admin@yourstudio.com)

   **Firestore Database:**

   - Navigate to Firestore Database → Create Database
   - Start in **production mode**
   - Choose your region
   - Deploy these security rules:

   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       // Admin access
       function isAdmin() {
         return request.auth != null &&
                get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'admin';
       }

       // Client access
       function isClient() {
         return request.auth != null &&
                get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'client';
       }

       function isOwner(albumId) {
         return request.auth != null &&
                get(/databases/$(database)/documents/users/$(request.auth.uid)).data.albumID == albumId;
       }

       // Users collection
       match /users/{userId} {
         allow read: if request.auth != null && (isAdmin() || request.auth.uid == userId);
         allow write: if isAdmin();
       }

       // Albums collection
       match /albums/{albumId} {
         allow read: if request.auth != null && (isAdmin() || isOwner(albumId));
         allow write: if isAdmin();

         match /photos/{photoId} {
           allow read: if request.auth != null && (isAdmin() || isOwner(albumId));
           allow write: if isAdmin();
         }
       }
     }
   }
   ```

   **Firebase Storage:**

   - Navigate to Storage → Get Started
   - Start in **production mode**
   - Deploy these security rules:

   ```javascript
   rules_version = '2';
   service firebase.storage {
     match /b/{bucket}/o {
       match /albums/{albumId}/{allPaths=**} {
         allow read: if request.auth != null;
         allow write: if request.auth != null &&
                      request.auth.token.role == 'admin';
       }
     }
   }
   ```

3. **Configure CORS for Storage (localhost testing)**

   Create a `cors.json` file:

   ```json
   [
     {
       "origin": ["*"],
       "method": ["GET", "HEAD", "PUT", "POST", "DELETE"],
       "maxAgeSeconds": 3600
     }
   ]
   ```

   Apply CORS settings:

   ```bash
   gsutil cors set cors.json gs://your-project-id.appspot.com
   ```

### Step 3: FlutterFire Configuration

1. **Install FlutterFire CLI:**

   ```bash
   dart pub global activate flutterfire_cli
   ```

2. **Configure Firebase:**
   ```bash
   flutterfire configure
   ```
   - Select your Firebase project
   - Select platforms (Web, Android, iOS)
   - This creates `lib/firebase_options.dart` automatically

### Step 4: Run the Application

**For Web (Development):**

```bash
flutter run -d chrome
```

**For Web (Release Build):**

```bash
flutter build web
```

The build output will be in `build/web/` directory.

## 👤 Admin Workflow

1. **Login** - Use admin credentials
2. **Dashboard** - View all albums and manage system
3. **Create Album** - Click "Create New Album"
   - Enter album name
   - Enter client details (name, email)
   - System generates unique album ID
4. **Upload Media**
   - Click on an album to edit
   - Upload photo (target image)
   - Upload corresponding video
   - System auto-generates target ID
   - Photo and video are automatically linked
5. **Client Access** - Share credentials with client

## 📱 Client App Integration

When client scans a photo:

1. Client app authenticates user
2. Fetches user's `albumID` from Firestore
3. ARCore detects target and returns `targetID`
4. App queries: `albums/{albumID}/photos/{targetID}`
5. Retrieves `videoURL` and plays AR video

## 🔐 Security Best Practices

1. **Admin User Creation** - Create admin users manually in Firebase Console
2. **Client User Creation** - Implement Cloud Function to create client users (prevents admin logout)
3. **Firestore Rules** - Strictly enforce role-based access
4. **Storage Rules** - Restrict uploads to admin role only
5. **API Keys** - Never commit `firebase_options.dart` to public repos (add to `.gitignore`)

## 📦 Project Structure

```
lib/
├── main.dart                          # App entry point
├── firebase_options.dart              # Firebase configuration (auto-generated)
└── src/
    ├── services/
    │   └── firebase_service.dart      # Core Firebase operations
    └── screens/
        ├── login_screen.dart          # Admin login
        ├── dashboard_screen.dart      # Main dashboard
        ├── create_album_screen.dart   # Album creation & upload
        └── album_editor_screen.dart   # Edit existing albums
```

## 🛠️ Production Deployment

### Cloud Functions (Recommended)

Create a Cloud Function for secure client user creation:

```javascript
const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.createClient = functions.https.onCall(async (data, context) => {
  // Verify admin
  if (!context.auth || context.auth.token.role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Admin only");
  }

  const { email, password, name, albumId } = data;

  // Create user
  const userRecord = await admin.auth().createUser({
    email: email,
    password: password,
  });

  // Set custom claims
  await admin.auth().setCustomUserClaims(userRecord.uid, { role: "client" });

  // Create Firestore document
  await admin.firestore().collection("users").doc(userRecord.uid).set({
    name: name,
    email: email,
    albumID: albumId,
    role: "client",
    createdOn: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { uid: userRecord.uid, message: "Client created successfully" };
});
```

### Hosting on Firebase Hosting

```bash
firebase init hosting
firebase deploy --only hosting
```

## 🐛 Troubleshooting

**Issue: Admin gets logged out when creating client users**

- Solution: Implement Cloud Function for user creation (see above)

**Issue: CORS errors on localhost**

- Solution: Configure CORS for Firebase Storage (see setup steps)

**Issue: Videos not loading**

- Solution: Check Storage security rules and file permissions

**Issue: Client can see other albums**

- Solution: Verify Firestore security rules are properly deployed

## 📄 License

This project is proprietary software for studio use.

## 🤝 Support

For issues or questions, contact your development team.

---

**Built with Flutter 💙 | Powered by Firebase 🔥**
