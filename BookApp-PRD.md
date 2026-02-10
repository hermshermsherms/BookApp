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

## 11. Implementation Plan & Milestones

### Current Status: **Project Scaffolded - Ready for Feature Implementation**
*Last Updated: 2026-02-10*

**Foundation Completed:**
- [x] PRD finalized and documented
- [x] Git repository initialized
- [x] Xcode project structure created
- [x] Basic SwiftUI app template set up
- [x] MVVM architecture scaffolded
- [x] Development mode authentication bypass

**Current Reality Check:**
- ⚠️ **Project structure exists but core features are NOT implemented**
- ⚠️ **Views are placeholder shells without real functionality**
- ⚠️ **No actual book data integration or user flows working**

---

## 12. Feature-by-Feature Implementation Milestones

### **Milestone 1: Discovery Feed MVP** 🎯 *[Current Priority]*
**Goal:** Users can swipe through real books and see book details

**Tasks:**
1. **Google Books API Integration**
   - Set up API key and service layer
   - Implement book search and trending books fetching
   - Test API responses and error handling

2. **Discovery Feed Core Functionality**
   - Display real book data in swipeable cards
   - Implement swipe gestures (up/next, left/dislike, tap/details)
   - Add book detail view with real data
   - Implement basic feed logic (popular books rotation)

3. **Book Detail View**
   - Full synopsis, author info, ratings display
   - Purchase sheet with affiliate links (mock for now)

**Definition of Done:**
- [ ] User can see and swipe through real books
- [ ] Detail view shows complete book information
- [ ] Basic navigation and gestures work smoothly
- [ ] No placeholder data visible to user

---

### **Milestone 2: Authentication & User State** 
**Goal:** Users can sign in and their actions persist

**Tasks:**
1. **Supabase Setup & Integration**
   - Set up Supabase project and database schema
   - Configure authentication service
   - Test user creation and session management

2. **Apple Sign In Production Setup**
   - Configure Apple Developer account capabilities
   - Replace demo user with real Apple Sign In
   - Handle authentication states and errors

**Definition of Done:**
- [ ] Real Apple Sign In working in production
- [ ] User sessions persist across app restarts
- [ ] User data stored and retrieved from Supabase

---

### **Milestone 3: Library & Book Management**
**Goal:** Users can save, organize, and review books

**Tasks:**
1. **Library Core Functionality**
   - Implement Want to Read / Reading / Read tabs
   - Book status management and transitions
   - Manual book search and add functionality

2. **Review System**
   - 1-5 star rating system
   - Text review creation and editing
   - Review display and management

**Definition of Done:**
- [ ] Users can save books from Discovery to Library
- [ ] Book status changes work correctly
- [ ] Review system fully functional
- [ ] Manual book addition works

---

### **Milestone 4: Profile & User Experience**
**Goal:** Complete user profile and statistics

**Tasks:**
1. **Profile Implementation**
   - Display user stats (books read, reviews written)
   - Account management (delete account)
   - Settings and preferences

2. **Theme & Polish**
   - Implement warm, bookish visual design
   - Smooth animations and transitions
   - Performance optimization

**Definition of Done:**
- [ ] Profile shows accurate user statistics
- [ ] Visual design matches PRD specifications
- [ ] App feels polished and performant

---

### **Milestone 5: Production Ready**
**Goal:** App ready for App Store submission

**Tasks:**
1. **Affiliate Revenue Setup**
   - Amazon Associates integration
   - Apple Books affiliate links
   - Purchase flow testing

2. **Production Polish**
   - Error handling and edge cases
   - App Store assets and metadata
   - Final testing and bug fixes

**Definition of Done:**
- [ ] Affiliate links generate revenue
- [ ] App passes App Store review guidelines
- [ ] All core user flows tested and working

---

## 13. Implementation Best Practices

### **Lessons Learned from Initial Implementation**

**❌ What NOT to do:**
- **Don't create scaffolding without functionality** - Empty view files with placeholder content provide no user value
- **Don't claim features are "implemented" when they're just structured** - Users care about working functionality, not architecture
- **Don't build everything at once** - This leads to nothing being fully functional
- **Don't skip testing each feature** - Untested features often have basic issues that block user flows

**✅ What TO do:**
- **Implement one complete user flow at a time** - Users should be able to complete a full journey (e.g., discover → view → save a book)
- **Start with core functionality, not polish** - Get the basic feature working before adding animations or perfect styling  
- **Test each milestone thoroughly** - Ensure the feature works end-to-end before moving to the next
- **Use real data as early as possible** - Mock data is fine temporarily, but integrate real APIs quickly
- **Focus on user experience over technical architecture** - A working app with less perfect code is better than perfect code that doesn't work

### **Milestone Success Criteria**
Each milestone should meet these criteria before moving to the next:
- ✅ **Functionally complete** - All described user actions work
- ✅ **Tested end-to-end** - Full user flow verified manually
- ✅ **No placeholder content** - Real data displayed to users
- ✅ **Error handling** - Basic error states handled gracefully
- ✅ **Commits and documentation** - Changes committed with clear descriptions

### **Implementation Order Principles**
1. **Start with the most valuable user flow** (Discovery feed for this app)
2. **Build vertically, not horizontally** (Complete one feature fully vs partial implementation across features)
3. **Integrate external dependencies early** (APIs, authentication) to surface integration issues
4. **Polish comes last** (Visual design and animations after functionality works)

---

## 14. Open Items

**For Milestone 1 (Discovery Feed MVP):**
- [ ] Google Books API key setup and rate limit planning
- [ ] Implement real book data fetching and display
- [ ] Add swipe gestures and navigation

**For Later Milestones:**
- [ ] Finalize app name and branding
- [ ] Affiliate program signup (Amazon Associates, Apple Books)  
- [ ] Supabase project setup and schema migration
- [ ] App Store provisioning and certificates
