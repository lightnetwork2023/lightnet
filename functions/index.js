// Import the necessary modules for Cloud Functions v2
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore"); // Added FieldValue for serverTimestamp
const { getAuth } = require("firebase-admin/auth");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentWritten, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const axios = require("axios"); // For making HTTP requests
const { RouterOSAPI } = require("node-routeros");

// --- Global Constants ---
const FLASK_API_URL = "http://167.179.100.104:5000/get-all-macs";
const FIRESTORE_COLLECTION = "devices";
const LOCATION_NAME = "MBAGALA"; // Location identifier for MikroTik API

// --- Initialize Firebase Admin SDK ---
// This should be called only once when your functions are deployed.
initializeApp();

// --- Global Firestore Instance ---
// Get a reference to the Firestore database globally for reuse across functions.
const db = getFirestore();

// --- Create User Function ---
exports.createUser = onRequest(async (request, response) => {
  // Set CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'GET, POST');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  // Only allow POST requests
  if (request.method !== 'POST') {
    response.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const { email, password, role, name, location, locations, home_customer_id } = request.body;

    // Initialize Firebase Auth (can be done inside the function if specific to auth operations)
    const auth = getAuth();

    // Validate required fields
    if (!email || !password || !role) {
      response.status(400).json({
        error: 'Missing required fields: email, password, and role are required'
      });
      return;
    }

    // Validate role
    const validRoles = ['technician', 'agent', 'superagent', 'boss', 'homeuser'];
    if (!validRoles.includes(role)) {
      response.status(400).json({
        error: 'Invalid role. Must be one of: technician, agent, superagent, boss, homeuser'
      });
      return;
    }

    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      response.status(400).json({ error: 'Invalid email format' });
      return;
    }

    // Validate password length
    if (password.length < 6) {
      response.status(400).json({ error: 'Password must be at least 6 characters long' });
      return;
    }

    // Validate location for agents and superagents
    if (role === 'agent' && (!location || location.trim() === '')) {
      response.status(400).json({ error: 'Location is required for agents' });
      return;
    }

    if (role === 'superagent' && (!locations || !Array.isArray(locations) || locations.length === 0)) {
      response.status(400).json({ error: 'Multiple locations are required for superagents' });
      return;
    }

    // Validate single location for agents
    if (role === 'agent' && location && location.trim() !== '') {
      const locationDoc = await db.collection('locations').doc(location.trim()).get();
      if (!locationDoc.exists) {
        response.status(400).json({ error: `Location '${location}' does not exist in the system` });
        return;
      }
    }

    // Validate multiple locations for superagents
    if (role === 'superagent' && locations && Array.isArray(locations)) {
      for (const loc of locations) {
        if (!loc || loc.trim() === '') {
          response.status(400).json({ error: 'All locations must be valid non-empty strings' });
          return;
        }
        const locationDoc = await db.collection('locations').doc(loc.trim()).get();
        if (!locationDoc.exists) {
          response.status(400).json({ error: `Location '${loc}' does not exist in the system` });
          return;
        }
      }
    }

    // Create user in Firebase Authentication
    const userRecord = await auth.createUser({
      email: email,
      password: password,
    });

    logger.info(`Successfully created user in Authentication: ${userRecord.uid}`);

    // Prepare user data for Firestore
    const userData = {
      email: email,
      role: role,
      name: name || '',
      createdAt: Timestamp.now(), // Use Timestamp.now() for consistency
    };

    // Handle location data based on role
    if (role === 'agent') {
      userData.location = location || '';
      userData.allowed_bundles = {};
    } else if (role === 'superagent') {
      userData.locations = locations || [];
      userData.allowed_bundles = {};
    } else if (role === 'homeuser') {
      // For home users, store the customer ID they're linked to
      userData.home_customer_id = home_customer_id || '';
    } else {
      // For technician and boss roles, store single location if provided
      userData.location = location || '';
    }

    // Create user document in Firestore
    await db.collection('users').doc(userRecord.uid).set(userData);

    logger.info(`Successfully created user document in Firestore: ${userRecord.uid}`);

    // Return success response
    response.status(200).json({
      success: true,
      message: 'User created successfully',
      uid: userRecord.uid,
      email: userRecord.email,
      role: role
    });

  } catch (error) {
    logger.error('Error creating user:', error);

    // Handle specific Firebase Auth errors
    if (error.code === 'auth/email-already-exists') {
      response.status(409).json({ error: 'An account already exists for that email' });
      return;
    }

    if (error.code === 'auth/invalid-email') {
      response.status(400).json({ error: 'Invalid email address' });
      return;
    }

    if (error.code === 'auth/weak-password') {
      response.status(400).json({ error: 'Password is too weak' });
      return;
    }

    // Generic error response
    response.status(500).json({
      error: 'Failed to create user',
      details: error.message
    });
  }
});

