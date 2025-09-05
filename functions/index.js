// Import the necessary modules for Cloud Functions v2
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp, FieldValue } = require("firebase-admin/firestore"); // Added FieldValue for serverTimestamp
const { getAuth } = require("firebase-admin/auth");
const { onSchedule } = require("firebase-functions/v2/scheduler");
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
    const { email, password, role, name, location, locations } = request.body;

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
    const validRoles = ['technician', 'agent', 'superagent', 'boss'];
    if (!validRoles.includes(role)) {
      response.status(400).json({
        error: 'Invalid role. Must be one of: technician, agent, superagent, boss'
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
