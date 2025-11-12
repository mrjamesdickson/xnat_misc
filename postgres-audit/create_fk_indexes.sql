-- ============================================================================
-- RECOMMENDED FOREIGN KEY INDEXES
-- Based on automated performance testing - 55.23% average improvement
-- Safe to run - uses CREATE INDEX IF NOT EXISTS
-- Date: 2025-11-12
-- Database: XNAT PostgreSQL 16.9
-- ============================================================================

\timing on

\echo ''
\echo '========================================='
\echo 'Creating Foreign Key Indexes'
\echo '========================================='
\echo ''
\echo 'This will create 20 indexes on foreign keys'
\echo 'Average expected improvement: 55.23%'
\echo 'Estimated time: 15-20 minutes'
\echo 'Estimated space: 10-15 MB'
\echo ''

-- High Priority (> 70% improvement) ---------------------------------------

\echo '--- High Priority Indexes (70%+ improvement) ---'

-- #1: 94.85% improvement (5.80ms → 0.30ms)
\echo 'Creating idx_container_entity_parent (94.85% improvement)...'
CREATE INDEX IF NOT EXISTS idx_container_entity_parent
ON xhbm_container_entity(parent_container_entity);

-- #2: 84.47% improvement (2.07ms → 0.32ms)
\echo 'Creating idx_experimentdata_visit (84.47% improvement)...'
CREATE INDEX IF NOT EXISTS idx_experimentdata_visit
ON xnat_experimentdata(visit);

-- #3: 79.07% improvement (1.02ms → 0.21ms)
\echo 'Creating idx_imageassessordata_imagesession (79.07% improvement)...'
CREATE INDEX IF NOT EXISTS idx_imageassessordata_imagesession
ON xnat_imageassessordata(imagesession_id);

-- #4: 73.01% improvement (1.10ms → 0.30ms)
\echo 'Creating idx_roicollectiondata_subjectid (73.01% improvement)...'
CREATE INDEX IF NOT EXISTS idx_roicollectiondata_subjectid
ON icr_roicollectiondata(subjectid);

\echo ''

-- Medium Priority (50-70% improvement) ------------------------------------

\echo '--- Medium Priority Indexes (50-70% improvement) ---'

-- #5: 65.93% improvement (1.02ms → 0.35ms)
\echo 'Creating idx_subjectassessordata_subject (65.93% improvement)...'
CREATE INDEX IF NOT EXISTS idx_subjectassessordata_subject
ON xnat_subjectassessordata(subject_id);

-- #6: 65.27% improvement (0.50ms → 0.17ms)
\echo 'Creating idx_automation_filters_values (65.27% improvement)...'
CREATE INDEX IF NOT EXISTS idx_automation_filters_values
ON xhbm_automation_filters_values(automation_filters);

-- #7: 62.75% improvement (0.79ms → 0.30ms)
\echo 'Creating idx_experimentdata_resource_abstractresource (62.75% improvement)...'
CREATE INDEX IF NOT EXISTS idx_experimentdata_resource_abstractresource
ON xnat_experimentdata_resource(xnat_abstractresource_xnat_abstractresource_id);

-- #8: 62.23% improvement (0.89ms → 0.34ms)
\echo 'Creating idx_automation_event_ids_parent (62.23% improvement)...'
CREATE INDEX IF NOT EXISTS idx_automation_event_ids_parent
ON xhbm_automation_event_ids_ids(parent_automation_event_ids);

-- #9: 61.21% improvement (0.56ms → 0.22ms)
\echo 'Creating idx_assessor_out_resource_abstractresource (61.21% improvement)...'
CREATE INDEX IF NOT EXISTS idx_assessor_out_resource_abstractresource
ON img_assessor_out_resource(xnat_abstractresource_xnat_abstractresource_id);

-- #10: 58.91% improvement (0.65ms → 0.27ms)
\echo 'Creating idx_configuration_config_data (58.91% improvement)...'
CREATE INDEX IF NOT EXISTS idx_configuration_config_data
ON xhbm_configuration(config_data);

-- #11: 57.27% improvement (0.73ms → 0.31ms)
\echo 'Creating idx_experimentdata_resource_experimentdata (57.27% improvement)...'
CREATE INDEX IF NOT EXISTS idx_experimentdata_resource_experimentdata
ON xnat_experimentdata_resource(xnat_experimentdata_id);

-- #12: 55.99% improvement (0.75ms → 0.33ms)
\echo 'Creating idx_subscription_delivery_subscription (55.99% improvement)...'
CREATE INDEX IF NOT EXISTS idx_subscription_delivery_subscription
ON xhbm_subscription_delivery_entity(subscription);

\echo ''

-- Standard Priority (30-50% improvement) ----------------------------------

\echo '--- Standard Priority Indexes (30-50% improvement) ---'

-- #13: 48.68% improvement (2.90ms → 1.49ms)
\echo 'Creating idx_container_entity_output_container (48.68% improvement)...'
CREATE INDEX IF NOT EXISTS idx_container_entity_output_container
ON xhbm_container_entity_output(container_entity);

