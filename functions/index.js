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

exports.fetchHotspotHostAndUpdateStatus = onSchedule("every 5 minutes", async (event) => {
  const conn = new RouterOSAPI(mikrotikConfig);
  const db = getFirestore();

  try {
    // --- 1. Fetch online devices from the MikroTik router ---
    await conn.connect();
    logger.info("Successfully connected to MikroTik API at", mikrotikConfig.host);

    const hosts = await conn.write("/ip/hotspot/host/print");

    // Create a Map of online devices for fast lookups (MAC -> IP Address)
    const onlineDevicesMap = new Map();
    for (const host of hosts) {
      // Ensure we only process valid hosts with a MAC and IP address
      if (host["mac-address"] && host.address) {
        onlineDevicesMap.set(host["mac-address"], host.address);
      }
    }
    logger.info(`Found ${onlineDevicesMap.size} online devices from MikroTik at ${LOCATION_NAME}.`);

    // --- 2. Get all managed devices from your Firestore 'devices' collection ---
    const devicesRef = db.collection(FIRESTORE_COLLECTION);
    const snapshot = await devicesRef.get();

    if (snapshot.empty) {
      logger.warn("No devices found in Firestore 'devices' collection. Nothing to update.");
      return;
    }

    // --- 3. Compare lists and update Firestore using an efficient Batch Write ---
    const batch = db.batch();
    let updatesCounter = 0;

    snapshot.forEach(doc => {
      const deviceData = doc.data();
      // Ensure the document has a mac_address field to check against
      const deviceMac = deviceData.mac_address;

      if (!deviceMac) {
        return; // Skip documents in the collection that don't have a MAC address
      }

      const currentStatus = deviceData.status;
      const currentIp = deviceData.ip_address;

      // Check if this device is in our online list from the MikroTik
      if (onlineDevicesMap.has(deviceMac)) {
        // --- Device is ONLINE ---
        const newIp = onlineDevicesMap.get(deviceMac);

        // Only update if the status is not already 'online' OR the IP has changed
        if (currentStatus !== "online" || currentIp !== newIp) {
          logger.log(`Status change: ${deviceData.namee || deviceMac} is now ONLINE with IP ${newIp}`);
          batch.update(doc.ref, {
            status: "online",
            ip_address: newIp,
            lastSeen: Timestamp.now()
           // location: LOCATION_NAME // Optionally update the location
          });
          updatesCounter++;
        }
      } else {
        // --- Device is OFFLINE ---
        // Only update if the status is not already 'offline'
        if (currentStatus !== "offline") {
          logger.log(`Status change: ${deviceData.namee || deviceMac} is now OFFLINE.`);
          // When offline, we clear the IP address
          batch.update(doc.ref, { status: "offline", ip_address: null });
          updatesCounter++;
        }
      }
    });

    // --- 4. Commit all the updates to Firestore at once ---
    if (updatesCounter > 0) {
      await batch.commit();
      logger.info(`✅ Successfully updated ${updatesCounter} device statuses in Firestore.`);
    } else {
      logger.info("✅ All device statuses are already up-to-date.");
    }

  } catch (error) {
    logger.error("🔥 An unexpected error occurred during the sync process:", {
      message: error.message,
      stack: error.stack,
    });
    throw new Error(`Failed to sync device statuses: ${error.message}`);
  } finally {
    // Ensure the connection to the router is always closed
    if (conn.connected) {
      try {
        conn.close();
        logger.info("Disconnected from MikroTik API.");
      } catch (closeError) {
        logger.warn("Warning: Failed to close MikroTik API connection:", closeError.message);
      }
    }
  }
});
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


// Import necessary modules


/**
 * This scheduled function runs every 5 minutes. It fetches the list of online
 * devices from the Flask API and updates the status and IP address of each
 * device in the Firestore 'devices' collection.
 */
exports.syncDeviceStatus = onSchedule("every 5 minutes", async (event) => {


  try {
    // --- 1. Fetch online devices from your Flask API ---
    const response = await axios.get(FLASK_API_URL);

    // Create a Map of online devices for fast lookups (MAC -> IP)
    const onlineDevicesMap = new Map();
    for (const device of response.data) {
      if (device.mac_address) {
        onlineDevicesMap.set(device.mac_address, device.ip_address);
      }
    }
    logger.info(`Found ${onlineDevicesMap.size} online devices from Flask API.`);

    // --- 2. Get all managed devices from your Firestore collection ---
    const firestore = getFirestore();
    const devicesRef = firestore.collection(FIRESTORE_COLLECTION);
    const snapshot = await devicesRef.get();

    if (snapshot.empty) {
      logger.warn("No devices found in Firestore. Nothing to update.");
      return;
    }

    // --- 3. Compare lists and update Firestore using an efficient Batch Write ---
    const batch = firestore.batch();
    let updatesCounter = 0;

    snapshot.forEach(doc => {
      const deviceData = doc.data();
      const deviceMac = deviceData.mac_address; // Get MAC from the document field
      const currentStatus = deviceData.status;
      const currentIp = deviceData.ip_address;

      // Check if this device is in our online list from the API
      if (onlineDevicesMap.has(deviceMac)) {
        // --- Device is ONLINE ---
        const newIp = onlineDevicesMap.get(deviceMac);

        // Only update if the status is not already 'online' OR the IP has changed
        if (currentStatus !== "online" || currentIp !== newIp) {
          logger.log(`Status change: ${deviceData.namee || deviceMac} is now ONLINE with IP ${newIp}`);
          batch.update(doc.ref, {
            status: "online",
            ip_address: newIp, // <-- ADD/UPDATE THE IP ADDRESS
            lastSeen: Timestamp.now()
          });
          updatesCounter++;
        }
      } else {
        // --- Device is OFFLINE ---
        // Only update if the status is not already 'offline'
        if (currentStatus !== "offline") {
          logger.log(`Status change: ${deviceData.namee || deviceMac} is now OFFLINE.`);
          // When offline, we can clear the IP address if desired
          batch.update(doc.ref, { status: "offline", ip_address: null });
          updatesCounter++;
        }
      }
    });

    // Commit all the updates to Firestore at once if there are any
    if (updatesCounter > 0) {
      await batch.commit();
      logger.info(`${updatesCounter} device statuses were updated in Firestore.`);
    } else {
      logger.info("All device statuses are already up-to-date.");
    }

  } catch (error) {
    if (error.isAxiosError) {
      logger.error("Error fetching data from Flask API:", error.message);
    } else {
      logger.error("An unexpected error occurred during sync:", error);
    }
  }
});