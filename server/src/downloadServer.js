/**
 * A deliberately tiny, standalone static file server — serves ONLY
 * public/downloads/ (the field app's .apk + its landing page). No DB
 * connection, no auth middleware, no routes from app.js, nothing that
 * touches the real API. This is the one process meant to be tunneled to
 * the public internet (see pm2's tp-rms-downloads); the real API
 * (src/server.js) never is.
 */
const express = require('express');
const path = require('path');

const PORT = parseInt(process.env.DOWNLOAD_SERVER_PORT || '4100', 10);

const app = express();
// Same /downloads prefix as app.js's LAN mount, so the one landing page
// (public/downloads/index.html) works identically from both — its button
// links to /downloads/tp-rms.apk either way, never a bare /tp-rms.apk.
app.get('/', (req, res) => res.redirect('/downloads/'));
app.use('/downloads', express.static(path.join(__dirname, '..', 'public', 'downloads')));

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`[download-server] serving public/downloads/ on port ${PORT}`);
});
