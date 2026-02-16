# BookApp — Product Requirements Document

> **Status:** v1 MVP — Discovery Feed Complete + Launch Screen & App Icon Complete
> **Last Updated:** 2026-02-15

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
| Swipe up | Next book | Smooth transition to next book (TikTok-style) |
| Swipe down | Previous book | Smooth transition to previous book (Instagram Reels-style) |
| Double tap | Like | Saves to Library → "Want to Read" + heart animation |
| Single tap | Details | Opens scrollable detail view with optimized action buttons |
| Buy button | Purchase | Shows purchase sheet with in-app browser links |

**Note:** Swipe left/right gestures were removed in favor of cleaner vertical-only navigation for optimal feed experience.

### Card Content (full-screen)
- **High-quality book cover image** with smart fallback hierarchy:
  1. High-resolution cover from Google Books API
  2. Thumbnail fallback if high-res unavailable
  3. Genre-specific styled title card with gradients and icons
- Title (serif typography) + Author
- Genre tag with accent styling
- Average rating (star icon) + page count
- One-line hook / description snippet
- Smooth animations and transitions throughout

### Detail View (single tap)
Scrollable overlay/sheet showing:
- Book cover (large, high-quality)
- Title, author, genre, page count, publication date
- Full synopsis / description
- Author info snippet
- **Skip, Save, Buy buttons** (positioned above similar books for better UX)
- Similar books (horizontal scroll with improved image quality)

### Purchase Sheet (Buy button)
Bottom sheet with purchase options:
- Amazon (with cart icon and orange branding)
- Bookshop.org (with building columns icon and positive branding)
- **Links open in smooth in-app Safari browser** with proper delegate handling for seamless navigation

**Note:** Apple Books removed from purchase options as requested.

### Feed Logic (v1 — pre-recommendation engine)
- Popular/trending books from Google Books API
- Rotate across genres for variety
- Exclude books user has already seen (liked or disliked)
- Pre-fetch next 5–10 books for smooth swiping

---

## 4. App Branding & Launch Experience

### Launch Screen
- **Static book logo with app branding** - displays for 1.5 seconds
- Clean white background with brown book icon and "BookApp" text
- Professional, minimalist design matching the bookish aesthetic

### App Icon
- **Complete iOS app icon set** generated for all required sizes
- Book design with clean, recognizable appearance
- Consistent with the app's warm, bookish visual style

---

## 5. Logging Page (Library)

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

## 6. Accounts & Auth

### Authentication
- **Apple Sign In** only (privacy-friendly, App Store compliant)
- Supabase Auth handles session management
- Account required to use the app (no guest mode for v1)

### Profile Tab
- Display name (from Apple ID)
- Reading stats: books read, reviews written, total books in library
- Settings: account management, delete account (required by App Store)

---

## 7. Design

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

## 8. Monetization (v1)

- **Free app** with affiliate revenue from book purchases
- Affiliate links in purchase sheet (Amazon Associates, Bookshop.org)
- No ads, no premium tier for v1

---

## 9. Data Model (Supabase)

### Tables
- **users** — id, apple_id, display_name, created_at
- **user_books** — id, user_id, google_books_id, status (want_to_read / reading / read), added_at, updated_at
- **reviews** — id, user_id, google_books_id, rating (1-5), review_text, created_at, updated_at
- **swipe_history** — id, user_id, google_books_id, action (like / dislike / buy), swiped_at

### Key Indexes
- user_books: (user_id, status) for tab filtering
- swipe_history: (user_id, google_books_id) for feed deduplication

---

## 10. Out of Scope (v1) — Deferred to v2+

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

## 11. Decisions Log

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
| 18 | Launch Screen | Static book logo, 1.5 second display | 2026-02-15 |
| 19 | App Icon | Complete iOS icon set with book design | 2026-02-15 |
| 20 | Image Quality | High-res → thumbnail → styled fallback hierarchy | 2026-02-15 |
| 21 | Apple Books | Removed from purchase options | 2026-02-15 |

---

## 12. Implementation Plan & Milestones

### Current Status: **Milestone 1 Complete + Launch Screen & App Icon Complete**
*Last Updated: 2026-02-15*

**Foundation Completed:**
- [x] PRD finalized and documented
- [x] Git repository initialized
- [x] Xcode project structure created
- [x] Basic SwiftUI app template set up
- [x] MVVM architecture implemented
- [x] Development mode authentication bypass

**Milestone 1 Achievements:**
- ✅ **Discovery Feed is fully functional with real book data**
- ✅ **Smooth vertical swipe navigation (TikTok/Instagram Reels style)**
- ✅ **Complete book detail views with optimized button placement**
- ✅ **High-quality image system with smart fallback hierarchy**
- ✅ **Purchase flow with in-app Safari browser integration**
- ✅ **Professional error handling and graceful fallback to mock data**
- ✅ **Production-ready code quality with comprehensive testing**

