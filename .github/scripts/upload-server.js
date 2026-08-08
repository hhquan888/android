const express = require('express');
const multer  = require('multer');
const { execFile } = require('child_process');
const path = require('path');

const app    = express();
const upload = multer({ dest: path.join(__dirname, '../uploads') });

app.get('/', (req, res) => {
  res.send(`
    <html><body style="font-family:sans-serif;padding:20px">
    <h2>&#128228; Upload file vao may ao Android</h2>
    <form method="POST" action="/upload" enctype="multipart/form-data">
      <input type="file" name="files" multiple />
      <button type="submit">Upload</button>
    </form>
    </body></html>
  `);
});

app.post('/upload', upload.array('files'), (req, res) => {
  const files = req.files || [];
  if (files.length === 0)
    return res.json({ success: false, message: 'Khong co file nao' });

  let done = 0;
  const results = [];
  files.forEach((f) => {
    const dest = '/sdcard/Download/' + f.originalname;
    execFile('adb', ['-s', 'localhost:5555', 'push', f.path, dest], (err) => {
      results.push({ file: f.originalname, success: !err, error: err?.message ?? null });
      done++;
      if (done === files.length)
        res.json({ success: results.every(r => r.success), results });
    });
  });
});

app.get('/list', (req, res) => res.json({ status: 'ok' }));

app.listen(3000, () => console.log('Upload server chay tai port 3000'));
