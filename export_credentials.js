const sqlite3 = require('sqlite3').verbose();
const fs = require('fs');

const db = new sqlite3.Database('./sqlite_backup.sqlite');
db.all('SELECT * FROM credentials_entity', (err, rows) => {
  if (err) throw err;
  fs.writeFileSync('./local-files/credentials.json', JSON.stringify(rows, null, 2));
  db.close();
});