-- #14: 48.35% improvement (0.75ms → 0.39ms)
\echo 'Creating idx_event_filter_entity_project_ids (48.35% improvement)...'
CREATE INDEX IF NOT EXISTS idx_event_filter_entity_project_ids
ON xhbm_event_service_filter_entity_project_ids(event_service_filter_entity);

-- #15: 47.36% improvement (11.92ms → 6.28ms)
\echo 'Creating idx_container_entity_history_container (47.36% improvement)...'
CREATE INDEX IF NOT EXISTS idx_container_entity_history_container
ON xhbm_container_entity_history(container_entity);

-- #16: 42.28% improvement (1.27ms → 0.73ms)
\echo 'Creating idx_timed_event_status_subscription_delivery (42.28% improvement)...'
CREATE INDEX IF NOT EXISTS idx_timed_event_status_subscription_delivery
ON xhbm_timed_event_status_entity(subscription_delivery_entity);

-- #17: 38.96% improvement (3.71ms → 2.26ms)
\echo 'Creating idx_container_entity_mount_container (38.96% improvement)...'
CREATE INDEX IF NOT EXISTS idx_container_entity_mount_container
ON xhbm_container_entity_mount(container_entity);

\echo ''

-- Low Priority (11-30% improvement) ---------------------------------------

\echo '--- Low Priority Indexes (11-30% improvement) ---'

-- #18: 28.24% improvement (0.38ms → 0.28ms)
\echo 'Creating idx_assessor_out_resource_imageassessordata (28.24% improvement)...'
CREATE INDEX IF NOT EXISTS idx_assessor_out_resource_imageassessordata
ON img_assessor_out_resource(xnat_imageassessordata_id);

-- #19: 18.59% improvement (0.46ms → 0.38ms)
\echo 'Creating idx_subscription_delivery_triggering_event (18.59% improvement)...'
CREATE INDEX IF NOT EXISTS idx_subscription_delivery_triggering_event
ON xhbm_subscription_delivery_entity(triggering_event_entity);

-- #20: 11.17% improvement (1.68ms → 1.49ms)
\echo 'Creating idx_container_entity_log_paths_container (11.17% improvement)...'
CREATE INDEX IF NOT EXISTS idx_container_entity_log_paths_container
ON xhbm_container_entity_log_paths(container_entity);

\echo ''
\echo 'All indexes created successfully'
\echo ''

-- ============================================================================
-- POST-INDEX MAINTENANCE
-- ============================================================================

\echo '--- Updating Statistics ---'

ANALYZE xhbm_container_entity;
ANALYZE xnat_experimentdata;
ANALYZE xnat_imageassessordata;
ANALYZE icr_roicollectiondata;
ANALYZE xnat_subjectassessordata;
ANALYZE xhbm_automation_filters_values;
ANALYZE xnat_experimentdata_resource;
ANALYZE xhbm_automation_event_ids_ids;
ANALYZE img_assessor_out_resource;
ANALYZE xhbm_configuration;
ANALYZE xhbm_subscription_delivery_entity;
ANALYZE xhbm_container_entity_output;
ANALYZE xhbm_event_service_filter_entity_project_ids;
ANALYZE xhbm_container_entity_history;
ANALYZE xhbm_timed_event_status_entity;
ANALYZE xhbm_container_entity_mount;
ANALYZE xhbm_container_entity_log_paths;

\echo ''
\echo 'Statistics updated'
\echo ''

-- ============================================================================
-- VERIFICATION
-- ============================================================================

\echo '========================================='
\echo 'VERIFICATION'
\echo '========================================='
\echo ''
\echo '--- Created Indexes ---'

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE indexname IN (
    'idx_container_entity_parent',
    'idx_experimentdata_visit',
    'idx_imageassessordata_imagesession',
    'idx_roicollectiondata_subjectid',
    'idx_subjectassessordata_subject',
    'idx_automation_filters_values',
    'idx_experimentdata_resource_abstractresource',
    'idx_automation_event_ids_parent',
    'idx_assessor_out_resource_abstractresource',
    'idx_configuration_config_data',
    'idx_experimentdata_resource_experimentdata',
    'idx_subscription_delivery_subscription',
    'idx_container_entity_output_container',
    'idx_event_filter_entity_project_ids',
    'idx_container_entity_history_container',
    'idx_timed_event_status_subscription_delivery',
    'idx_container_entity_mount_container',
    'idx_assessor_out_resource_imageassessordata',
    'idx_subscription_delivery_triggering_event',
    'idx_container_entity_log_paths_container'
)
ORDER BY tablename, indexname;

\echo ''
\echo '========================================='
\echo 'COMPLETE'
\echo '========================================='
\echo ''
\echo 'Summary:'
\echo '- 20 foreign key indexes created'
\echo '- Average expected improvement: 55.23%'
\echo '- Statistics updated for all affected tables'
\echo ''
\echo 'Next Steps:'
\echo '1. Monitor query performance over next 24 hours'
\echo '2. Check pg_stat_statements for query time improvements'
\echo '3. Review pg_stat_user_indexes for index usage'
\echo ''
\echo 'To monitor:'
\echo 'SELECT indexname, idx_scan FROM pg_stat_user_indexes'
\echo 'WHERE indexname LIKE ''idx_%'''
\echo 'ORDER BY idx_scan DESC;'
\echo ''
