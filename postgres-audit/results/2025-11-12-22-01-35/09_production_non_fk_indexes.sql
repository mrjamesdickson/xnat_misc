-- Non-FK Indexes (from test results)
-- Generated: 2025-11-12 22-01-35
-- Database: xnat

 -- Table: xdat_change_info | Improvement: 98.01%                                                                                                                             +
 CREATE INDEX IF NOT EXISTS idx_change_info_date ON xdat_change_info(Schema-based index);                                                                                     +
 
 -- Table: xhbm_dicom_spatial_data | Improvement: 95.47%                                                                                                                      +
 CREATE INDEX IF NOT EXISTS idx_dicom_series ON xhbm_dicom_spatial_data(Schema-based index);                                                                                  +
 
 -- Table: xhbm_container_entity_environment_variables | Improvement: 94.50%                                                                                                  +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_container_entity_environment_variables_environment_variables ON xhbm_container_entity_environment_variables(environment_variables);+
 
 -- Table: wrk_workflowdata_meta_data | Improvement: 92.83%                                                                                                                   +
 CREATE INDEX IF NOT EXISTS idx_large_wrk_workflowdata_meta_data_xft_version ON wrk_workflowdata_meta_data(xft_version);                                                      +
 
 -- Table: xdat_user_login | Improvement: 89.93%                                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_query_user_login_session ON xdat_user_login(session_id);                                                                                      +
 
 -- Table: xhbm_container_entity_log_paths | Improvement: 88.70%                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_container_entity_log_paths_container_entity ON xhbm_container_entity_log_paths(container_entity);                                  +
 
 -- Table: xnat_resource | Improvement: 88.17%                                                                                                                                +
 CREATE INDEX IF NOT EXISTS idx_resource_format ON xnat_resource(Schema-based index);                                                                                         +
 
 -- Table: wrk_workflowdata | Improvement: 87.41%                                                                                                                             +
 CREATE INDEX IF NOT EXISTS idx_large_wrk_workflowdata_comments ON wrk_workflowdata(comments);                                                                                +
 
 -- Table: xnat_resource_meta_data | Improvement: 86.97%                                                                                                                      +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_resource_meta_data_xft_version ON xnat_resource_meta_data(xft_version);                                                            +
 
 -- Table: xhbm_container_entity_log_paths | Improvement: 84.32%                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_log_paths_container ON xhbm_container_entity_log_paths(Schema-based index);                                                                   +
 
 -- Table: xhbm_dicom_spatial_data | Improvement: 84.28%                                                                                                                      +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_dicom_spatial_data_created ON xhbm_dicom_spatial_data(created);                                                                    +
 
 -- Table: xnat_resourcecatalog_meta_data | Improvement: 83.18%                                                                                                               +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_resourcecatalog_meta_data_xft_version ON xnat_resourcecatalog_meta_data(xft_version);                                              +
 
 -- Table: xhbm_container_entity_mount | Improvement: 82.06%                                                                                                                  +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_container_entity_mount_container_host_path ON xhbm_container_entity_mount(container_host_path);                                    +
 
 -- Table: xdat_user_login_meta_data | Improvement: 81.38%                                                                                                                    +
 CREATE INDEX IF NOT EXISTS idx_large_xdat_user_login_meta_data_xft_version ON xdat_user_login_meta_data(xft_version);                                                        +
 
 -- Table: xhbm_container_entity | Improvement: 79.49%                                                                                                                        +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_container_entity_created ON xhbm_container_entity(created);                                                                        +
 
 -- Table: xnat_abstractresource_meta_data | Improvement: 76.57%                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_abstractresource_meta_data_xft_version ON xnat_abstractresource_meta_data(xft_version);                                            +
 
 -- Table: xdat_user_login | Improvement: 74.07%                                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_large_xdat_user_login_login_date ON xdat_user_login(login_date);                                                                              +
 
 -- Table: xnat_imagescandata | Improvement: 69.11%                                                                                                                           +
 CREATE INDEX IF NOT EXISTS idx_imagescan_modality ON xnat_imagescandata(Schema-based index);                                                                                 +
 
 -- Table: xs_item_cache | Improvement: 67.65%                                                                                                                                +
 CREATE INDEX IF NOT EXISTS idx_large_xs_item_cache_elementname ON xs_item_cache(elementname);                                                                                +
 
 -- Table: xs_item_cache | Improvement: 67.22%                                                                                                                                +
 CREATE INDEX IF NOT EXISTS idx_query_item_cache_element_ids ON xs_item_cache(elementname, ids);                                                                              +
 
 -- Table: xnat_ctscandata_meta_data | Improvement: 59.15%                                                                                                                    +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_ctscandata_meta_data_xft_version ON xnat_ctscandata_meta_data(xft_version);                                                        +
 
 -- Table: xhbm_container_entity_container_labels | Improvement: 52.62%                                                                                                       +
 CREATE INDEX IF NOT EXISTS idx_large_xhbm_container_entity_container_labels_container_labels ON xhbm_container_entity_container_labels(container_labels);                    +
 
 -- Table: xnat_ctscandata | Improvement: 37.51%                                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_ctscandata_parameters_voxelres_x ON xnat_ctscandata(parameters_voxelres_x);                                                        +
 
 -- Table: xnat_imagescandata | Improvement: 32.77%                                                                                                                           +
 CREATE INDEX IF NOT EXISTS idx_imagescan_uid ON xnat_imagescandata(Schema-based index);                                                                                      +
 
 -- Table: xnat_resourcecatalog | Improvement: 32.50%                                                                                                                         +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_resourcecatalog_resourcecatalog_info ON xnat_resourcecatalog(resourcecatalog_info);                                                +
 
 -- Table: xnat_imagescandata_meta_data | Improvement: 28.89%                                                                                                                 +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_imagescandata_meta_data_xft_version ON xnat_imagescandata_meta_data(xft_version);                                                  +
 
 -- Table: xdat_field_mapping | Improvement: 21.50%                                                                                                                           +
 CREATE INDEX IF NOT EXISTS idx_large_xdat_field_mapping_field ON xdat_field_mapping(field);                                                                                  +
 
 -- Table: xhbm_preference | Improvement: 14.88%                                                                                                                              +
 CREATE INDEX IF NOT EXISTS idx_query_preference_tool_name ON xhbm_preference(tool, name);                                                                                    +
 
 -- Table: xnat_experimentdata | Improvement: 12.59%                                                                                                                          +
 CREATE INDEX IF NOT EXISTS idx_large_xnat_experimentdata_date ON xnat_experimentdata(date);                                                                                  +
 