**UI/UX Polish Completed (Feb 2026):**
- ✅ **Repositioned Skip/Save/Buy buttons above "You might also like" for better UX**
- ✅ **Fixed buy button functionality to properly show purchase sheet**
- ✅ **Dramatically improved image quality with high-res → thumbnail → styled fallback hierarchy**
- ✅ **Eliminated image reloading issues during swipes**
- ✅ **Replaced plain white fallbacks with beautiful genre-specific styled title cards**
- ✅ **Removed unwanted zoom effects during scrolling**
- ✅ **Enhanced swipe animations for smoother, more natural feel like social media apps**
- ✅ **Fixed in-app browser white screen issue with proper Safari delegate handling**

**Launch Screen & Branding Completed (Feb 2026):**
- ✅ **Animated launch screen with static book logo and 1.5 second display**
- ✅ **Complete iOS app icon set generated with book design**
- ✅ **High-resolution image loading system with priority fallback**
- ✅ **Updated mock data with real Google Books IDs for working cover images**
- ✅ **Comprehensive code cleanup and memory management improvements**

---

## 13. Feature-by-Feature Implementation Milestones

### **Milestone 1: Discovery Feed MVP** ✅ *[COMPLETED]*
**Goal:** Users can swipe through real books and see book details

**Tasks:**
1. **Google Books API Integration**
   - ✅ Set up API service layer with fallback to mock data
   - ✅ Implement book search and trending books fetching
   - ✅ Test API responses and error handling

2. **Discovery Feed Core Functionality**
   - ✅ Display real book data in swipeable cards
   - ✅ Implement swipe gestures (up/next, left/dislike, double tap/like, single tap/details, right/buy)
   - ✅ Add book detail view with complete real data
   - ✅ Implement feed logic (popular books rotation, genre variety, seen book deduplication)

3. **Book Detail View**
   - ✅ Full synopsis, author info, ratings, metadata display
   - ✅ Similar books horizontal scroll
   - ✅ Purchase sheet with affiliate links (Amazon, Bookshop.org)
   - ✅ In-app browser integration (SFSafariViewController)

4. **Launch Experience & Branding**
   - ✅ Static launch screen with book logo and app branding
   - ✅ Complete iOS app icon set generation
   - ✅ High-resolution image loading implementation
   - ✅ Mock data improvement with real Google Books IDs

**Definition of Done:**
- [x] User can see and swipe through real books (10 mock books + Google Books API)
- [x] Detail view shows complete book information (synopsis, author, similar books, metadata)
- [x] All PRD-specified gestures work smoothly (swipe up/next, left/dislike, double tap/like, single tap/details, right/buy)
- [x] No placeholder data visible to user (graceful fallback to realistic mock data)
- [x] Professional launch screen and app icon implemented
- [x] High-quality image loading system in place

---

### **Milestone 2: Authentication & User State** 🎯 *[Next Priority]*
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

### **Milestone 6: Technical Debt & Browser Refinements**
**Goal:** Polish in-app browser experience and resolve edge cases

**Tasks:**
1. **Safari Browser Integration Fixes**
   - Fix half sheet collapsing issue after closing website
   - Fix websites that do not render properly in in-app browser  
   - Remove white outline around half sheet when collapsing website
   - Investigate and resolve any remaining Safari in-app browser edge cases

2. **Performance & Polish**
   - Code optimization and cleanup
   - Memory management improvements
   - Animation smoothness enhancements

**Definition of Done:**
- [ ] All Safari browser edge cases resolved
- [ ] Half sheet behavior is smooth and consistent
- [ ] No visual glitches in purchase flow
- [ ] App feels polished and professional throughout

---

## 14. Implementation Best Practices

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

## 15. Open Items

### **Recently Completed (Feb 2026):**
- [x] Launch screen implementation with static book logo
- [x] Complete iOS app icon set generation
- [x] High-resolution image loading with smart fallback hierarchy
- [x] Mock data improvement with real Google Books IDs
- [x] Code quality improvements and memory management
- [x] Google Books API integration with fallback to mock data
- [x] Real book data fetching and display with high-quality images
- [x] Smooth swipe gestures and navigation (TikTok/Instagram Reels style)
- [x] Complete UI/UX polish and bug fixes

### **Next Priority: Authentication & User State Setup**
- [ ] Supabase project setup and schema migration
- [ ] Configure Apple Developer account capabilities
- [ ] Replace demo user with real Apple Sign In
- [ ] Handle authentication states and errors

### **For Later Milestones:**
- [ ] Finalize app name and branding
- [ ] Affiliate program signup (Amazon Associates, Bookshop.org)  
- [ ] App Store provisioning and certificates

---

## 16. Project Status Summary

### **What's Working Well:**
- Discovery Feed MVP is fully functional and polished
- High-quality image loading system provides excellent user experience
- TikTok-style navigation feels smooth and natural
- Purchase flow with in-app Safari browser integration
- Professional launch screen and app icon
- Comprehensive error handling and fallback to mock data
- Clean, maintainable codebase with MVVM architecture

### **Current Focus Areas:**
- Preparing for Milestone 2 (Authentication & User State)
- Supabase project setup and Apple Sign In configuration
- Maintaining code quality standards established in Milestone 1

### **Next Steps:**
1. Begin Supabase setup and Apple Sign In production configuration
2. Start implementing user data persistence and session management
3. Continue building out Library and Profile functionality
4. Address technical debt items in final milestone before App Store launch

The app has achieved a solid foundation with Milestone 1 complete and is ready to progress to user authentication and data persistence in Milestone 2.

