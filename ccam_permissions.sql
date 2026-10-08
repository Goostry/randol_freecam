CREATE TABLE IF NOT EXISTS `ccam_permissions` (
  `identifier` VARCHAR(60) NOT NULL,
  `allowed` TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`identifier`)
);
