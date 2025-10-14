# Cloud Function: Store Home User Payment

## Overview
This Cloud Function automatically stores successful home user payments in Firestore under the customer's payment collection, making them immediately visible in the admin dashboard and analytics.

## What I Implemented

### 1. Cloud Function (`storeHomeUserPayment`)
**File:** `functions/index.js`

**Endpoint:** 
```
https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment
```

**Method:** POST

**Purpose:**
- Receives payment details after successful mobile money transaction
- Validates customer exists
- Creates payment record in Firestore
- Auto-approves the payment (no manual approval needed)
- Links payment to customer's billing periods

### 2. Flutter Integration
**File:** `lib/screens/HomeUserPaymentScreen.dart`

**Changes:**
- Added `_storePaymentInFirestore()` method
- Calls Cloud Function after successful payment
- Handles errors gracefully (doesn't fail payment if storage fails)

## How It Works

### Payment Flow:
1. **Home user makes payment** → AzamPay API
2. **Payment succeeds** → AzamPay confirms
3. **App calls Cloud Function** → `storeHomeUserPayment`
4. **Cloud Function:**
   - Validates customer exists
   - Creates payment record in Firestore
   - Auto-approves payment
   - Returns success
5. **User sees confirmation** → "Payment successful! Your payment has been recorded."

### Data Flow:
```
Home User App
    ↓
AzamPay Payment API (Flask)
    ↓
Payment Success
    ↓
Cloud Function (storeHomeUserPayment)
    ↓
Firestore: home_customers/{id}/payments/{paymentId}
    ↓
Visible in Boss Dashboard
```

## API Specification

### Request

**URL:** `https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment`

**Method:** POST

**Headers:**
```json
{
  "Content-Type": "application/json"
}
```

**Body:**
```json
{
  "customerId": "12345",
  "amount": 50000,
  "phone": "0712345678",
  "provider": "Airtel",
  "reference": "Mobile-Airtel-1234567890",
  "createdByName": "John Doe"
}
```

**Required Fields:**
- `customerId` (string) - 5-digit customer ID
- `amount` (number) - Amount paid in TZS
- `phone` (string) - Customer's phone number
- `provider` (string) - Payment provider (Airtel, Tigo, Mpesa, Halopesa, Azampesa)

**Optional Fields:**
- `reference` (string) - Payment reference/transaction ID
- `createdByName` (string) - Customer name (defaults to customer record name)

### Response

**Success (200):**
```json
{
  "success": true,
  "message": "Payment recorded successfully",
  "paymentId": "abc123xyz",
  "customerId": "12345"
}
```

**Error (400) - Missing Fields:**
```json
{
  "error": "Missing required fields: customerId, amount, phone, and provider are required"
}
```

**Error (404) - Customer Not Found:**
```json
{
  "error": "Customer not found"
}
```

**Error (500) - Server Error:**
```json
{
  "error": "Failed to store payment",
  "details": "Error message here"
}
```

## Firestore Structure

### Payment Record Created:
**Path:** `home_customers/{customerId}/payments/{paymentId}`

**Document:**
```javascript
{
  customer_id: "12345",
  amount_paid: 50000,
  currency: "TZS",
  attachments: [],
  status: "approved",
  created_by_uid: "system",
  created_by_name: "John Doe",
  created_at: Timestamp,
  approved_by_uid: "system",
  approved_by_name: "Auto-Approved",
  approved_at: Timestamp,
  schedule: "monthly",
  period_start: Timestamp,
  period_end: Timestamp, // 30 days from now
  due_date: Timestamp, // 30 days from now
  reference: "Mobile-Airtel-1234567890",
  notes: "Mobile money payment via Airtel",
  payment_type: "Airtel",
  customer_zone: "Zone A",
  customer_type: "Residential"
}
```

### Key Features:
- **Auto-approved:** Status is immediately set to "approved"
- **System user:** Created by "system" user (not requiring manual approval)
- **Billing period:** Automatically sets 30-day period from payment date
- **Denormalized data:** Includes customer zone and type for analytics
- **Payment type:** Stores provider name for tracking

## Deployment

### Deploy the Cloud Function:

```bash
cd c:\Users\LITtech\AndroidStudioProjects\lightnetwork
firebase deploy --only functions:storeHomeUserPayment
```

Or deploy all functions:
```bash
firebase deploy --only functions
```

### Verify Deployment:

1. Check Firebase Console → Functions
2. Look for `storeHomeUserPayment` function
3. Status should be "Healthy"
4. URL should be: `https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment`

## Testing

### Test the Cloud Function:

**Using curl:**
```bash
curl -X POST https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "12345",
    "amount": 1000,
    "phone": "0712345678",
    "provider": "Airtel",
    "reference": "TEST-123",
    "createdByName": "Test User"
  }'
```

**Using Postman:**
1. Method: POST
2. URL: `https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment`
3. Headers: `Content-Type: application/json`
4. Body (raw JSON):
   ```json
   {
     "customerId": "12345",
     "amount": 1000,
     "phone": "0712345678",
     "provider": "Airtel"
   }
   ```

### Test End-to-End:

1. **Create test home user account**
2. **Login as home user**
3. **Make test payment:**
   - Amount: 1000 TZS
   - Phone: Your test number
   - Provider: Airtel
4. **Approve payment on phone**
5. **Check Firestore:**
   - Navigate to `home_customers/{customerId}/payments`
   - Verify payment record exists
   - Status should be "approved"
6. **Check Boss Dashboard:**
   - Login as boss
   - View customer payments
   - Payment should appear in list

## Benefits

### ✅ Automatic Recording
- No manual entry needed
- Payment recorded immediately after success
- Boss sees payment in real-time

### ✅ Auto-Approval
- Mobile money payments are trusted
- No manual approval workflow needed
- Reduces boss workload

### ✅ Complete Tracking
- All payment details stored
- Provider information tracked
- Reference numbers saved
- Timestamps recorded

### ✅ Analytics Ready
- Denormalized zone and customer type
- Can query by payment type
- Integrates with existing analytics

### ✅ Billing Integration
- Automatically creates billing period
- Sets due date 30 days out
- Links to customer's payment schedule

## Monitoring

### View Cloud Function Logs:

**Firebase Console:**
1. Go to Firebase Console → Functions
2. Click on `storeHomeUserPayment`
3. Click "Logs" tab
4. View execution logs

**Firebase CLI:**
```bash
firebase functions:log --only storeHomeUserPayment
```

### Check for Errors:

**Look for:**
- Failed customer lookups (404 errors)
- Missing fields (400 errors)
- Firestore write failures (500 errors)

**Common Issues:**
- Customer ID doesn't exist
- Invalid amount format
- Firestore permissions
- Network timeouts

## Security

### ✅ What's Secure:
- Validates customer exists before storing
- Validates required fields
- Uses Firebase Admin SDK (server-side)
- CORS enabled for app access
- Logs all operations

### ⚠️ Considerations:
- No authentication on Cloud Function (relies on app security)
- Anyone with URL can call it (but needs valid customer ID)
- Consider adding API key or Firebase Auth token validation

### Future Enhancement - Add Auth:
```javascript
// Verify Firebase Auth token
const idToken = request.headers.authorization?.split('Bearer ')[1];
if (!idToken) {
  response.status(401).json({ error: 'Unauthorized' });
  return;
}

const decodedToken = await admin.auth().verifyIdToken(idToken);
// Verify user is homeuser role and matches customerId
```

## Troubleshooting

### Payment succeeds but not recorded in Firestore

**Check:**
1. Cloud Function deployed? `firebase functions:list`
2. Cloud Function URL correct in app?
3. Customer ID exists in Firestore?
4. Check Cloud Function logs for errors

**Solution:**
```bash
# Redeploy function
firebase deploy --only functions:storeHomeUserPayment

# Check logs
firebase functions:log --only storeHomeUserPayment
```

### Error: "Customer not found"

**Cause:** Customer ID doesn't exist in `home_customers` collection

**Solution:**
- Verify customer was created properly
- Check customer ID matches exactly
- Ensure customer not archived

### Error: "Failed to store payment"

**Cause:** Firestore write permission or data validation issue

**Solution:**
- Check Firestore security rules
- Verify all required fields present
- Check Cloud Function has Firestore write access

### Payment recorded twice

**Cause:** User tapped "Pay Now" multiple times or network retry

**Solution:**
- Add idempotency key (use transaction ID)
- Check for duplicate payments before creating
- Add loading state to prevent double-tap

## Future Enhancements

### 1. Idempotency
Prevent duplicate payments:
```javascript
// Check if payment with same reference already exists
const existingPayment = await customerRef
  .collection('payments')
  .where('reference', '==', reference)
  .limit(1)
  .get();

if (!existingPayment.empty) {
  return response.status(200).json({
    success: true,
    message: 'Payment already recorded',
    paymentId: existingPayment.docs[0].id
  });
}
```

### 2. SMS Notification
Send SMS receipt after payment:
```javascript
// After storing payment
await sendSMS({
  to: phone,
  message: `Payment received: TZS ${amount}. Thank you!`
});
```

### 3. Email Receipt
Send email receipt:
```javascript
await sendEmail({
  to: customerData.email,
  subject: 'Payment Receipt',
  body: `Your payment of TZS ${amount} has been received.`
});
```

### 4. Webhook from AzamPay
Instead of app calling function, AzamPay calls it directly:
```javascript
// Verify AzamPay signature
const signature = request.headers['x-azampay-signature'];
if (!verifySignature(signature, request.body)) {
  return response.status(401).json({ error: 'Invalid signature' });
}
```

## Summary

The Cloud Function provides:
- ✅ Automatic payment recording in Firestore
- ✅ Auto-approval of mobile money payments
- ✅ Complete payment tracking with all details
- ✅ Integration with existing billing system
- ✅ Real-time visibility for boss dashboard
- ✅ Analytics-ready data structure
- ✅ Error handling and logging

**Result:** Home users can make payments that are immediately recorded and visible to the boss, with no manual intervention needed.
