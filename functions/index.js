const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendBroadcast = functions.firestore
  .document('adminNotifications/{id}')
  .onCreate(async (snap) => {
    const d = snap.data();
    if (!d.title || !d.body) return null;
    return admin.messaging().send({
      notification: { title: d.title, body: d.body },
      topic: d.target || 'all_users'
    });
  });