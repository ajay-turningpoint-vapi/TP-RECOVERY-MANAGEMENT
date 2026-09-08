// pm2 process definitions for the API server and the background worker.
// Two separate processes on purpose — see src/worker.js: a slow/failing
// background job should never be able to starve HTTP request handling,
// and each side can be restarted or scaled independently.
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
  ],
};
