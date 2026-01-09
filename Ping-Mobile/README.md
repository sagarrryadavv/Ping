# 💬 Ping Rooms

**Talk now. The moment disappears.**

[![Flutter](https://img.shields.io/badge/Flutter-3.0%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Backend-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

Ping is a real-time, ephemeral chat platform designed to be the ultimate **social icebreaker**.  
Built for classrooms, colleges, and communities, it removes the pressure of digital communication by creating shared, temporary spaces where conversations self-destruct.

---

## 🚀 Why Ping?

The hardest part of meeting new people is being the one to text first.  
Ping solves this by making every conversation a shared **event** rather than a direct message.

- **👻 Ephemeral by Design**  
  Rooms self-destruct after 10 minutes. No history, no archives, no pressure.

- **🗳️ Group Democracy**  
  Time running out? The chat only extends if the group votes for it.

- **🔔 Live Pings**  
  "Ping" the whole group to start a conversation instantly without DMing anyone.

- **🎭 Avatar Identity**  
  Users join with custom avatars, keeping the vibe fun and low-stakes.

---

## 📸 Screenshots

| Home Screen | Chat Room | Voting |
|:---:|:---:|:---:|
| ![Home](https://placehold.co/200x400?text=Home+Screen) | ![Chat](https://placehold.co/200x400?text=Chat+UI) | ![Vote](https://placehold.co/200x400?text=Voting+UI) |

---

## 🛠️ Tech Stack

- **Mobile App:** Flutter (Dart)
- **Backend:** Firebase (Firestore, Auth, Cloud Functions)
- **Notifications:** Firebase Cloud Messaging (FCM) via HTTP v1 API
- **State Management:** Provider / StreamBuilders (optimized for real-time data)

---

## ⚙️ Getting Started

This project is organized as a **monorepo**.  
The mobile application source code is located in the `Ping-Mobile` directory.

---

## ✅ Prerequisites

- Flutter SDK installed
- A Firebase account (Free Tier is enough)

---

## 📥 1. Clone the Repository

```bash
git clone https://github.com/sagarrryadavv/Ping.git
cd Ping
```
## 📱 2. Navigate to the App Directory
The Flutter code lives inside the mobile folder:

```bash
cd Ping-Mobile
```
### 3. Setup Firebase (BYOB - Bring Your Own Backend)
For security, this repo does not include private keys. You must connect your own Firebase project.

1. **Create Project:**
   - Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project.

2. **Register App:**
   - In the Firebase console, add an **Android app**.
   - Use the package name: `com.example.ping_app`

3. **Add SHA-1 Key (Crucial for Login):**
   You must register your local debug key for Google Sign-In to work.
   - Run the following command in your terminal to get your SHA-1 key:
     ```bash
     keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
     ```
   - Copy the **SHA-1** fingerprint from the output.
   - Go to **Project Overview** > **Project settings** (gear icon) > **Your apps**.
   - Select the Android app, click **Add fingerprint**, and paste the SHA-1 key.

4. **Download Config:**
   - Download `google-services.json` from the Firebase console.
   - Place it in the following directory:
     ```
     Ping-Mobile/android/app/google-services.json
     ```

5. **Enable Authentication:**
   - Go to **Build** > **Authentication** in the Firebase Console.
   - Click **Get Started**.
   - Enable **Google** provider (Click 'Enable', select a support email, and Save).
   - Enable **Email/Password** provider (Click 'Enable' and Save).

6. **Setup Firestore Database:**
   - Go to **Build** > **Firestore Database**.
   - Click **Create Database**.
   - Select a location (e.g., `nam5` or `eur3`) and click **Next**.
   - Choose **Start in Test Mode** (for easiest setup) and click **Create**.

7. **Configure Notifications (Critical):**
   The app uses a Service Account to send "Pings" securely.
   - Go to **Project Settings** (Gear icon) > **Service accounts**.
   - Click **Generate new private key** > **Generate key** (this downloads a JSON file).
   - Open the file `Ping-Mobile/lib/services/notification_service.dart` in your code editor.
   - Replace the placeholder values (like `YOUR_PROJECT_ID` and `YOUR_PRIVATE_KEY`) with the details from the JSON file you just downloaded.
   - **⚠️ Note:** Do not commit this file to GitHub after adding your real keys.

8. **Generate Flutter Configuration:**
   - Open your terminal in the `Ping-Mobile` folder.
   - Run the following command to link everything together:
     ```bash
     flutterfire configure
     ```
   - Select your project and platform (**Android**) when prompted.

## ▶️ 5. Run the App
```bash
flutter run
```
## 📂 Repository Structure
```bash
Ping/
├── Ping-Mobile/       # Flutter Android/iOS Application
│   ├── lib/           # Screens, Services, Providers
│   ├── assets/        # Images, Icons, Avatars
│   └── android/       # Native Android code
└── README.md          # Documentation
```

## 🤝 Contributing
Contributions are welcome! 🚀

1.  **Fork** the project
2.  Create your **feature branch**:
    ```bash
    git checkout -b feature/AmazingFeature
    ```
3.  **Commit** your changes:
    ```bash
    git commit -m "Add some AmazingFeature"
    ```
4.  **Push** to the branch:
    ```bash
    git push origin feature/AmazingFeature
    ```
5.  Open a **Pull Request**

## 📞 Contact
**Sagar Yadav**

* [LinkedIn](https://www.linkedin.com/in/your-profile-here)
* [GitHub](https://github.com/sagarrryadavv)

**Project Link:** [https://github.com/sagarrryadavv/Ping](https://github.com/sagarrryadavv/Ping)
