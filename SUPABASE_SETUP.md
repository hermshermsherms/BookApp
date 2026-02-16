# Supabase Setup Guide for BookApp

This guide will help you set up the Supabase backend for the BookApp authentication system.

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and sign up/sign in
2. Click "New Project"
3. Choose your organization
4. Fill in project details:
   - **Name**: `BookApp`
   - **Database Password**: Generate a strong password (save it securely!)
   - **Region**: Choose closest to your users
   - **Pricing Plan**: Free tier is sufficient for development

## Step 2: Configure Database Schema

1. In your Supabase dashboard, go to **SQL Editor**
2. Copy the contents of `supabase_schema.sql` and paste it into the editor
3. Click **Run** to create all tables, indexes, and security policies

## Step 3: Configure Apple Sign In

1. In Supabase dashboard, go to **Authentication > Providers**
2. Find **Apple** and click **Configure**
3. Enable Apple Sign In
4. You'll need these from Apple Developer Console:
   - **Services ID** (com.yourapp.bookapp.signin)
   - **Team ID** (from Apple Developer account)
   - **Key ID** (from Apple Sign In key)
   - **Private Key** (download .p8 file from Apple)

## Step 4: Get Supabase Credentials

In your Supabase dashboard, go to **Settings > API**:

- **Project URL**: `https://YOUR_PROJECT_ID.supabase.co`
- **anon/public key**: `eyJ...` (long JWT token)

## Step 5: Configure iOS App

### Option A: Environment Variables (Recommended for production)

1. In Xcode, select your project → Target → Info
2. Add these keys to Info.plist:
   ```xml
   <key>SUPABASE_URL</key>
   <string>https://YOUR_PROJECT_ID.supabase.co</string>
   <key>SUPABASE_ANON_KEY</key>
   <string>YOUR_ANON_KEY_HERE</string>
   ```

### Option B: Direct Code Update (Development only)

Update the values in `AuthService.swift` and `SupabaseService.swift`:

```swift
// Replace placeholder values
private let supabaseURL = "https://YOUR_PROJECT_ID.supabase.co"
private let supabaseAnonKey = "YOUR_ANON_KEY_HERE"
```

## Step 6: Configure Apple Sign In in Xcode

1. In Xcode, select your project → Target → Signing & Capabilities
2. Click **+ Capability** and add **Sign in with Apple**
3. Ensure your Apple Developer account is properly configured

## Step 7: Apple Developer Console Setup

1. Go to [developer.apple.com](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**

### Create App ID:
- **App ID**: `com.yourcompany.bookapp`
- Enable **Sign In with Apple** capability

### Create Services ID:
- **Services ID**: `com.yourcompany.bookapp.signin`
- Enable **Sign In with Apple**
- Configure **Return URLs**: Add your Supabase callback URL:
  `https://YOUR_PROJECT_ID.supabase.co/auth/v1/callback`

### Create Sign In with Apple Key:
- Create a new key with **Sign In with Apple** enabled
- Download the .p8 file (save securely!)
- Note the **Key ID**

## Step 8: Test the Setup

1. Remove any demo user code from the app
2. Build and run the app
3. Try signing in with Apple ID
4. Check Supabase dashboard → Authentication → Users to verify user creation

## Troubleshooting

### Common Issues:

1. **"Invalid client" error**: Check Services ID configuration
2. **"Invalid redirect URI"**: Verify callback URL in Apple Developer Console
3. **Database errors**: Ensure schema was created successfully
4. **Token errors**: Verify Supabase keys are correct

### Debug Steps:

1. Check Supabase logs: Dashboard → Logs
2. Check Xcode console for detailed error messages
3. Verify Info.plist has correct keys
4. Test database connection in Supabase SQL Editor

## Security Notes

- Never commit real API keys to version control
- Use environment variables for production
- The anon key is safe for client-side use (it respects RLS policies)
- Keep your service role key secret (not used in this app)

## Next Steps

Once authentication is working:
1. Test user data persistence 
2. Verify library and review functionality
3. Test swipe history tracking
4. Implement error handling for network issues