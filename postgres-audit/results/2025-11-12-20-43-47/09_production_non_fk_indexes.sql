-- Non-FK Indexes (from test results)
-- Generated: 2025-11-12 20-43-47
-- Database: xnat

 -- Table: xdat_change_info | Improvement: 98.11%                                                            +
 CREATE INDEX IF NOT EXISTS idx_change_info_date ON xdat_change_info(Schema-based index);                    +
 
 -- Table: xnat_resource | Improvement: 94.82%                                                               +
 CREATE INDEX IF NOT EXISTS idx_resource_format ON xnat_resource(Schema-based index);                        +
 
 -- Table: xhbm_dicom_spatial_data | Improvement: 92.11%                                                     +
 CREATE INDEX IF NOT EXISTS idx_dicom_series ON xhbm_dicom_spatial_data(Schema-based index);                 +
 
 -- Table: wrk_workflowdata | Improvement: 87.28%                                                            +
 CREATE INDEX IF NOT EXISTS idx_large_wrk_workflowdata_comments ON wrk_workflowdata(comments);               +
 
 -- Table: xdat_user_login | Improvement: 84.95%                                                             +
 CREATE INDEX IF NOT EXISTS idx_query_user_login_session ON xdat_user_login(session_id);                     +
 
 -- Table: xdat_user_login | Improvement: 84.03%                                                             +
 CREATE INDEX IF NOT EXISTS idx_large_xdat_user_login_login_date ON xdat_user_login(login_date);             +
 
 -- Table: xnat_imagescandata | Improvement: 69.07%                                                          +
 CREATE INDEX IF NOT EXISTS idx_imagescan_modality ON xnat_imagescandata(Schema-based index);                +
 
 -- Table: xs_item_cache | Improvement: 68.30%                                                               +
 CREATE INDEX IF NOT EXISTS idx_query_item_cache_element_ids ON xs_item_cache(elementname, ids);             +
 
 -- Table: xhbm_container_entity_log_paths | Improvement: 66.09%                                             +
 CREATE INDEX IF NOT EXISTS idx_log_paths_container ON xhbm_container_entity_log_paths(Schema-based index);  +
 
 -- Table: xnat_imagescandata | Improvement: 44.45%                                                          +
 CREATE INDEX IF NOT EXISTS idx_imagescan_uid ON xnat_imagescandata(Schema-based index);                     +
 
 -- Table: xnat_imagesessiondata_history | Improvement: 24.47%                                               +
 CREATE INDEX IF NOT EXISTS idx_query_imagesession_history ON xnat_imagesessiondata_history(id, change_date);+
 
 -- Table: xdat_user_login | Improvement: 19.31%                                                             +
 CREATE INDEX IF NOT EXISTS idx_user_login_active ON xdat_user_login(Schema-based index);                    +
 