async function computeAndUpdateCustomerStatus(customerId) {
  const ref = db.collection('home_customers').doc(customerId);
  const snap = await ref.get();
  if (!snap.exists) return;
  const c = snap.data();
  const now = new Date();
  function tsToDate(v) { if (!v) return null; if (v.toDate) return v.toDate(); if (v instanceof Date) return v; return null; }
  function wd1_7(d) { const w0_6 = d.getDay(); return ((w0_6 + 6) % 7) + 1; }
  function clamp(n, a, b) { return Math.max(a, Math.min(b, n)); }
  const startDate = tsToDate(c.start_date) || new Date();
  const schedule = c.schedule === 'weekly' ? 'weekly' : 'monthly';
  function firstDueWeekly() {
    const anchor = (c.billing_weekday && Number.isInteger(c.billing_weekday)) ? c.billing_weekday : wd1_7(startDate);
    let firstDue = new Date(startDate.getTime());
    const diff = anchor - wd1_7(firstDue);
    if (diff > 0) {
      firstDue.setDate(firstDue.getDate() + diff);
    } else if (diff < 0) {
      firstDue.setDate(firstDue.getDate() + (7 + diff));
    } else {
      firstDue.setDate(firstDue.getDate() + 7);
    }
    return firstDue;
  }
  function weeksBetween(ref) {
    const fd = firstDueWeekly();
    if (ref < fd) return 0;
    const days = Math.floor((ref - fd) / 86400000);
    return Math.floor(days / 7) + 1;
  }
  function weeksDueUpTo(ref) {
    const fd = firstDueWeekly();
    if (ref < fd) return 0;
    const daysDiff = Math.floor((ref - fd) / 86400000);
    const weeksDiff = Math.floor(daysDiff / 7);
    const dueThisWeek = new Date(fd.getTime());
    dueThisWeek.setDate(dueThisWeek.getDate() + 7 * weeksDiff);
    return ref >= dueThisWeek ? (weeksDiff + 1) : weeksDiff;
  }
  function firstDueMonthly() {
    const anchor = clamp(c.billing_day_of_month || startDate.getDate(), 1, 28);
    let firstDue = new Date(startDate.getFullYear(), startDate.getMonth(), anchor, startDate.getHours(), startDate.getMinutes(), startDate.getSeconds(), startDate.getMilliseconds());
    if (firstDue <= startDate) {
      firstDue = new Date(firstDue.getFullYear(), firstDue.getMonth() + 1, anchor, firstDue.getHours(), firstDue.getMinutes(), firstDue.getSeconds(), firstDue.getMilliseconds());
    }
    return firstDue;
  }
  function monthsBetween(ref) {
    const fd = firstDueMonthly();
    if (ref < fd) return 0;
    return (ref.getFullYear() - fd.getFullYear()) * 12 + (ref.getMonth() - fd.getMonth()) + 1;
  }
  function monthsDueUpTo(ref) {
    const fd = firstDueMonthly();
    if (ref < fd) return 0;
    const monthsDiff = (ref.getFullYear() - fd.getFullYear()) * 12 + (ref.getMonth() - fd.getMonth());
    const anchor = clamp(c.billing_day_of_month || startDate.getDate(), 1, 28);
    const dueThisMonth = new Date(
      fd.getFullYear(),
      fd.getMonth() + monthsDiff,
      anchor,
      fd.getHours(),
      fd.getMinutes(),
      fd.getSeconds(),
      fd.getMilliseconds()
    );
    return ref >= dueThisMonth ? (monthsDiff + 1) : monthsDiff;
  }
  function currentPeriod(ref) {
    if (schedule === 'weekly') {
      const fd = firstDueWeekly();
      if (ref < fd) return { start: startDate, end: new Date(fd.getTime() - 1000), due: fd };
      const weeks = weeksBetween(ref);
      const start = new Date(fd.getTime());
      start.setDate(start.getDate() + 7 * (weeks - 1));
      const end = new Date(start.getTime());
      end.setDate(end.getDate() + 7);
      end.setSeconds(end.getSeconds() - 1);
      return { start, end, due: start };
    } else {
      const fd = firstDueMonthly();
      if (ref < fd) return { start: startDate, end: new Date(fd.getTime() - 1000), due: fd };
      const months = monthsBetween(ref);
      const anchor = clamp(c.billing_day_of_month || startDate.getDate(), 1, 28);
      const start = new Date(fd.getFullYear(), fd.getMonth() + (months - 1), anchor, fd.getHours(), fd.getMinutes(), fd.getSeconds(), fd.getMilliseconds());
      const end = new Date(start.getFullYear(), start.getMonth() + 1, anchor);
      end.setSeconds(end.getSeconds() - 1);
      return { start, end, due: start };
    }
  }
  function periodsDueUpToNow(ref) { return schedule === 'weekly' ? weeksDueUpTo(ref) : monthsDueUpTo(ref); }
  function buildPeriods(n) {
    const list = [];
    if (n <= 0) return list;
    if (schedule === 'weekly') {
      const fd = firstDueWeekly();
      for (let i = 0; i < n; i++) {
        const start = new Date(fd.getTime());
        start.setDate(start.getDate() + 7 * i);
        const end = new Date(start.getTime());
        end.setDate(end.getDate() + 7);
        end.setSeconds(end.getSeconds() - 1);
        list.push({ start, end, due: start });
      }
    } else {
      const fd = firstDueMonthly();
      const anchor = clamp(c.billing_day_of_month || startDate.getDate(), 1, 28);
      for (let i = 0; i < n; i++) {
        const start = new Date(fd.getFullYear(), fd.getMonth() + i, anchor, fd.getHours(), fd.getMinutes(), fd.getSeconds(), fd.getMilliseconds());
        const end = new Date(start.getFullYear(), start.getMonth() + 1, anchor);
        end.setSeconds(end.getSeconds() - 1);
        list.push({ start, end, due: start });
      }
    }
    return list;
  }
  const dueCount = periodsDueUpToNow(now);
  const periods = buildPeriods(dueCount);
  const snaps = await ref.collection('plan_snapshots').orderBy('effective_from', 'asc').get();
  const snapshots = snaps.docs.map(d => ({
    amount: Number(d.data().amount) || 0,
    currency: d.data().currency || c.currency || 'TZS',
    effective_from: tsToDate(d.data().effective_from)
  }));
  function requiredFor(date) {
    if (!snapshots.length) return Number(c.plan_amount) || 0;
    let current = snapshots[0];
    for (const s of snapshots) {
      if (!(date < s.effective_from)) current = s; else break;
    }
    return Number(current.amount) || 0;
  }
  const paySnap = await ref.collection('payments').where('status', '==', 'approved').get();
  const payments = paySnap.docs.map(d => d.data());
  payments.sort((a, b) => {
    const aAt = tsToDate(a.approved_at) || tsToDate(a.created_at) || new Date(0);
    const bAt = tsToDate(b.approved_at) || tsToDate(b.created_at) || new Date(0);
    return aAt - bAt;
  });
  let totalPaid = 0;
  let lastPaidAt = null;
  for (const m of payments) {
    const amt = typeof m.amount_paid === 'number' ? m.amount_paid : Number(m.amount_paid) || 0;
    totalPaid += amt;
    const at = tsToDate(m.approved_at) || tsToDate(m.created_at);
    if (at && (!lastPaidAt || at > lastPaidAt)) lastPaidAt = at;
  }
  let totalDue = 0;
  for (const p of periods) totalDue += requiredFor(p.start);
  let remaining = totalPaid;
  const periodStatuses = [];
  for (const p of periods) {
    const required = requiredFor(p.start);
    const allocated = remaining >= required ? required : (remaining > 0 ? remaining : 0);
    remaining = remaining - allocated;
    const state = allocated >= required ? 'paid' : (allocated > 0 ? 'partial' : 'unpaid');
    periodStatuses.push({
      start: Timestamp.fromDate(p.start),
      end: Timestamp.fromDate(p.end),
      due: Timestamp.fromDate(p.due),
      required_amount: Math.round(required * 100) / 100,
      paid_amount: Math.round(allocated * 100) / 100,
      state: state
    });
  }
  const outstanding = totalDue - totalPaid;
  const cp = currentPeriod(now);
  const overdue = outstanding > 0 && now > cp.due;
  const sortKey = overdue ? 2 : (outstanding > 0 ? 1 : 0);
  const status = {
    overdue,
    outstanding_amount: Math.max(0, Math.round(outstanding * 100) / 100),
    total_due_amount: Math.max(0, Math.round(totalDue * 100) / 100),
    total_paid_amount: Math.max(0, Math.round(totalPaid * 100) / 100),
    next_due_date: Timestamp.fromDate(cp.due),
    currency: c.currency || 'TZS',
    updated_at: FieldValue.serverTimestamp(),
    sort_key: sortKey,
    periods: periodStatuses,
  };
  if (lastPaidAt) status.last_paid_at = Timestamp.fromDate(lastPaidAt);
  await ref.set({ status }, { merge: true });
}

