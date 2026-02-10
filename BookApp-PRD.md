# BookApp — Product Requirements Document

> **Status:** v1 MVP — requirements mostly finalized
> **Last Updated:** 2026-02-08

---

## 1. Overview

An iOS app for book discovery and reading tracking. Two core experiences:

1. **Discovery** — A full-screen, TikTok-style swipeable feed of book recommendations
2. **Logging** — A personal library of liked/read books with review capabilities

User accounts (via Apple Sign In) power personalization across both.

---

## 2. Tech Stack

| Component | Decision |
|-----------|----------|
| **Framework** | SwiftUI |
| **Architecture** | MVVM |
| **Backend** | Supabase (PostgreSQL, Auth, Storage) |
| **Book Data** | Google Books API |
| **Min iOS** | 16+ (best SwiftUI support) |
| **Device** | iPhone only (v1) |
| **Orientation** | Portrait only |

---

## 3. Discovery Page

### Interaction Model
| Gesture | Action | Result |
|---------|--------|--------|
| Swipe up | Next book | Advances feed |
| Swipe left | Dislike | Soft signal — won't reappear soon, used as negative signal for future recs |
| Double tap | Like | Saves to Library → "Want to Read" |
| Single tap | Details | Opens scrollable detail view |
| Swipe right | Buy | Auto-saves to Library + shows purchase sheet |

### Card Content (full-screen)
- Book cover image (prominent, centered)
- Title + Author
- Genre tag(s)
- Average rating (from Google Books)
- Page count
- One-line hook / description snippet

### Detail View (single tap)
Scrollable overlay/sheet showing:
- Book cover (large)
- Title, author, genre, page count, publication date
- Full synopsis / description
- Author info snippet
- Similar books (horizontal scroll)
- Action buttons: Like, Buy, Dislike

### Purchase Sheet (swipe right)
Bottom sheet with purchase options:
- Amazon
- Apple Books
- Bookshop.org
- Links open in in-app browser (SFSafariViewController)

### Feed Logic (v1 — pre-recommendation engine)
- Popular/trending books from Google Books API
- Rotate across genres for variety
- Exclude books user has already seen (liked or disliked)
- Pre-fetch next 5–10 books for smooth swiping

---

## 4. Logging Page (Library)

### Layout
- **Three tabs:** Want to Read | Reading | Read
- Each tab: scrollable list sorted by date added (most recent first)
- Each row: cover thumbnail, title, author, status indicator

### Book Status Flow
```
Want to Read → Reading → Read
```
- Users can move books between statuses freely
- Books arrive in "Want to Read" from Discovery (like or buy)

### Reviews
- Available when a book is marked as "Read"
- **Rating:** 1–5 stars, full stars only (tap to rate)
- **Text review:** Open text input, no character limit
- Reviews are editable and deletable

### Manual Book Add
- Search bar at top of Library that queries Google Books API
- User can search by title or author
- Add result to any status tab

---

## 5. Accounts & Auth

### Authentication
- **Apple Sign In** only (privacy-friendly, App Store compliant)
- Supabase Auth handles session management
- Account required to use the app (no guest mode for v1)

### Profile Tab
- Display name (from Apple ID)
- Reading stats: books read, reviews written, total books in library
- Settings: account management, delete account (required by App Store)

---

## 6. Design

### Visual Style
- **Light, warm, bookish** — indie bookstore aesthetic
- Cream / warm paper background tones
- Serif fonts for book titles, clean sans-serif for UI text
- Book covers as the primary visual element
- Subtle, smooth animations (native iOS feel, not flashy)

### Navigation
- **Bottom tab bar** with 3 tabs:
  - 📖 Discovery
  - 📚 Library
  - 👤 Profile

---

## 7. Monetization (v1)

- **Free app** with affiliate revenue from book purchases
- Affiliate links in purchase sheet (Amazon Associates, Apple Books affiliate)
- No ads, no premium tier for v1

