# Home User Payment Integration

## Overview
Home users can now make payments directly through the app using mobile money (Airtel, Tigo, Vodacom, Halopesa, Azampesa), just like agents do.

## What I Implemented

### 1. Payment Screen (`HomeUserPaymentScreen.dart`)
**File:** `lib/screens/HomeUserPaymentScreen.dart`

**Features:**
- Shows customer account information (name, ID, plan amount)
- Amount input field (user enters how much they want to pay)
- Phone number field (pre-filled from customer record)
- Payment provider dropdown (Airtel, Tigo, Vodacom, Halopesa, Azampesa)
- Payment instructions card
- "Pay Now" button with loading state

**Payment Flow:**
1. User enters amount they want to pay
2. Confirms their phone number
3. Selects mobile money provider
4. Taps "Pay Now"
5. Backend initiates payment via AzamPay
6. User approves payment on their phone
7. Success message shown and returns to home screen

### 2. Integration with Existing Payment API
Uses the same `/make-paymentagent` endpoint that agents use.

**Payload sent:**
```json
{
  "phone": "0712345678",
  "amount": "50000",
  "provider": "Airtel",
  "location": "HOME_USER",
  "days": 30,
  "durationSeconds": 2592000,
  "quantity": "12345"  // Customer ID for tracking
}
```

**Key differences from agent payments:**
- `location`: Set to `"HOME_USER"` to identify home user payments
- `quantity`: Contains the customer ID (5-digit ID) for tracking
- `days`: Fixed at 30 days (monthly billing)
- `durationSeconds`: Fixed at 2592000 (30 days in seconds)

### 3. Updated Home User Screen
**File:** `lib/screens/HomeUserScreen.dart`

**Changes:**
- Added "Make Payment" button between status card and payment history
- Button navigates to payment screen
- Refreshes data after successful payment

## How It Works

### For Home Users:
1. **Login** with email/password
2. **View account** - see plan, status, outstanding balance
3. **Tap "Make Payment"**
4. **Enter amount** - can pay any amount (partial or full)
5. **Confirm phone** - pre-filled with their registered number
6. **Select provider** - choose their mobile money provider
7. **Tap "Pay Now"**
8. **Approve on phone** - receive prompt from mobile money provider
9. **Payment recorded** - automatically tracked in the system

### Payment Tracking:
- Location field: `"HOME_USER"` identifies these as home user payments
- Quantity field: Contains customer ID for linking payment to customer
- Backend can query payments where `location = 'HOME_USER'` to get all home user payments
- Boss can see these payments in analytics/reports

## Backend Integration

### Existing Endpoint Used:
`POST http://167.179.100.104:5000/make-paymentagent`

**Request:**
```json
{
  "phone": "0712345678",
  "amount": "50000",
  "provider": "Airtel",
  "location": "HOME_USER",
  "days": 30,
  "durationSeconds": 2592000,
  "quantity": "12345"
}
```

**Response (Success):**
```json
{
  "success": true,
  "message": "Payment initiated - use voucher now"
}
```

**Response (Error):**
```json
{
  "success": false,
  "error": "Error message here"
}
```

### Payment Recording
The backend (`app.py`) handles:
1. Getting AzamPay access token
2. Initiating mobile money payment
3. Recording transaction in database
4. Returning success/failure to app

### Database Storage
Payments are stored with:
- `phone`: Customer's phone number
- `amount`: Amount paid
- `location`: "HOME_USER" (identifies home user payments)
- `quantity`: Customer ID (for linking)
- `provider`: Mobile money provider used
- `timestamp`: When payment was made

## Querying Home User Payments

### In Python (Flask):
```python
# Get all home user payments
cursor.execute("""
    SELECT * FROM payments 
    WHERE location = 'HOME_USER'
    ORDER BY created_at DESC
""")

# Get payments for specific customer
cursor.execute("""
    SELECT * FROM payments 
    WHERE location = 'HOME_USER' 
    AND quantity = %s
    ORDER BY created_at DESC
""", (customer_id,))
```