exports.onHomeCustomerPaymentWrite = onDocumentWritten("home_customers/{customerId}/payments/{paymentId}", async (event) => {
  const customerId = event.params.customerId;
  try { await computeAndUpdateCustomerStatus(customerId); } catch (e) { logger.error(e); }
});

exports.onHomeCustomerPlanSnapshotWrite = onDocumentWritten("home_customers/{customerId}/plan_snapshots/{snapId}", async (event) => {
  const customerId = event.params.customerId;
  try { await computeAndUpdateCustomerStatus(customerId); } catch (e) { logger.error(e); }
});

exports.onHomeCustomerWrite = onDocumentWritten("home_customers/{customerId}", async (event) => {
  const customerId = event.params.customerId;
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  // Recompute on create, or when key fields change
  if (!before) {
    try { await computeAndUpdateCustomerStatus(customerId); } catch (e) { logger.error(e); }
    return;
  }
  const keys = ['plan_amount','currency','schedule','billing_day_of_month','billing_weekday','start_date'];
  for (const k of keys) {
    if (JSON.stringify(before[k]) !== JSON.stringify(after[k])) {
      try { await computeAndUpdateCustomerStatus(customerId); } catch (e) { logger.error(e); }
      break;
    }
  }
});

exports.sweepOverdueHomeCustomers = onSchedule("every 1 hours", async (event) => {
  try {
    const nowTs = Timestamp.now();
    const q = await db.collection('home_customers')
      .where('status.next_due_date', '<=', nowTs)
      .limit(500)
      .get();
    for (const d of q.docs) { await computeAndUpdateCustomerStatus(d.id); }
  } catch (e) { logger.error(e); }
});

