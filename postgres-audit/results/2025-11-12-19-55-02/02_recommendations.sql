Timing is on.

=========================================
PostgreSQL Optimization Recommendations
=========================================


--- RECOMMENDATION 1: Create Indexes on Foreign Keys ---

                                                                                             recommended_sql                                                                                             
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 CREATE INDEX idx_icr_roicollectiondata_subjectid ON icr_roicollectiondata(subjectid);
 CREATE INDEX idx_img_assessor_in_resource_xnat_abstractresource_xnat_abstractresource_id ON img_assessor_in_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_img_assessor_in_resource_xnat_imageassessordata_id ON img_assessor_in_resource(xnat_imageassessordata_id);
 CREATE INDEX idx_img_assessor_out_resource_xnat_imageassessordata_id ON img_assessor_out_resource(xnat_imageassessordata_id);
 CREATE INDEX idx_img_assessor_out_resource_xnat_abstractresource_xnat_abstractresource_id ON img_assessor_out_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_recon_in_resource_xnat_abstractresource_xnat_abstractresource_id ON recon_in_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_recon_in_resource_xnat_reconstructedimagedata_xnat_reconstructedimagedata_id ON recon_in_resource(xnat_reconstructedimagedata_xnat_reconstructedimagedata_id);
 CREATE INDEX idx_recon_out_resource_xnat_reconstructedimagedata_xnat_reconstructedimagedata_id ON recon_out_resource(xnat_reconstructedimagedata_xnat_reconstructedimagedata_id);
 CREATE INDEX idx_recon_out_resource_xnat_abstractresource_xnat_abstractresource_id ON recon_out_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_xdat_a_xdat_action_type_allowe_xdat_role_type_xdat_role_type_role_name ON xdat_a_xdat_action_type_allowe_xdat_role_type(xdat_role_type_role_name);
 CREATE INDEX idx_xdat_a_xdat_action_type_allowe_xdat_role_type_xdat_action_type_action_name ON xdat_a_xdat_action_type_allowe_xdat_role_type(xdat_action_type_action_name);
 CREATE INDEX idx_xdat_r_xdat_role_type_assign_xdat_user_xdat_user_xdat_user_id ON xdat_r_xdat_role_type_assign_xdat_user(xdat_user_xdat_user_id);
 CREATE INDEX idx_xdat_r_xdat_role_type_assign_xdat_user_xdat_role_type_role_name ON xdat_r_xdat_role_type_assign_xdat_user(xdat_role_type_role_name);
 CREATE INDEX idx_xhbm_alias_token_validipaddresses_alias_token ON xhbm_alias_token_validipaddresses(alias_token);
 CREATE INDEX idx_xhbm_archive_processor_instance_project_ids_list_archive_processor_instance ON xhbm_archive_processor_instance_project_ids_list(archive_processor_instance);
 CREATE INDEX idx_xhbm_archive_processor_instance_scp_blacklist_archive_processor_instance ON xhbm_archive_processor_instance_scp_blacklist(archive_processor_instance);
 CREATE INDEX idx_xhbm_archive_processor_instance_scp_whitelist_archive_processor_instance ON xhbm_archive_processor_instance_scp_whitelist(archive_processor_instance);
 CREATE INDEX idx_xhbm_automation_event_ids_ids_parent_automation_event_ids ON xhbm_automation_event_ids_ids(parent_automation_event_ids);
 CREATE INDEX idx_xhbm_automation_filters_values_automation_filters ON xhbm_automation_filters_values(automation_filters);
 CREATE INDEX idx_xhbm_command_input_entity_command_entity ON xhbm_command_input_entity(command_entity);
 CREATE INDEX idx_xhbm_command_input_entity_select_values_command_input_entity ON xhbm_command_input_entity_select_values(command_input_entity);
 CREATE INDEX idx_xhbm_command_mount_entity_command_entity ON xhbm_command_mount_entity(command_entity);
 CREATE INDEX idx_xhbm_command_output_entity_command_entity ON xhbm_command_output_entity(command_entity);
 CREATE INDEX idx_xhbm_command_wrapper_derived_input_entity_command_wrapper_entity ON xhbm_command_wrapper_derived_input_entity(command_wrapper_entity);
 CREATE INDEX idx_xhbm_command_wrapper_entity_command_entity ON xhbm_command_wrapper_entity(command_entity);
 CREATE INDEX idx_xhbm_command_wrapper_entity_contexts_command_wrapper_entity ON xhbm_command_wrapper_entity_contexts(command_wrapper_entity);
 CREATE INDEX idx_xhbm_command_wrapper_external_input_entity_command_wrapper_entity ON xhbm_command_wrapper_external_input_entity(command_wrapper_entity);
 CREATE INDEX idx_xhbm_command_wrapper_output_entity_command_wrapper_entity ON xhbm_command_wrapper_output_entity(command_wrapper_entity);
 CREATE INDEX idx_xhbm_command_wrapper_output_entity_tags_command_wrapper_output_entity ON xhbm_command_wrapper_output_entity_tags(command_wrapper_output_entity);
 CREATE INDEX idx_xhbm_compute_environment_config_entity_config_types_compute_environment_config_entity ON xhbm_compute_environment_config_entity_config_types(compute_environment_config_entity);
 CREATE INDEX idx_xhbm_compute_environment_entity_compute_environment_config ON xhbm_compute_environment_entity(compute_environment_config);
 CREATE INDEX idx_xhbm_compute_environment_entity_environment_variables_compute_environment_entity ON xhbm_compute_environment_entity_environment_variables(compute_environment_entity);
 CREATE INDEX idx_xhbm_compute_environment_entity_mounts_compute_environment_entity ON xhbm_compute_environment_entity_mounts(compute_environment_entity);
 CREATE INDEX idx_xhbm_compute_environment_scope_entity_compute_environment_config ON xhbm_compute_environment_scope_entity(compute_environment_config);
 CREATE INDEX idx_xhbm_compute_environment_scope_entity_ids_compute_environment_scope_entity ON xhbm_compute_environment_scope_entity_ids(compute_environment_scope_entity);
 CREATE INDEX idx_xhbm_configuration_config_data ON xhbm_configuration(config_data);
 CREATE INDEX idx_xhbm_constraint_entity_constraint_values_constraint_entity_constraint_config ON xhbm_constraint_entity_constraint_values(constraint_entity_constraint_config);
 CREATE INDEX idx_xhbm_constraint_scope_entity_constraint_config ON xhbm_constraint_scope_entity(constraint_config);
 CREATE INDEX idx_xhbm_constraint_scope_entity_ids_constraint_scope_entity ON xhbm_constraint_scope_entity_ids(constraint_scope_entity);
 CREATE INDEX idx_xhbm_container_entity_parent_container_entity ON xhbm_container_entity(parent_container_entity);
 CREATE INDEX idx_xhbm_container_entity_history_container_entity ON xhbm_container_entity_history(container_entity);
 CREATE INDEX idx_xhbm_container_entity_mount_container_entity ON xhbm_container_entity_mount(container_entity);
 CREATE INDEX idx_xhbm_container_entity_output_container_entity ON xhbm_container_entity_output(container_entity);
 CREATE INDEX idx_xhbm_container_entity_output_tags_container_entity_output ON xhbm_container_entity_output_tags(container_entity_output);
 CREATE INDEX idx_xhbm_container_entity_swarm_constraints_container_entity ON xhbm_container_entity_swarm_constraints(container_entity);
 CREATE INDEX idx_xhbm_container_mount_files_entity_container_entity_mount ON xhbm_container_mount_files_entity(container_entity_mount);
 CREATE INDEX idx_xhbm_dashboard_config_entity_hardware_config_id ON xhbm_dashboard_config_entity(hardware_config_id);
 CREATE INDEX idx_xhbm_dashboard_config_entity_compute_environment_config_id ON xhbm_dashboard_config_entity(compute_environment_config_id);
 CREATE INDEX idx_xhbm_dashboard_entity_dashboard_config ON xhbm_dashboard_entity(dashboard_config);
 CREATE INDEX idx_xhbm_dashboard_entity_dashboard_framework ON xhbm_dashboard_entity(dashboard_framework);
 CREATE INDEX idx_xhbm_dashboard_scope_entity_dashboard_config ON xhbm_dashboard_scope_entity(dashboard_config);
 CREATE INDEX idx_xhbm_dashboard_scope_entity_ids_dashboard_scope_entity ON xhbm_dashboard_scope_entity_ids(dashboard_scope_entity);
 CREATE INDEX idx_xhbm_definition_category ON xhbm_definition(category);
 CREATE INDEX idx_xhbm_dicomscpinstance_whitelist_scp_id ON xhbm_dicomscpinstance_whitelist(scp_id);
 CREATE INDEX idx_xhbm_event_filters_event_filters ON xhbm_event_filters(event_filters);
 CREATE INDEX idx_xhbm_event_filters_filter_vals_event_filters ON xhbm_event_filters_filter_vals(event_filters);
 CREATE INDEX idx_xhbm_event_service_filter_entity_project_ids_event_service_filter_entity ON xhbm_event_service_filter_entity_project_ids(event_service_filter_entity);
 CREATE INDEX idx_xhbm_event_specific_fields_event_specific_fields ON xhbm_event_specific_fields(event_specific_fields);
 CREATE INDEX idx_xhbm_executed_pacs_request_series_ids_executed_pacs_request ON xhbm_executed_pacs_request_series_ids(executed_pacs_request);
 CREATE INDEX idx_xhbm_hardware_constraint_entity_hardware_entity_id ON xhbm_hardware_constraint_entity(hardware_entity_id);
 CREATE INDEX idx_xhbm_hardware_constraint_entity_constraint_values_hardware_constraint_entity ON xhbm_hardware_constraint_entity_constraint_values(hardware_constraint_entity);
 CREATE INDEX idx_xhbm_hardware_entity_hardware_config ON xhbm_hardware_entity(hardware_config);
 CREATE INDEX idx_xhbm_hardware_entity_environment_variables_hardware_entity ON xhbm_hardware_entity_environment_variables(hardware_entity);
 CREATE INDEX idx_xhbm_hardware_entity_generic_resources_hardware_entity ON xhbm_hardware_entity_generic_resources(hardware_entity);
 CREATE INDEX idx_xhbm_hardware_scope_entity_hardware_config ON xhbm_hardware_scope_entity(hardware_config);
 CREATE INDEX idx_xhbm_hardware_scope_entity_ids_hardware_scope_entity ON xhbm_hardware_scope_entity_ids(hardware_scope_entity);
 CREATE INDEX idx_xhbm_icr_dicomweb_study_data_patient_fk ON xhbm_icr_dicomweb_study_data(patient_fk);
 CREATE INDEX idx_xhbm_notification_definition ON xhbm_notification(definition);
 CREATE INDEX idx_xhbm_orchestrated_wrapper_entity_command_wrapper_entity ON xhbm_orchestrated_wrapper_entity(command_wrapper_entity);
 CREATE INDEX idx_xhbm_orchestrated_wrapper_entity_orchestration_entity ON xhbm_orchestrated_wrapper_entity(orchestration_entity);
 CREATE INDEX idx_xhbm_orchestration_project_entity_orchestration_entity ON xhbm_orchestration_project_entity(orchestration_entity);
 CREATE INDEX idx_xhbm_project_irb_info_project_irb_files_project_irb_info ON xhbm_project_irb_info_project_irb_files(project_irb_info);
 CREATE INDEX idx_xhbm_protocol_validation_result_protocol_id ON xhbm_protocol_validation_result(protocol_id);
 CREATE INDEX idx_xhbm_protocol_validation_rule_protocol_id ON xhbm_protocol_validation_rule(protocol_id);
 CREATE INDEX idx_xhbm_protocol_validation_violation_rule_id ON xhbm_protocol_validation_violation(rule_id);
 CREATE INDEX idx_xhbm_protocol_validation_violation_result_id ON xhbm_protocol_validation_violation(result_id);
 CREATE INDEX idx_xhbm_query_response_query_id ON xhbm_query_response(query_id);
 CREATE INDEX idx_xhbm_queued_pacs_request_series_ids_queued_pacs_request ON xhbm_queued_pacs_request_series_ids(queued_pacs_request);
 CREATE INDEX idx_xhbm_script_trigger_template_associated_entities_script_trigger_template ON xhbm_script_trigger_template_associated_entities(script_trigger_template);
 CREATE INDEX idx_xhbm_subscription_definition ON xhbm_subscription(definition);
 CREATE INDEX idx_xhbm_subscription_subscriber ON xhbm_subscription(subscriber);
 CREATE INDEX idx_xhbm_subscription_channels_subscription ON xhbm_subscription_channels(subscription);
 CREATE INDEX idx_xhbm_subscription_channels_channels ON xhbm_subscription_channels(channels);
 CREATE INDEX idx_xhbm_subscription_delivery_entity_triggering_event_entity ON xhbm_subscription_delivery_entity(triggering_event_entity);
 CREATE INDEX idx_xhbm_subscription_delivery_entity_subscription ON xhbm_subscription_delivery_entity(subscription);
 CREATE INDEX idx_xhbm_subscription_delivery_payload_payload_id ON xhbm_subscription_delivery_payload(payload_id);
 CREATE INDEX idx_xhbm_subscription_entity_event_service_filter_entity ON xhbm_subscription_entity(event_service_filter_entity);
 CREATE INDEX idx_xhbm_timed_event_status_entity_subscription_delivery_entity ON xhbm_timed_event_status_entity(subscription_delivery_entity);
 CREATE INDEX idx_xhbm_training_question_quiz_id ON xhbm_training_question(quiz_id);
 CREATE INDEX idx_xhbm_training_task_training_set_id ON xhbm_training_task(training_set_id);
 CREATE INDEX idx_xhbm_xnat_protocol_validation_result_protocol_id ON xhbm_xnat_protocol_validation_result(protocol_id);
 CREATE INDEX idx_xhbm_xnat_protocol_validation_rule_protocol_id ON xhbm_xnat_protocol_validation_rule(protocol_id);
 CREATE INDEX idx_xhbm_xnat_protocol_validation_violation_result_id ON xhbm_xnat_protocol_validation_violation(result_id);
 CREATE INDEX idx_xhbm_xnat_protocol_validation_violation_rule_id ON xhbm_xnat_protocol_validation_violation(rule_id);
 CREATE INDEX idx_xhbm_xsync_project_history_assessor_histories_xsync_project_history ON xhbm_xsync_project_history_assessor_histories(xsync_project_history);
 CREATE INDEX idx_xhbm_xsync_project_history_experiment_histories_xsync_project_history ON xhbm_xsync_project_history_experiment_histories(xsync_project_history);
 CREATE INDEX idx_xhbm_xsync_project_history_resource_histories_xsync_project_history ON xhbm_xsync_project_history_resource_histories(xsync_project_history);
 CREATE INDEX idx_xhbm_xsync_project_history_subject_histories_xsync_project_history ON xhbm_xsync_project_history_subject_histories(xsync_project_history);
 CREATE INDEX idx_xnat_datatypeprotocol_fieldgroups_xnat_datatypeprotocol_xnat_abstractprotocol_id ON xnat_datatypeprotocol_fieldgroups(xnat_datatypeprotocol_xnat_abstractprotocol_id);
 CREATE INDEX idx_xnat_datatypeprotocol_fieldgroups_xnat_fielddefinitiongroup_xnat_fielddefinitiongroup_id ON xnat_datatypeprotocol_fieldgroups(xnat_fielddefinitiongroup_xnat_fielddefinitiongroup_id);
 CREATE INDEX idx_xnat_experimentdata_visit ON xnat_experimentdata(visit);
 CREATE INDEX idx_xnat_experimentdata_resource_xnat_experimentdata_id ON xnat_experimentdata_resource(xnat_experimentdata_id);
 CREATE INDEX idx_xnat_experimentdata_resource_xnat_abstractresource_xnat_abstractresource_id ON xnat_experimentdata_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_xnat_experimentdata_share_visit ON xnat_experimentdata_share(visit);
 CREATE INDEX idx_xnat_imageassessordata_imagesession_id ON xnat_imageassessordata(imagesession_id);
 CREATE INDEX idx_xnat_projectasset_experimentdata_xnat_abstractprojectasset_id ON xnat_projectasset_experimentdata(xnat_abstractprojectasset_id);
 CREATE INDEX idx_xnat_projectasset_experimentdata_xnat_experimentdata_id ON xnat_projectasset_experimentdata(xnat_experimentdata_id);
 CREATE INDEX idx_xnat_projectasset_subjectdata_xnat_abstractprojectasset_id ON xnat_projectasset_subjectdata(xnat_abstractprojectasset_id);
 CREATE INDEX idx_xnat_projectasset_subjectdata_xnat_subjectdata_id ON xnat_projectasset_subjectdata(xnat_subjectdata_id);
 CREATE INDEX idx_xnat_projectdata_investigator_xnat_investigatordata_xnat_investigatordata_id ON xnat_projectdata_investigator(xnat_investigatordata_xnat_investigatordata_id);
 CREATE INDEX idx_xnat_projectdata_investigator_xnat_projectdata_id ON xnat_projectdata_investigator(xnat_projectdata_id);
 CREATE INDEX idx_xnat_projectdata_resource_xnat_abstractresource_xnat_abstractresource_id ON xnat_projectdata_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_xnat_projectdata_resource_xnat_projectdata_id ON xnat_projectdata_resource(xnat_projectdata_id);
 CREATE INDEX idx_xnat_pvisitdata_subject_id ON xnat_pvisitdata(subject_id);
 CREATE INDEX idx_xnat_reconstructedimagedata_image_session_id ON xnat_reconstructedimagedata(image_session_id);
 CREATE INDEX idx_xnat_subjectassessordata_subject_id ON xnat_subjectassessordata(subject_id);
 CREATE INDEX idx_xnat_subjectdata_resource_xnat_abstractresource_xnat_abstractresource_id ON xnat_subjectdata_resource(xnat_abstractresource_xnat_abstractresource_id);
 CREATE INDEX idx_xnat_subjectdata_resource_xnat_subjectdata_id ON xnat_subjectdata_resource(xnat_subjectdata_id);
 CREATE INDEX idx_xsync_xsyncassessordata_authorized_by ON xsync_xsyncassessordata(authorized_by);
