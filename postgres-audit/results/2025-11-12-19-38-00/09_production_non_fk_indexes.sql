-- Non-FK Indexes (from test results)
 CREATE INDEX IF NOT EXISTS idx_change_info_date ON xdat_change_info(...);  -- 99.00% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_dicom_series ON xhbm_dicom_spatial_data(...);  -- 94.68% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_resource_format ON xnat_resource(...);  -- 77.70% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_imagescan_modality ON xnat_imagescandata(...);  -- 68.32% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_log_paths_container ON xhbm_container_entity_log_paths(...);  -- 64.53% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_imagescan_uid ON xnat_imagescandata(...);  -- 54.96% improvement (Schema-based index)
 CREATE INDEX IF NOT EXISTS idx_user_login_active ON xdat_user_login(...);  -- 15.55% improvement (Schema-based index)

