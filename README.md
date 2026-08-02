# BookApp

BookApp is a native SwiftUI iOS application. Open `BookApp.xcodeproj` in Xcode; the repository is intentionally an Xcode project rather than a Swift package.

## Run in the simulator

1. Open `BookApp.xcodeproj`.
2. Select the shared **BookApp** scheme and an iPhone simulator.
3. Press **Run** (`Command-R`).
4. Use **Continue as Demo User** on the sign-in screen to explore the app without configuring a backend.

## Run on an iPhone

1. Connect the iPhone and trust the Mac if prompted.
2. In the **BookApp** target's **Signing & Capabilities** tab, select your Apple Developer team.
3. If Xcode reports that the bundle identifier is unavailable, replace the BookApp target's bundle identifier with a unique reverse-DNS identifier you own.
4. Select the iPhone as the run destination and press **Run**.

The project uses automatic signing and includes the Sign in with Apple entitlement. A free Apple ID can install development builds on a personal device; distribution requires an Apple Developer Program membership.

## Service configuration

The app launches and supports its demo flow without API credentials. To load live books, similar-book recommendations, and provider-authorized EPUB editions:

- Copy `BookApp/Secrets.example.swift` to `BookApp/Secrets.swift` and replace the placeholder with a Google Books API key. `Secrets.swift` is already part of the target and is ignored by Git.
- Alternatively, set `GOOGLE_BOOKS_API_KEY` in the BookApp target's generated Info.plist settings.
- `SUPABASE_URL` and `SUPABASE_ANON_KEY` as described in `SUPABASE_SETUP.md`.

The Preview button opens editions Google Books marks as readable in the user's region, with an exact-match Project Gutenberg fallback for public-domain books. It does not bypass publisher access restrictions. Restrict the Google key to the Books API and the app's iOS bundle identifier before distributing a build. Do not commit production credentials.
