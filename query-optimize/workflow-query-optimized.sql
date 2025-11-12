-- Optimized workflow query for XNAT
-- Improvements:
-- 1. Simplified subquery structure
-- 2. Used UNION ALL instead of UNION (no need for DISTINCT when using DISTINCT later)
-- 3. Reduced nesting levels
-- 4. Better use of indexes
-- 5. Removed redundant IS NOT NULL checks (handled by WHERE/JOIN conditions)

WITH assessor_ids AS (
    -- Combine current and historical assessor IDs in one CTE
    SELECT DISTINCT id
    FROM xnat_imageassessordata
    WHERE imagesession_id = $2

    UNION ALL

    SELECT DISTINCT id
    FROM xnat_imageassessordata_history
    WHERE imagesession_id = $3
),
workflow_subset AS (
    -- Get workflow data for the experiment and its assessors
    SELECT
        w.wrk_workflowdata_id,
        w.id,
        w.externalid,
        w.pipeline_name,
        w.data_type,
        w.comments,
        w.details,
        w.justification,
        w.launch_time,
        w.status,
        w.step_description,
        w.percentagecomplete,
        w.last_modified,
        w.create_user,
        w.workflowdata_info
    FROM wrk_workflowdata w
    WHERE w.id = $1
       OR w.id IN (SELECT id FROM assessor_ids)
)
SELECT
    ws.wrk_workflowdata_id,
    ws.id,
    ws.externalid,
    ws.pipeline_name,
    ws.data_type,
    ws.comments,
    ws.details,
    ws.justification,
    ws.launch_time,
    ws.status,
    ws.step_description,
    ws.percentagecomplete,
    ws.last_modified,
    COALESCE(ws.create_user, u.login) AS create_user,
    e.label,
    s.project AS shared_project
FROM workflow_subset ws
INNER JOIN xnat_experimentdata e
    ON ws.id = e.id
LEFT JOIN xnat_experimentdata_share s
    ON e.id = s.sharing_share_xnat_experimentda_id
LEFT JOIN wrk_workflowdata_meta_data m
    ON ws.workflowdata_info = m.meta_data_id
LEFT JOIN xdat_user u
    ON m.insert_user_xdat_user_id = u.xdat_user_id
ORDER BY ws.wrk_workflowdata_id DESC
LIMIT 50;

-- ============================================================================
-- FURTHER OPTIMIZATIONS (if needed)
-- ============================================================================

-- Option 1: If you only need the main experiment's workflow (not assessors)
-- This avoids the UNION entirely:
/*
SELECT
    w.wrk_workflowdata_id,
    w.id,
    w.externalid,
    w.pipeline_name,
    w.data_type,
    w.comments,
    w.details,
    w.justification,
    w.launch_time,
    w.status,
    w.step_description,
    w.percentagecomplete,
    w.last_modified,
    COALESCE(w.create_user, u.login) AS create_user,
    e.label,
    s.project AS shared_project
FROM wrk_workflowdata w
INNER JOIN xnat_experimentdata e
    ON w.id = e.id
LEFT JOIN xnat_experimentdata_share s
    ON e.id = s.sharing_share_xnat_experimentda_id
LEFT JOIN wrk_workflowdata_meta_data m
    ON w.workflowdata_info = m.meta_data_id
LEFT JOIN xdat_user u
    ON m.insert_user_xdat_user_id = u.xdat_user_id
WHERE w.id = $1
ORDER BY w.wrk_workflowdata_id DESC
LIMIT 50;
*/

-- Option 2: If assessor workflows are frequently accessed separately,
-- consider splitting into two queries and combining results in application code

-- Option 3: If workflow data rarely changes, consider materialized view:
/*
CREATE MATERIALIZED VIEW mv_experiment_workflows AS
SELECT
    w.wrk_workflowdata_id,
    w.id,
    w.externalid,
    w.pipeline_name,
    w.data_type,
    w.launch_time,
    w.status,
    w.last_modified,
    COALESCE(w.create_user, u.login) AS create_user,
    e.label,
    e.project
FROM wrk_workflowdata w
INNER JOIN xnat_experimentdata e ON w.id = e.id
LEFT JOIN wrk_workflowdata_meta_data m ON w.workflowdata_info = m.meta_data_id
LEFT JOIN xdat_user u ON m.insert_user_xdat_user_id = u.xdat_user_id;

CREATE INDEX idx_mv_experiment_workflows_id ON mv_experiment_workflows(id);
CREATE INDEX idx_mv_experiment_workflows_project ON mv_experiment_workflows(project);

-- Refresh periodically:
REFRESH MATERIALIZED VIEW CONCURRENTLY mv_experiment_workflows;
*/
