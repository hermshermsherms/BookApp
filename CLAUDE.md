# Claude Development Guidelines for BookApp

This file contains important guidelines and common mistakes to avoid when working on the BookApp project.

## 🚫 Common SwiftUI Mistakes to Avoid

### DragGesture Translation Properties
**NEVER use `.y` or `.x` on `value.translation` in DragGesture**

❌ **Wrong:**
```swift
DragGesture()
    .onChanged { value in
        let offset = value.translation.y  // ERROR: CGSize has no member 'y'
    }
```

✅ **Correct:**
```swift
DragGesture()
    .onChanged { value in
        let offset = value.translation.height  // Use .height for vertical
        let horizontal = value.translation.width  // Use .width for horizontal
    }
```

**Reason:** `value.translation` is of type `CGSize`, which has `width` and `height` properties, not `x` and `y`.

## 🏗 Architecture Guidelines

### File Organization
- Keep related files in the same target/directory structure
- Ensure models are available to all services that need them
- Use consistent directory naming (avoid mixing "Services" and "Services 2")

### Configuration Management
- Never hardcode API keys or URLs
- Use `Config.swift` for centralized configuration
- Support both development and production environments

## 🔧 Build Error Prevention

### Before Making Changes
1. Always test build after significant changes
2. Check that new models/types are accessible from all required files
3. Verify import statements are correct

### SwiftUI Specific
- Use `.height` and `.width` for CGSize properties
- Use `.x` and `.y` for CGPoint properties
- Remember that `@Published` properties need `@MainActor` when updated from background threads

## 🔐 Apple Sign In Development Issues

### Error 1000: "The operation couldn't be completed"
This is a **common development issue**, not a code problem. Solutions:

**For Development:**
- ✅ **Use "Continue as Demo User"** - Always works, perfect for testing
- ✅ **Test on physical device** instead of simulator
- ❌ **Don't rely on Apple Sign In in simulator** - Known to be unreliable

**For Production:**
- Requires proper Apple Developer Console setup
- Need valid Team ID and Bundle ID configuration  
- Requires Supabase project with Apple Sign In configured

### Development vs Production Testing
- **Development**: Use demo user for reliable testing
- **Staging**: Test Apple Sign In on device with proper certificates
- **Production**: Full Apple Developer Console + Supabase setup required

### When Apple Sign In Fails
1. **Check testing environment** (simulator vs device)
2. **Use demo user as fallback** for development
3. **Verify entitlements** are properly configured
4. **Check Apple Developer Console** setup for production

## 📝 Git Workflow

### Branch Management
- Create feature branches for major changes (`user-auth`, `library-features`, etc.)
- Commit working code frequently to avoid losing progress
- Stash changes before switching branches

### Commit Messages
- Use descriptive commit messages
- Include the area affected (e.g., "Fix DragGesture in DiscoveryFeedView")

## ✅ Testing Guidelines

### Build Testing
- Test builds on both Debug and Release configurations when possible
- Check for warnings as well as errors
- Verify functionality after fixing build errors

### Manual Testing
- Test gesture interactions after changes to UI components
- Verify authentication flows after auth changes
- Check data persistence after database/model changes

---

*This file should be updated whenever we encounter new common issues or establish new best practices.*