(119 rows)

Time: 17.468 ms

--- RECOMMENDATION 2: Drop Unused Indexes (REVIEW FIRST!) ---

WARNING: Only drop after confirming these are truly unused

Time: 1.123 ms
psql:/tmp/02_generate_recommendations.sql:55: ERROR:  column "indexname" does not exist
LINE 2: ...  'DROP INDEX IF EXISTS ' || schemaname || '.' || indexname ...
                                                             ^
HINT:  Perhaps you meant to reference the column "pg_stat_user_indexes.indexrelname".

--- RECOMMENDATION 3: VACUUM Bloated Tables ---

psql:/tmp/02_generate_recommendations.sql:77: ERROR:  column "tablename" does not exist
LINE 2: ...'VACUUM (FULL, ANALYZE) ' || schemaname || '.' || tablename ...
                                                             ^
psql:/tmp/02_generate_recommendations.sql:95: ERROR:  column "tablename" does not exist
LINE 2:     'ANALYZE ' || schemaname || '.' || tablename || ';  -- '...
                                               ^
psql:/tmp/02_generate_recommendations.sql:119: ERROR:  column "tablename" does not exist
LINE 2:     '-- ' || schemaname || '.' || tablename ||
                                          ^
psql:/tmp/02_generate_recommendations.sql:137: ERROR:  column a.tablename does not exist
LINE 6:     AND a.tablename = b.tablename
                ^
Time: 0.913 ms

--- RECOMMENDATION 4: Update Statistics on Large Tables ---

Time: 0.155 ms

--- RECOMMENDATION 5: Consider Composite Indexes ---

Tables with high sequential scans may benefit from indexes
Analyze queries on these tables to determine which columns to index

Time: 0.258 ms

--- RECOMMENDATION 6: Remove Duplicate Indexes (if found) ---

Time: 0.771 ms

=========================================
Recommendations Generated
=========================================

IMPORTANT:
1. Review all recommendations before executing
2. Test in a development environment first
3. Create a backup before making changes
4. Run ANALYZE after creating new indexes
5. Monitor performance after changes

Save recommendations to a file:
psql -h localhost -U postgres -d your_db -f 02_generate_recommendations.sql > recommendations.sql