exports.recomputeAllHomeCustomers = onRequest(async (request, response) => {
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.set('Access-Control-Allow-Headers', 'Content-Type');
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }
  try {
    const snapshot = await db.collection('home_customers').get();
    let updated = 0;
    for (const doc of snapshot.docs) {
      try {
        await computeAndUpdateCustomerStatus(doc.id);
        updated++;
      } catch (e) {
        logger.error(`Error updating customer ${doc.id}:`, e);
      }
    }
    response.status(200).json({ 
      success: true, 
      message: `Recomputed status for ${updated} customers`,
      total: snapshot.size
    });
  } catch (error) {
    logger.error('Error in recomputeAllHomeCustomers:', error);
    response.status(500).json({ error: 'Failed to recompute', details: error.message });
  }
});

// --- Store User Location Function (from previous request) ---
/**
 * HTTP Cloud Function to store user location data in Firestore.
 * This function is designed to be triggered by an HTTP POST request from your Flask application.
 *
 * It expects a JSON payload in the request body containing user details.
 *
 * @param req The Express Request object.
 * @param res The Express Response object.
 */
exports.storeUserLocation = onRequest(async (req, res) => {
  // Log the incoming request method and body for debugging purposes.
  logger.info('Received request for storeUserLocation:', req.method, req.body);

  // 1. Validate Request Method: Ensure only POST requests are processed.
  if (req.method !== 'POST') {
    logger.warn(`Method Not Allowed for storeUserLocation: Received a ${req.method} request.`);
    return res.status(405).send('Method Not Allowed');
  }

  // 2. Validate Request Body: Ensure it's a valid JSON object.
  if (!req.body || typeof req.body !== 'object') {
    logger.error('Bad Request for storeUserLocation: Request body is missing or not a JSON object.');
    return res.status(400).send('Bad Request: Request body must be a JSON object.');
  }

  // 3. Extract User Data: Destructure the expected fields from the request body.
  const { username, location, speed_limit, session_timeout, password } = req.body;

  // 4. Basic Data Validation: Check for essential fields.
  if (!username || !location || session_timeout === undefined) { // session_timeout can be 0, so check for undefined
    logger.error('Bad Request for storeUserLocation: Missing required user data (username, location, session_timeout).', req.body);
    return res.status(400).send('Bad Request: Missing required user data (username, location, session_timeout).');
  }

  try {
    // Ensure the location document exists in the 'locations' collection.
    // The document ID will be the 'location' string itself.
    const locationDocRef = db.collection('locations').doc(location);

    // Use .set with { merge: true } to create the document if it doesn't exist
    // or update it without overwriting existing fields if it does.
    // Here, we might just store a 'name' field for the location itself.
    await locationDocRef.set({
      name: location, // Store the location name as a field within the location document
      lastUserAddedAt: FieldValue.serverTimestamp() // Optional: track when a user was last added to this location
    }, { merge: true }); // Use merge to avoid overwriting if the location document already exists

    logger.info(`Ensured location document '${location}' exists.`);

    // Now, store the user's specific data in a subcollection 'users' under this location document.
    // The document ID for the user will be their 'username'.
    const userLocationDocRef = locationDocRef.collection('users').doc(username);

    await userLocationDocRef.set({
      username: username, // Store username explicitly as a field within the user's document
      speed_limit: speed_limit || null,
      session_timeout: session_timeout,
      password: password, // WARNING: Storing plain text passwords is a security risk.
      createdAt: FieldValue.serverTimestamp()
    });

    logger.info(`Successfully stored user ${username} data under location '${location}' in Firestore.`);
    // 7. Send Success Response: Confirm that the data was stored.
    return res.status(200).send({ message: `User ${username} data stored successfully under location '${location}' in Firestore.` });

  } catch (error) {
    // 8. Handle Errors: Log and send an appropriate error response if something goes wrong.
    logger.error('Error storing user data in Firestore via storeUserLocation:', error);
    return res.status(500).send('Internal Server Error: Failed to store user data.');
  }
});

// --- New: Delete User From Location Function ---
/**
 * HTTP Cloud Function to delete a user from a specific location's subcollection in Firestore.
 * This function expects a JSON payload in the request body containing 'username' and 'location'.
 *
 * @param req The Express Request object.
 * @param res The Express Response object.
 */
exports.deleteUserFromLocation = onRequest(async (req, res) => {
  logger.info('Received request for deleteUserFromLocation:', req.method, req.body);

  if (req.method !== 'POST') {
    logger.warn(`Method Not Allowed for deleteUserFromLocation: Received a ${req.method} request.`);
    return res.status(405).send('Method Not Allowed');
  }

  if (!req.body || typeof req.body !== 'object') {
    logger.error('Bad Request for deleteUserFromLocation: Request body is missing or not a JSON object.');
    return res.status(400).send('Bad Request: Request body must be a JSON object.');
  }

  const { username, location } = req.body;

  if (!username || !location) {
    logger.error('Bad Request for deleteUserFromLocation: Missing required data (username, location).', req.body);
    return res.status(400).send('Bad Request: Missing required data (username, location).');
  }

  try {
    // Reference the specific user document within the location's subcollection.
    const userDocRef = db.collection('locations').doc(location).collection('users').doc(username);

    // Check if the document exists before attempting to delete it.
    const docSnapshot = await userDocRef.get();
    if (!docSnapshot.exists) {
      logger.warn(`User ${username} not found under location ${location}. No deletion performed.`);
      return res.status(404).send({ message: `User ${username} not found under location ${location}.` });
    }

    // Delete the document.
    await userDocRef.delete();

    logger.info(`Successfully deleted user ${username} from location '${location}' in Firestore.`);
    return res.status(200).send({ message: `User ${username} deleted successfully from location '${location}'.` });

  } catch (error) {
    logger.error('Error deleting user from Firestore via deleteUserFromLocation:', error);
    return res.status(500).send('Internal Server Error: Failed to delete user data.');
  }
});


