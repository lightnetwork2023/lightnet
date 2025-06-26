// Import the necessary modules for Cloud Functions v2
const { onRequest } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const axios = require("axios"); // For making HTTP requests
const FLASK_API_URL = "http://167.179.100.104:5000/get-all-macs";
const FIRESTORE_COLLECTION = "devices";
const { RouterOSAPI } = require("node-routeros");

// Initialize Firebase Admin SDK
initializeApp();

// Create user function
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
    const { email, password, role, name, location } = request.body;

    // Initialize Firebase services
    const auth = getAuth();
    const db = getFirestore();

    // Validate required fields
    if (!email || !password || !role) {
      response.status(400).json({ 
        error: 'Missing required fields: email, password, and role are required' 
      });
      return;
    }

    // Validate role
    const validRoles = ['technician', 'agent', 'boss'];
    if (!validRoles.includes(role)) {
      response.status(400).json({ 
        error: 'Invalid role. Must be one of: technician, agent, boss' 
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

    // Validate location for agents
    if (role === 'agent' && (!location || location.trim() === '')) {
      response.status(400).json({ error: 'Location is required for agents' });
      return;
    }

    // If location is provided, validate it exists in locations collection
    if (location && location.trim() !== '') {
      const locationDoc = await db.collection('locations').doc(location.trim()).get();
      if (!locationDoc.exists) {
        response.status(400).json({ error: `Location '${location}' does not exist in the system` });
        return;
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
      location: location || '',
      createdAt: Timestamp.now(),
    };

    // Initialize allowed_bundles for agents
    if (role === 'agent') {
      userData.allowed_bundles = {};
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

// Configuration for MikroTik API
const mikrotikConfig = {
  host: "41.59.115.231",
  user: "admin", // Replace with your MikroTik username
  password: "ROCKY221122", // Replace with your MikroTik password
  port: 8728, // Default API port
};

const LOCATION_NAME = "MBAGALA"; // Location identifier

exports.updateNetworkSnapshot = onRequest(async (request, response) => {
  // Log the start of the function execution for better debugging
  logger.info("updateNetworkSnapshot function triggered", { query: request.query });

  // --- Start of Copied Logic ---

  const mac = request.query.mac;
  const ip = request.query.ip || ''; // Default to empty string if IP is not provided

  if (!mac) {
    logger.error("Request is missing the required 'mac' parameter.");
    response.status(400).json({ error: 'Missing mac parameter' });
    return; // Exit the function
  }

  try {
    const firestore = getFirestore();
    const docRef = firestore.collection('active_macs').doc(mac);

    await docRef.set({
      mac: mac,
      ip: ip,
      lastSeen: Timestamp.now() // Use the v2 Admin SDK Timestamp
    });

    logger.info(`Successfully updated MAC: ${mac} with IP: ${ip}`);
    response.status(200).json({ status: 'ok', mac, ip });

  } catch (error) {
    logger.error(`Error writing to Firestore for MAC [${mac}]`, error);
    response.status(500).json({ error: 'Internal Server Error', details: error.message });
  }

  // --- End of Copied Logic ---
});