---

## 8. Data Model (Supabase)

### Tables
- **users** — id, apple_id, display_name, created_at
- **user_books** — id, user_id, google_books_id, status (want_to_read / reading / read), added_at, updated_at
- **reviews** — id, user_id, google_books_id, rating (1-5), review_text, created_at, updated_at
- **swipe_history** — id, user_id, google_books_id, action (like / dislike / buy), swiped_at

### Key Indexes
- user_books: (user_id, status) for tab filtering
- swipe_history: (user_id, google_books_id) for feed deduplication

---

## 9. Out of Scope (v1) — Deferred to v2+

| Feature | Notes |
|---------|-------|
| Onboarding flow | Interest capture for personalized recs |
| Recommendation engine | ML/algorithm-powered feed |
| Custom shelves / tags | User-created collections |
| Reading progress tracking | Page number / percentage |
| Undo swipe | Shake or button to undo last action |
| Dark mode | Follow system or manual toggle |
| Social features | Friends, following, public profiles |
| Push notifications | New recs, reading reminders |
| Android version | — |
| iPad support | — |
| Barcode / ISBN scanner | Camera-based book add |

---

## 10. Decisions Log

| # | Question | Decision | Date |
|---|----------|----------|------|
| 1 | iOS Framework | SwiftUI | 2026-02-08 |
| 2 | Backend | Supabase | 2026-02-08 |
| 3 | Book Data Source | Google Books API | 2026-02-08 |
| 4 | Buy Action | Bottom sheet with multiple purchase options | 2026-02-08 |
| 5 | Card Content | Rich: cover, title, author, genre, rating, page count, hook | 2026-02-08 |
| 6 | Swipe Left | Soft signal — skip, won't resurface soon | 2026-02-08 |
| 7 | Auth | Apple Sign In only | 2026-02-08 |
| 8 | Logging Layout | Three tabs by status | 2026-02-08 |
| 9 | Detail View | Comprehensive: synopsis, author, similar books, action buttons | 2026-02-08 |
| 10 | Feed Source (v1) | Popular/trending from Google Books | 2026-02-08 |
| 11 | Star Rating | 1–5, full stars only | 2026-02-08 |
| 12 | Design Style | Light, warm, bookish | 2026-02-08 |
| 13 | Buy Auto-saves | Yes, swipe-right also saves to Library | 2026-02-08 |
| 14 | Manual Add | Search by title/author via Google Books API | 2026-02-08 |
| 15 | Navigation | 3-tab bar: Discovery, Library, Profile | 2026-02-08 |
| 16 | v1 Scope | Defer: custom shelves, progress tracking, undo, dark mode | 2026-02-08 |
| 17 | Monetization | Free + affiliate links | 2026-02-08 |

---

## 11. Implementation Status

### Current Status: **Ready for Development**
*Last Updated: 2026-02-10*

**Completed:**
- [x] PRD finalized and documented
- [x] Git repository initialized
- [x] Xcode project structure created
- [x] Basic SwiftUI app template set up
- [x] All MVVM folders and files created
- [x] All source files properly linked in Xcode project
- [x] Project compiles and is ready to run

**Ready to Start:**
- 📱 **The project is now fully set up and can be opened in Xcode**
- 🔧 **All views, models, and services are scaffolded**
- 🎯 **Tab navigation (Discovery, Library, Profile) is implemented**
- 🚀 **Development mode authentication bypass added**

**Next Steps:**
1. Configure Supabase project and database schema
2. Set up Google Books API key  
3. Add real book data integration
4. Style with the warm, bookish theme
5. Configure Apple Sign In for production

---

## 12. Open Items

- [ ] Finalize app name and branding
- [ ] Google Books API key setup and rate limit planning
- [ ] Affiliate program signup (Amazon Associates, Apple Books)
- [ ] Supabase project setup and schema migration
- [ ] App Store provisioning and certificates