### In Firestore (if you migrate):
```dart
// Get all home user payments
await FirebaseFirestore.instance
    .collection('payments')
    .where('location', isEqualTo: 'HOME_USER')
    .orderBy('created_at', descending: true)
    .get();

// Get payments for specific customer
await FirebaseFirestore.instance
    .collection('payments')
    .where('location', isEqualTo: 'HOME_USER')
    .where('quantity', isEqualTo: customerId)
    .orderBy('created_at', descending: true)
    .get();
```

## Linking Payments to Home Internet Billing

### Option 1: Manual Reconciliation (Current)
Boss can:
1. Query payments where `location = 'HOME_USER'`
2. Match `quantity` (customer ID) to home internet customers
3. Manually record payment in Firestore `home_customers/{id}/payments`

### Option 2: Automatic Recording (Future Enhancement)
Add a webhook or scheduled job to:
1. Check for new payments where `location = 'HOME_USER'`
2. Extract customer ID from `quantity` field
3. Automatically create payment record in Firestore:
   ```dart
   await HomeInternetService.addPayment(
     customerId: quantity, // Customer ID from payment
     amountPaid: amount,
     reference: 'Mobile Money Payment',
     notes: 'Auto-recorded from $provider',
   );
   ```

## Testing

### Test Payment Flow:
1. **Create test home user:**
   - Customer ID: 12345
   - Email: test@homeuser.com
   - Password: test123

2. **Login as home user**

3. **Make test payment:**
   - Amount: 1000 TZS (minimum test amount)
   - Phone: Your test number
   - Provider: Airtel (or your provider)

4. **Verify in database:**
   ```sql
   SELECT * FROM payments 
   WHERE location = 'HOME_USER' 
   AND quantity = '12345'
   ORDER BY created_at DESC 
   LIMIT 1;
   ```

5. **Check AzamPay dashboard** for transaction

## Security Considerations

✅ **What's Secure:**
- Home users can only make payments for their own account
- Customer ID is validated before payment
- Uses existing AzamPay integration (already secure)
- HTTPS for API calls
- Phone number validation

⚠️ **Important Notes:**
- Home users can pay any amount (not restricted to plan amount)
- No duplicate payment prevention (user can pay multiple times)
- Payment approval is on mobile money side (AzamPay handles this)

## Future Enhancements

### 1. Payment History in App
Show home users their payment history:
```dart
// Add to HomeUserScreen
Widget _buildPaymentHistory() {
  return FutureBuilder<List<Payment>>(
    future: _fetchPayments(),
    builder: (context, snapshot) {
      // Display list of payments
    },
  );
}
```

### 2. Automatic Payment Recording
Create a Cloud Function or Flask endpoint to automatically record payments in Firestore when they succeed.

### 3. Payment Receipts
Generate and send SMS/email receipts after successful payment.

### 4. Payment Plans
Allow home users to set up recurring payments or payment plans.

### 5. Payment Reminders
Send push notifications or SMS when payment is due.

## Troubleshooting

### Payment fails with "Payment service unavailable"
- Check Flask server is running: `http://167.179.100.104:5000`
- Verify AzamPay credentials are valid
- Check AzamPay token generation

### Payment initiated but not recorded
- Check database connection in Flask
- Verify payment table exists
- Check Flask logs for errors

### User can't see payment button
- Verify user role is 'homeuser'
- Check `home_customer_id` is set in user document
- Ensure customer exists in Firestore

### Phone number not pre-filled
- Check customer record has phone number
- Verify customer ID is correctly linked to user

## Summary

Home users can now:
- ✅ Make payments directly through the app
- ✅ Pay any amount (partial or full payments)
- ✅ Use any mobile money provider
- ✅ See their account status before paying
- ✅ Get immediate feedback on payment status

Payments are tracked with:
- `location = "HOME_USER"` for identification
- `quantity = customer_id` for linking to customer
- Same payment infrastructure as agent payments
- Ready for automatic reconciliation with home internet billing