// --- Delete App User Function ---
// Deletes a Firebase Authentication user and their Firestore user document.
exports.deleteAppUser = onRequest(async (request, response) => {
  // CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  if (request.method !== 'POST') {
    response.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const { uid, email } = request.body || {};
    const auth = getAuth();
    let targetUid = uid;

    // Resolve UID by email if needed
    if (!targetUid && email) {
      const userRecord = await auth.getUserByEmail(email);
      targetUid = userRecord.uid;
    }

    if (!targetUid) {
      response.status(400).json({ error: 'Missing uid or email' });
      return;
    }

    // Delete from Firebase Auth
    await auth.deleteUser(targetUid);

    // Delete Firestore user document
    await db.collection('users').doc(targetUid).delete();

    response.status(200).json({ success: true, message: 'User deleted successfully', uid: targetUid });
  } catch (error) {
    logger.error('Error deleting user:', error);
    const status = error.code === 'auth/user-not-found' ? 404 : 500;
    response.status(status).json({ error: 'Failed to delete user', details: error.message });
  }
});


// --- MikroTik API Configuration ---
const mikrotikConfig = {
  host: "41.59.115.231",
  user: "admin", // Replace with your MikroTik username
  password: "ROCKY221122", // Replace with your MikroTik password
  port: 8728, // Default API port
};

// --- Update Network Snapshot Function ---
exports.updateNetworkSnapshot = onRequest(async (request, response) => {
  // Log the start of the function execution for better debugging
  logger.info("updateNetworkSnapshot function triggered", { query: request.query });

  const mac = request.query.mac;
  const ip = request.query.ip || ''; // Default to empty string if IP is not provided

  if (!mac) {
    logger.error("Request is missing the required 'mac' parameter in updateNetworkSnapshot.");
    response.status(400).json({ error: 'Missing mac parameter' });
    return; // Exit the function
  }

  try {
    // Use the globally initialized 'db' instance
    const docRef = db.collection('active_macs').doc(mac);

    await docRef.set({
      mac: mac,
      ip: ip,
      lastSeen: Timestamp.now() // Use the v2 Admin SDK Timestamp
    });

    logger.info(`Successfully updated MAC: ${mac} with IP: ${ip} in active_macs.`);
    response.status(200).json({ status: 'ok', mac, ip });

  } catch (error) {
    logger.error(`Error writing to Firestore for MAC [${mac}] in updateNetworkSnapshot`, error);
    response.status(500).json({ error: 'Internal Server Error', details: error.message });
  }
});

// --- AzamPay Payment Processing ---
const AZAM_CLIENT_ID = 'c7b6bda0-9a3f-47fb-b365-1110dfc37089';
const AZAM_CLIENT_SECRET = 'EsOPLBAfwnLGCQUHOqjMaTqXm/nPv4A8o0WndaEZ4yJ9oJYLkVgPHeQvKPKA2exyvWEAnFL0fBipGq1Qbll6ePoPNfYdsIxYGd5g9UhyK1l8ytGnS3XQj6GUjCfo0J35sb0wgdFwpruktQ2a9SXdKMkuaCtjHPesNHCqPtoy9fUZmabAh7Igi5ZSA2UlTP8WQjaXmaoYEn8aJ1AQxCIEcaIo+DijH7w4hsCmoVWQTHnfpuYDrz3ndpE0eAPRfP381UBxNPuuedtckpTILuGtvRPKgxMAdQh/Lf38tlNnedsSOXm1aZZFa3Vgm8N+Epk338gspvc1syAmOmnUtAFCQqShiUrgiA8SZqzYerMvGWAteprO+B89l2PdL2LXjYcbVyyyGiptCoKEsCaHIRgitNydEMYsEfHhlygEvMCuBqMzWrPlJgugeGD0GlhNW1gR9iq2GLQzRHYwfrSJeFBo1oQb0frIS7tBHy5WisaDJtJalOWOmEy5UuLAVSg8PHVXJ94yOEA9mdg9x4HV0x+bA5JSi0+29tVC59HPly+N9BvsYVRIGWsqW82Ki3OOpZuRtc7O4/YfhrNplTxBBCv6+SDqF5bCKJpNwXKV9t9peAFe39Jy18DMnZ8WnmYMKh4FP2YQUfE4XWnoXhPuRswSw6eRevNiYIYEZbP6YsLPlNY=';

// Token caching
let accessToken = null;
let tokenExpiry = null;

