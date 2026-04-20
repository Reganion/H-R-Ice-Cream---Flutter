const admin = require("firebase-admin");

const serviceAccount = require("./serviceAccount.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

async function deleteAllUsers(nextPageToken) {
  const list = await admin.auth().listUsers(1000, nextPageToken);

  const uids = list.users.map(user => user.uid);

  if (uids.length > 0) {
    await admin.auth().deleteUsers(uids);
    console.log("Deleted:", uids.length, "users");
  } else {
    console.log("No users found.");
  }

  if (list.pageToken) {
    return deleteAllUsers(list.pageToken);
  }
}

deleteAllUsers().then(() => {
  console.log("All users deleted successfully!");
});
