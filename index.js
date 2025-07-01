const express = require("express");
const bodyParser = require("body-parser");
const admin = require("firebase-admin");

const serviceAccount = JSON.parse(process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON);


admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const app = express();
app.use(bodyParser.json());

app.post("/send-notification", async (req, res) => {
  const {
    topic,       // profession topic like 'maids'
    title,       // Notification Title
    body,        // Notification Body
    requestId,
    serviceType,
    issue,
    block,
    flat,
    time,
    actionType   // e.g., 'new_request' or 'reactivated'
  } = req.body;

  const message = {
    notification: {
      title,
      body,
    },
    data: {
      requestId: String(requestId),
      actionType: actionType || 'new_request',
      serviceType: serviceType || '',
      issue: issue || '',
      block: block || '',
      flat: flat || '',
      time: time || '',
    },
    android: {
      notification: {
        channelId: 'request_channel',
        sound: 'ringtone',
        priority: 'high',
      },
      priority: 'high',
    },
    topic: topic,
  };

  try {
    const response = await admin.messaging().send(message);
    console.log("✅ Notification sent:", response);
    res.status(200).send("Notification sent!");
  } catch (error) {
    console.error("❌ Error sending notification:", error);
    res.status(500).send("Error sending notification");
  }
});

app.listen(3000, () => {
  console.log("🚀 Server running at http://localhost:3000");
});
🔐 Load credentials from env var

