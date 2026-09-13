/**
 * Cloud Functions are retired.
 *
 * Checkout, Nokia beacons, home-internet billing, user admin, and scheduled
 * jobs now run on the LightNet Flask server:
 *   POST /make-payment
 *   POST /make-paymentagent
 *   POST /api/nokia/beacon-status
 *   GET  /api/jobs/nokia-stale
 *   GET  /api/jobs/sa-monthly-balance
 *   /api/hi/*  /api/auth/*  /api/app/*
 *
 * Do not add new HTTPS or scheduled functions here.
 */
const { logger } = require("firebase-functions");
logger.info("lightnet Cloud Functions are retired; traffic belongs on the Flask server");
