# Home User Role Setup Guide

## Overview
The **Home User** role allows home internet customers to log in and view their own payment information and account details.

## What I Implemented

### 1. Authentication & Role Management
**File:** `lib/controllers/auth_controller.dart`
- Added `isHomeUser` getter to check if user has 'homeuser' role
- Added `homeCustomerId` field to store the linked customer ID
- Loads `home_customer_id` from user document in Firestore

### 2. Main App Routing
**File:** `lib/main.dart`
- Added routing logic to direct home users to `HomeUserScreen`
- Home users are authenticated via email/password like other roles

### 3. Home User Screen
**File:** `lib/screens/HomeUserScreen.dart`
- Shows customer's plan details (speed, amount, billing schedule, zone)
- Displays payment status (paid up, pending, or overdue)
- Shows total due, total paid, and outstanding balance
- Displays next due date and last payment date
- Refresh button to reload data
- Logout button

### 4. Create Home User Account
**File:** `lib/screens/CreateHomeUserAccountScreen.dart`
- Boss-only screen to create login credentials for a customer
- Links the Firebase Auth account to a customer ID
- Sets role as 'homeuser' and stores `home_customer_id` in user document

**File:** `lib/controllers/HomeInternetService.dart`
- Added `createHomeUserAccount()` method
- Creates Firebase Auth user with role 'homeuser'
- Links account to customer via `home_customer_id` field

### 5. Integration with Edit Customer Screen
**File:** `lib/screens/EditHomeCustomerScreen.dart`
- Added "Create Home User Account" button
- Opens the account creation screen for that customer

## How to Use

### For Boss: Creating a Home User Account

1. **Navigate to Home Internet Users** (from main menu)
2. **Select a customer** and tap the Edit icon
3. **Scroll down** and tap "Create Home User Account"
4. **Enter credentials:**
   - Email (customer will use this to login)
   - Password (minimum 6 characters)
5. **Tap "Create Account"**
6. Share the email and password with the customer

### For Home User: Logging In

1. **Open the app** and tap "Login"
2. **Enter email and password** provided by the boss
3. **View your account:**
   - Plan details (speed, amount, billing)
   - Payment status (paid/pending/overdue)
   - Outstanding balance
   - Next due date
   - Last payment date
4. **Pull down to refresh** data
5. **Tap logout** when done

## Firestore Structure

### User Document (in `users` collection)
```json
{
  "email": "customer@example.com",
  "role": "homeuser",
  "name": "Customer Name",
  "home_customer_id": "12345"  // Links to home_customers/{id}
}
```

### Customer Document (in `home_customers` collection)
```json
{
  "id": "12345",
  "name": "Customer Name",
  "phone": "0712345678",
  "speed_mbps": 10,
  "plan_amount": 50000,
  "schedule": "monthly",
  "zone": "Zone A",
  // ... other fields
}
```

## Security

- **Boss-only:** Only boss can create home user accounts
- **Customer-specific:** Each home user can only see their own data
- **Read-only:** Home users cannot modify any data, only view
- **Firebase Auth:** Uses standard Firebase Authentication for login
- **Firestore Rules:** Ensure you add rules to restrict home users to their own customer ID:

```javascript
// Add to firestore.rules
match /home_customers/{customerId} {
  allow read: if request.auth != null && 
    (get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'boss' ||
     get(/databases/$(database)/documents/users/$(request.auth.uid)).data.home_customer_id == customerId);
}
```

## What Home Users Can See

✅ **Can View:**
- Their plan details (speed, amount, billing schedule)
- Payment status (paid up, pending, overdue)
- Outstanding balance
- Next due date
- Last payment date
- Zone and location

❌ **Cannot View:**
- Other customers' data
- Payment approval workflows
- Analytics
- Admin functions

❌ **Cannot Do:**
- Make payments (view only)
- Edit their profile
- View other customers
- Access admin features

## Testing

1. **Create a test customer** in Home Internet Users
2. **Create a home user account** for that customer
3. **Logout** from boss account
4. **Login** with the home user credentials
5. **Verify** you see only that customer's data
6. **Test refresh** by pulling down
7. **Logout** and login as boss again

## Notes

- Home user accounts are linked to customer IDs, not phone numbers
- If a customer is archived, their home user account remains but will show an error
- To disable a home user, delete their account from Firebase Auth Console
- Email addresses must be unique across all Firebase Auth users
- Passwords must be at least 6 characters (Firebase Auth requirement)

## Future Enhancements (Optional)

- Allow home users to upload payment receipts
- Show payment history with dates and amounts
- Push notifications for due dates
- In-app payment integration
- Profile editing (phone, address)
- Password reset functionality
