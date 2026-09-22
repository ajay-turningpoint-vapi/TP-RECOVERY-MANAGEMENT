-- Small generic key/value settings table. First (only, for now) use is the
-- manager-only maintenance-mode kill switch — see maintenanceService.js.
CREATE TABLE IF NOT EXISTS app_settings (
  `key` VARCHAR(64) NOT NULL,
  `value` VARCHAR(255) NOT NULL,
  updated_by VARCHAR(36) NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO app_settings (`key`, `value`) VALUES ('maintenance_mode', 'false');
