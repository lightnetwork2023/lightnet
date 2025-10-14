# Firestore Security Rules for Home Users

## Issue
Home users are getting "unable to load your account" error because they don't have permission to read their customer data from Firestore.

## Required Firestore Rules

Add these rules to your `firestore.rules` file to allow home users to read their own customer data:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // Helper function to check if user is authenticated
    function isSignedIn() {
      return request.auth != null;
    }
    
    // Helper function to get user's role
    function getUserRole() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role;
    }
    
    // Helper function to get user's home_customer_id
    function getHomeCustomerId() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.home_customer_id;
    }
    
    // Users collection - users can read their own document
    match /users/{userId} {
      allow read: if isSignedIn() && request.auth.uid == userId;
      allow write: if false; // Only Cloud Functions can write
    }
    
    // Home customers collection
    match /home_customers/{customerId} {
      // Boss can read/write all customers
      allow read, write: if isSignedIn() && getUserRole() == 'boss';
      
      // Home users can read ONLY their linked customer
      allow read: if isSignedIn() && 
                     getUserRole() == 'homeuser' && 
                     getHomeCustomerId() == customerId;
      
      // Payments subcollection
      match /payments/{paymentId} {
        // Boss can read/write all payments
        allow read, write: if isSignedIn() && getUserRole() == 'boss';
        
        // Home users can read ONLY their customer's payments
        allow read: if isSignedIn() && 
                       getUserRole() == 'homeuser' && 
                       getHomeCustomerId() == customerId;
        
        // Cloud Functions can write (for auto-recording payments)
        allow write: if false; // Only via Cloud Functions with admin SDK
      }
      
      // Plan snapshots subcollection
      match /plan_snapshots/{snapshotId} {
        // Boss can read/write
        allow read, write: if isSignedIn() && getUserRole() == 'boss';
        
        // Home users can read their customer's plan snapshots
        allow read: if isSignedIn() && 
                       getUserRole() == 'homeuser' && 
                       getHomeCustomerId() == customerId;
      }
    }
    
    // Locations collection - read-only for authenticated users
    match /locations/{locationId} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && getUserRole() == 'boss';
    }
    
    // Config collection - read-only for authenticated users
    match /config/{document=**} {
      allow read: if isSignedIn();
      allow write: if isSignedIn() && getUserRole() == 'boss';
    }
  }
}
```

## How to Deploy

### Option 1: Firebase Console

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **lightnet-d2de9**
3. Click **Firestore Database** in left menu
4. Click **Rules** tab
5. Replace the rules with the above
6. Click **Publish**

### Option 2: Firebase CLI

```bash
# Navigate to project directory
cd c:\Users\LITtech\AndroidStudioProjects\lightnetwork

# Edit firestore.rules file
# (paste the rules above)

# Deploy rules
firebase deploy --only firestore:rules
```

## What These Rules Do

### For Home Users:
✅ **Can read:**
- Their own user document (`users/{uid}`)
- Their linked customer document (`home_customers/{customerId}`)
- Their customer's payments (`home_customers/{customerId}/payments/*`)
- Their customer's plan snapshots (`home_customers/{customerId}/plan_snapshots/*`)

❌ **Cannot read:**
- Other customers' data
- Other users' documents
- Unlinked customer data

❌ **Cannot write:**
- Any data (read-only access)

### For Boss:
✅ **Can read/write:**
- All home customers
- All payments
- All plan snapshots
- All locations
- All config

### For Cloud Functions:
✅ **Can read/write:**
- Everything (uses Admin SDK, bypasses rules)

## Testing the Rules

### Test in Firebase Console:

1. Go to Firestore → Rules tab
2. Click **Rules Playground**
3. Test home user read access:
   ```
   Location: /databases/(default)/documents/home_customers/12345
   Auth: Authenticated as UID: [home_user_uid]
   Operation: get
   ```
4. Should show: **Allowed** ✅

### Test in App:

1. **Create home user account** for customer ID 12345
2. **Login as home user**
3. **Should see:**
   - Customer name and details
   - Plan information
   - Payment status
   - No errors

## Common Issues

### Issue 1: "Missing or insufficient permissions"

**Cause:** Rules not deployed or incorrect

**Solution:**
```bash
firebase deploy --only firestore:rules
```

### Issue 2: "Customer not found"

**Cause:** `home_customer_id` not set in user document

**Solution:**
- Check user document in Firestore
- Verify `home_customer_id` field exists
- Re-create home user account if needed

### Issue 3: Rules take time to apply

**Cause:** Firestore rules cache

**Solution:**
- Wait 1-2 minutes after deployment
- Logout and login again
- Clear app data and restart

## Security Best Practices

### ✅ What's Secure:
- Home users can only see their own data
- Customer ID is validated against user document
- No write access for home users
- Boss has full access for management

### ⚠️ Important:
- User document must have `home_customer_id` field
- Customer ID must match exactly
- Rules use helper functions for clarity
- Cloud Functions bypass rules (use Admin SDK)

## Debugging

### Check if rules are applied:

```bash
firebase firestore:rules:get
```

### View rule evaluation logs:

1. Firebase Console → Firestore → Usage tab
2. Look for "Security Rules" section
3. Check for denied requests

### Test specific rule:

```javascript
// In Firebase Console Rules Playground
// Test: Can home user read their customer?
match /databases/(default)/documents/home_customers/12345 {
  allow read: if request.auth.uid == 'home_user_uid_here'
}
```

## Summary

After deploying these rules:
- ✅ Home users can read their own customer data
- ✅ Home users can see their payment history
- ✅ Boss retains full access
- ✅ Data is secure and isolated
- ✅ "Unable to load your account" error should be fixed

Deploy the rules and test by logging in as a home user!
