-- Adds the ADMIN role — a deliberately narrow account that can view BUSY
-- sync health, manually trigger a sync, reset a salesperson's password,
-- and is now the ONLY role that controls maintenance mode (see
-- maintenanceService.js / middleware/auth.js — Manager no longer has this).
ALTER TABLE users MODIFY COLUMN role ENUM('SALESPERSON','RECOVERY_EXECUTIVE','MANAGEMENT','ADMIN') NOT NULL;
