// pm2 process definitions for the API server, the background worker, and
// the crash-alert watcher. Three separate processes on purpose — see
// src/worker.js: a slow/failing background job should never be able to
// starve HTTP request handling, and each side can be restarted or scaled
// independently. The watcher (src/scripts/crashWatcher.js) emails
// ALERT_EMAIL_TO (see .env) the moment pm2 reports either of the other
// two crashing/restarting — see that file for what it actually does.
//
// Usage:
//   pm2 start ecosystem.config.js --env production
//   pm2 status / pm2 logs / pm2 restart tp-rms-api / pm2 stop all
//   pm2 save && pm2 startup   (persist across machine reboots)

module.exports = {
  apps: [
    {
      name: 'tp-rms-api',
      script: 'src/server.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      max_memory_restart: '300M',
      watch: false,
      env: { NODE_ENV: 'development' },
      env_production: { NODE_ENV: 'production' },
      out_file: 'logs/pm2-api-out.log',
      error_file: 'logs/pm2-api-error.log',
      merge_logs: true,
      time: true,
    },
    {
      name: 'tp-rms-worker',
      script: 'src/worker.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      max_memory_restart: '300M',
      watch: false,
      env: { NODE_ENV: 'development' },
      env_production: { NODE_ENV: 'production' },
      out_file: 'logs/pm2-worker-out.log',
      error_file: 'logs/pm2-worker-error.log',
      merge_logs: true,
      time: true,
    },
    {
      // Isolated static file server for the public app-download link — see
      // src/downloadServer.js's header comment for why this is a
      // completely separate process from tp-rms-api, never the thing
      // tunneled to the internet being the real API.
      name: 'tp-rms-downloads',
      script: 'src/downloadServer.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false,
      env: { NODE_ENV: 'development', DOWNLOAD_SERVER_PORT: '4100' },
      env_production: { NODE_ENV: 'production', DOWNLOAD_SERVER_PORT: '4100' },
      out_file: 'logs/pm2-downloads-out.log',
      error_file: 'logs/pm2-downloads-error.log',
      merge_logs: true,
      time: true,
    },
    {
      name: 'tp-rms-crash-watcher',
      script: 'src/scripts/crashWatcher.js',
      cwd: __dirname,
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '10s',
      watch: false,
      env: { NODE_ENV: 'development' },
      env_production: { NODE_ENV: 'production' },
      out_file: 'logs/pm2-crash-watcher-out.log',
      error_file: 'logs/pm2-crash-watcher-error.log',
      merge_logs: true,
      time: true,
    },
  ],
};