// Function to get access token from AzamPay
async function getAzamPayToken() {
  // Check if we have a valid token
  if (accessToken && tokenExpiry && new Date() < tokenExpiry) {
    return accessToken;
  }

  try {
    const response = await axios.post(
      'https://authenticator.azampay.co.tz/AppRegistration/GenerateToken',
      {
        appName: 'lightnet',
        clientId: AZAM_CLIENT_ID,
        clientSecret: AZAM_CLIENT_SECRET
      },
      {
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': 'LightNet-Server/1.0'
        },
        timeout: 30000 // 30 seconds timeout
      }
    );

    if (response.data && response.data.data && response.data.data.accessToken) {
      accessToken = response.data.data.accessToken;
      
      // Set token expiry (default to 1 hour if not provided)
      const expiresInMs = response.data.data.expiresIn || 3600 * 1000;
      tokenExpiry = new Date(Date.now() + expiresInMs);
      
      logger.info('Successfully obtained AzamPay access token');
      return accessToken;
    }
    
    throw new Error('Invalid token response from AzamPay');
  } catch (error) {
    logger.error('Failed to get AzamPay token:', error.message);
    throw new Error(`Payment service unavailable: ${error.message}`);
  }
}

// Main payment processing function
exports.processPayment = onRequest({ cors: true }, async (req, res) => {
  // Set CORS headers
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (req.method === 'OPTIONS') {
    res.status(204).send('');
    return;
  }

  // Only allow POST requests
  if (req.method !== 'POST') {
    res.status(405).json({ success: false, error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const { phone, amount, provider, location, durationSeconds, macAddress, nasIp, quantity } = req.body;
    
    // Validate required fields
    if (!phone || !amount || !provider || !location || !durationSeconds) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: phone, amount, provider, location, and durationSeconds are required'
      });
    }

    // Generate a random voucher code (12 digits)
    const voucherCode = Math.floor(100000000000 + Math.random() * 900000000000).toString();
    
    // Get AzamPay access token
    const token = await getAzamPayToken();
    
    // Use provided macAddress or set to null for optional usage
    const finalMacAddress = macAddress || null;
    
    // Prepare payment payload
    const payload = {
      accountNumber: phone,
      amount: amount.toString(),
      currency: 'TZS',
      externalId: require('crypto').randomUUID(),
      provider: provider,
      additionalProperties: {
        voucher: voucherCode,
        duration: durationSeconds.toString(),
        location: location,
        ...(macAddress && { mac_address: macAddress }),
        ...(nasIp && { nas_ip: nasIp }),
        ...(quantity && { quantity: quantity.toString() })
      }
    };

    // Make payment request to AzamPay
    const paymentResponse = await axios.post(
      'https://checkout.azampay.co.tz/azampay/mno/checkout',
      payload,
      {
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`,
          'X-API-Key': 'none'
        },
        timeout: 15000 // 15 seconds timeout
      }
    );

    // Log successful payment initiation
    logger.info('Payment initiated successfully', {
      voucherCode,
      phone,
      amount,
      location,
      provider,
      macAddress
    });

    // Return success response with voucher code
    return res.status(200).json({
      success: true,
      voucherCode,
      message: 'Payment initiated - use voucher now'
    });

  } catch (error) {
    // Log the error
    logger.error('Payment processing error:', error.response?.data || error.message);
    
    // Return appropriate error response
    const statusCode = error.response?.status || 500;
    const errorMessage = error.response?.data?.message || error.message || 'Payment processing failed';
    
    return res.status(statusCode).json({
      success: false,
      error: errorMessage,
      details: error.response?.data || {}
    });
  }
});

// --- Store Home User Payment Function ---
/**
 * HTTP Cloud Function to store successful home user payment in Firestore.
 * This function is called after a successful payment to record it in the customer's payment collection.
 * 
 * Expected payload:
 * {
 *   "customerId": "12345",
 *   "amount": 50000,
 *   "phone": "0712345678",
 *   "provider": "Airtel",
 *   "reference": "AZM123456789",
 *   "createdByName": "Customer Name"
 * }
 */
exports.storeHomeUserPayment = onRequest(async (request, response) => {
  // Set CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  // Only allow POST requests
  if (request.method !== 'POST') {
    response.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const { customerId, amount, phone, provider, reference, createdByName } = request.body;

    // Validate required fields
    if (!customerId || !amount || !phone || !provider) {
      response.status(400).json({
        error: 'Missing required fields: customerId, amount, phone, and provider are required'
      });
      return;
    }

    // Verify customer exists
    const customerRef = db.collection('home_customers').doc(customerId);
    const customerSnap = await customerRef.get();
    
    if (!customerSnap.exists) {
      response.status(404).json({ error: 'Customer not found' });
      return;
    }

    const customerData = customerSnap.data();

    // Create payment record
    const paymentData = {
      customer_id: customerId,
      amount_paid: parseFloat(amount),
      currency: 'TZS',
      attachments: [],
      status: 'approved', // Auto-approve mobile money payments
      created_by_uid: 'system',
      created_by_name: createdByName || customerData.name || 'Home User',
      created_at: FieldValue.serverTimestamp(),
      approved_by_uid: 'system',
      approved_by_name: 'Auto-Approved',
      approved_at: FieldValue.serverTimestamp(),
      schedule: customerData.schedule || 'monthly',
      period_start: Timestamp.now(),
      period_end: Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)), // 30 days from now
      due_date: Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
      reference: reference || `${provider}-${phone}`,
      notes: `Mobile money payment via ${provider}`,
      payment_type: provider,
      customer_zone: customerData.zone || '',
      customer_type: customerData.customer_type || '',
    };

    // Store payment in customer's payments subcollection
    const paymentRef = await customerRef.collection('payments').add(paymentData);

    logger.info(`Successfully stored payment for customer ${customerId}`, {
      paymentId: paymentRef.id,
      amount: amount,
      provider: provider
    });

    // Return success response
    response.status(200).json({
      success: true,
      message: 'Payment recorded successfully',
      paymentId: paymentRef.id,
      customerId: customerId
    });

  } catch (error) {
    logger.error('Error storing home user payment:', error);
    response.status(500).json({
      error: 'Failed to store payment',
      details: error.message
    });
  }
});

// --- Reset User Password Function ---
exports.resetUserPassword = onRequest(async (request, response) => {
  // Set CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'GET, POST');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  // Only allow POST requests
  if (request.method !== 'POST') {
    response.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const { email, newPassword } = request.body;

    // Validate required fields
    if (!email || !newPassword) {
      response.status(400).json({
        error: 'Missing required fields: email and newPassword are required'
      });
      return;
    }

    // Validate password length
    if (newPassword.length < 6) {
      response.status(400).json({ error: 'Password must be at least 6 characters long' });
      return;
    }

    const auth = getAuth();

    // Get user by email
    const userRecord = await auth.getUserByEmail(email);

    // Update the user's password
    await auth.updateUser(userRecord.uid, {
      password: newPassword
    });

    logger.info(`Password reset successfully for user: ${email}`);

    response.status(200).json({
      success: true,
      message: 'Password reset successfully'
    });

  } catch (error) {
    logger.error('Error resetting password:', error);
    
    if (error.code === 'auth/user-not-found') {
      response.status(404).json({ error: 'User not found with this email' });
    } else if (error.code === 'auth/invalid-email') {
      response.status(400).json({ error: 'Invalid email address' });
    } else {
      response.status(500).json({
        error: 'Failed to reset password',
        details: error.message
      });
    }
  }
});

// --- Store Payment Data Function (Cloud Function v2) ---
/**
 * HTTP Cloud Function to store payment data in Firestore after successful payment callback.
 * This function is called from Flask app.py after a successful payment to sync data to Firestore.
 * 
 * Expected payload:
 * {
 *   "voucher": "123456789012",
 *   "location": "MBAGALA",
 *   "sublocation": "MBAGALA-A",  // optional
 *   "amount": 5000,
 *   "duration": 86400,
 *   "phone": "0712345678",
 *   "mac_address": "AA:BB:CC:DD:EE:FF",  // optional
 *   "payment_method": "Airtel",  // optional
 *   "transaction_id": "AZM123456789",  // optional
 *   "created_by": "Agent Name",
 *   "payment_type": "voucher"
 * }
 */
exports.storePaymentData = onRequest(async (request, response) => {
  // Set CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight requests
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  // Only allow POST requests
  if (request.method !== 'POST') {
    response.status(405).json({ error: 'Method not allowed. Use POST.' });
    return;
  }

  try {
    const {
      voucher,
      location,
      amount,
      duration,
      phone,
      mac_address,
      payment_method,
      transaction_id,
      created_by,
      payment_type,
      timestamp
    } = request.body;

    // Validate required fields
    if (!location || !amount || !phone) {
      response.status(400).json({
        error: 'Missing required fields: location, amount, and phone are required'
      });
      return;
    }

    const amountFloat = parseFloat(amount);

    // STEP 1: Get location document and detect if it's a sublocation
    const locationRef = db.collection('locations').doc(location);
    let locationDoc = await locationRef.get();
    
    // Create location if it doesn't exist
    if (!locationDoc.exists) {
      logger.warn(`Location '${location}' does not exist, creating as main location...`);
      await locationRef.set({
        parent_location: null,
        type: 'main',
        created_at: FieldValue.serverTimestamp(),
        auto_created: true
      });
      locationDoc = await locationRef.get();
    }

    // Get parent_location to determine hierarchy
    const locationData = locationDoc.data() || {};
    const parentLocation = locationData.parent_location || null;
    const isSublocation = parentLocation !== null;

    logger.info(`Processing payment for ${location}`, {
      isSublocation,
      parentLocation,
      amount: amountFloat
    });

    // STEP 2: Store payment with hierarchy info
    const paymentData = {
      voucher: voucher || null,
      location: location,
      parent_location: parentLocation,  // Auto-detected!
      is_sublocation: isSublocation,
      amount: amountFloat,
      duration: parseInt(duration) || 0,
      phone: phone,
      mac_address: mac_address || null,
      payment_method: payment_method || 'unknown',
      transaction_id: transaction_id || null,
      created_by: created_by || 'system',
      payment_type: payment_type || 'voucher',
      created_at: timestamp ? Timestamp.fromDate(new Date(timestamp)) : FieldValue.serverTimestamp(),
      synced_at: FieldValue.serverTimestamp()
    };

    const paymentRef = await db.collection('payments').add(paymentData);

    // STEP 3: Update location metadata (always)
    await locationRef.set({
      metadata: {
        total_revenue: FieldValue.increment(amountFloat),
        payment_count: FieldValue.increment(1),
        last_payment_at: FieldValue.serverTimestamp(),
        last_updated: FieldValue.serverTimestamp()
      }
    }, { merge: true });

    // STEP 4: If this is a sublocation, ALSO update parent metadata
    if (isSublocation && parentLocation) {
      const parentRef = db.collection('locations').doc(parentLocation);
      const parentDoc = await parentRef.get();
      
      if (parentDoc.exists) {
        await parentRef.set({
          metadata: {
            total_revenue: FieldValue.increment(amountFloat),
            payment_count: FieldValue.increment(1),
            last_payment_at: FieldValue.serverTimestamp(),
            last_updated: FieldValue.serverTimestamp()
          }
        }, { merge: true });
        
        logger.info(`Updated parent location '${parentLocation}' with +${amountFloat}`);
      } else {
        logger.warn(`Parent location '${parentLocation}' does not exist!`);
      }
    }

    logger.info(`Successfully stored payment in Firestore`, {
      paymentId: paymentRef.id,
      location: location,
      parentLocation: parentLocation,
      isSublocation: isSublocation,
      amount: amountFloat
    });

    // Return success response
    response.status(200).json({
      success: true,
      message: 'Payment data stored successfully in Firestore',
      paymentId: paymentRef.id,
      location: location,
      parent_location: parentLocation,
      is_sublocation: isSublocation
    });

  } catch (error) {
    logger.error('Error storing payment data in Firestore:', error);
    response.status(500).json({
      error: 'Failed to store payment data',
      details: error.message
    });
  }
});

// --- Get Location Analytics Function (Hybrid Approach) ---
/**
 * Get analytics for a location including time-based queries
 * Supports: today, 24h, month, year
 * Automatically includes sublocations in the totals
 */
exports.getLocationAnalytics = onRequest(async (request, response) => {
  // Set CORS headers
  response.set('Access-Control-Allow-Origin', '*');
  response.set('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  response.set('Access-Control-Allow-Headers', 'Content-Type');

  // Handle preflight
  if (request.method === 'OPTIONS') {
    response.status(204).send('');
    return;
  }

  try {
    const { location, period } = request.method === 'POST' ? request.body : request.query;

    if (!location) {
      response.status(400).json({ error: 'Missing location parameter' });
      return;
    }

    // STEP 1: Get all sublocations of this location
    const sublocationsSnapshot = await db.collection('locations')
      .where('parent_location', '==', location)
      .get();

    const locationIds = [location, ...sublocationsSnapshot.docs.map(doc => doc.id)];

    logger.info(`Fetching analytics for ${location}`, {
      period,
      includesSublocations: locationIds.length > 1,
      locations: locationIds
    });

    // STEP 2: Get quick stats from metadata (fast!)
    const locationDoc = await db.collection('locations').doc(location).get();
    const metadata = locationDoc.exists ? locationDoc.data().metadata || {} : {};

    const quickStats = {
      total_revenue: metadata.total_revenue || 0,
      payment_count: metadata.payment_count || 0,
      last_payment_at: metadata.last_payment_at || null
    };

    // STEP 3: If period specified, query payments collection
    let detailedStats = null;
    if (period) {
      let startDate;
      const now = new Date();

      switch (period) {
        case 'today':
          startDate = new Date(now);
          startDate.setHours(0, 0, 0, 0);
          break;
        case '24h':
          startDate = new Date(now.getTime() - 24 * 60 * 60 * 1000);
          break;
        case 'month':
          startDate = new Date(now.getFullYear(), now.getMonth(), 1);
          break;
        case 'year':
          startDate = new Date(now.getFullYear(), 0, 1);
          break;
        default:
          response.status(400).json({ 
            error: 'Invalid period. Use: today, 24h, month, or year' 
          });
          return;
      }

      // Query payments for the period
      const paymentsQuery = db.collection('payments')
        .where('location', 'in', locationIds)
        .where('created_at', '>=', Timestamp.fromDate(startDate));

      const paymentsSnapshot = await paymentsQuery.get();

      let totalAmount = 0;
      const breakdown = {};
      const sublocationBreakdown = {};

      paymentsSnapshot.forEach(doc => {
        const data = doc.data();
        totalAmount += data.amount;
        
        // Breakdown by location
        breakdown[data.location] = (breakdown[data.location] || 0) + data.amount;
        
        // Count for sublocation
        if (data.parent_location === location && data.location !== location) {
          sublocationBreakdown[data.location] = (sublocationBreakdown[data.location] || 0) + data.amount;
        }
      });

      detailedStats = {
        period: period,
        start_date: startDate.toISOString(),
        total_amount: totalAmount,
        payment_count: paymentsSnapshot.size,
        breakdown: breakdown,
        sublocation_breakdown: sublocationBreakdown
      };
    }

    // STEP 4: Get sublocation metadata for quick overview
    const sublocationsData = {};
    for (const subDoc of sublocationsSnapshot.docs) {
      const subData = subDoc.data();
      sublocationsData[subDoc.id] = {
        total_revenue: subData.metadata?.total_revenue || 0,
        payment_count: subData.metadata?.payment_count || 0
      };
    }

    response.status(200).json({
      success: true,
      location: location,
      includes_sublocations: locationIds.length > 1,
      sublocation_ids: locationIds.filter(id => id !== location),
      quick_stats: quickStats,
      detailed_stats: detailedStats,
      sublocations: sublocationsData
    });

  } catch (error) {
    logger.error('Error fetching location analytics:', error);
    response.status(500).json({
      error: 'Failed to fetch analytics',
      details: error.message
    });
  }
});

