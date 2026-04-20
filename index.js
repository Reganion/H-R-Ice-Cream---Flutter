const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

async function deleteAllUsers() {
  const list = await admin.auth().listUsers(1000);
  
  const uids = list.users.map(u => u.uid);

  if (uids.length > 0) {
    await admin.auth().deleteUsers(uids);
    console.log("Deleted:", uids.length, "users");
  }

  if (list.pageToken) {
    return deleteAllUsers(list.pageToken);
  }
}

deleteAllUsers().then(() => {
  console.log("All users deleted!");
});
