// File: functions/index.js
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Initialize Firebase Admin SDK if not already done
admin.initializeApp();
const db = admin.firestore();

// --- 1. LISTEN FOR NEW PING CREATION ---
exports.sendPingNotification = functions.firestore
    .document('groups/{groupId}/pings/{pingId}')
    .onCreate(async (snap, context) => {

        const pingData = snap.data();
        const groupId = context.params.groupId;

        const pingName = pingData.name || "A new topic";
        const creatorName = pingData.creatorName || "Someone";
        const createdBy = pingData.createdBy;

        // --- 2. GET GROUP MEMBERS (TARGETS) ---
        const groupRef = db.collection('groups').doc(groupId);
        const groupSnap = await groupRef.get();

        if (!groupSnap.exists) {
            console.log("Group does not exist. Aborting notification.");
            return null;
        }

        const groupMembers = groupSnap.data().members || [];
        const targetUids = groupMembers.filter(uid => uid !== createdBy); // Exclude the creator

        if (targetUids.length === 0) {
            console.log("No members to notify.");
            return null;
        }

        // --- 3. FETCH FCM TOKENS FOR TARGET MEMBERS ---
        const tokensSnapshot = await db.collection('users')
            .where(admin.firestore.FieldPath.documentId(), 'in', targetUids)
            .select('fcmToken')
            .get();

        const registrationTokens = [];
        tokensSnapshot.forEach(doc => {
            const token = doc.data().fcmToken;
            if (token) {
                registrationTokens.push(token);
            }
        });

        if (registrationTokens.length === 0) {
            console.log("No valid FCM tokens found for members.");
            return null;
        }

        // --- 4. CONSTRUCT NOTIFICATION PAYLOAD ---
        const payload = {
            notification: {
                title: 'New Ping in the Group!',
                body: `${creatorName} started a ping: "${pingName}"`,
                sound: 'default',
            },
            data: {
                click_action: 'FLUTTER_NOTIFICATION_CLICK',
                pingId: snap.id,
                groupId: groupId,
            },
        };

        // --- 5. SEND THE NOTIFICATION ---
        const response = await admin.messaging().sendEachForMulticast({ tokens: registrationTokens, ...payload });

        console.log('Notifications sent:', response.successCount);
        return null;
    });