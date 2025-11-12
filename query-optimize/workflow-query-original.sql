-- Original workflow query from XNAT
-- This query retrieves workflow data for a specific experiment and related assessors
-- Performance issues: Multiple subqueries, UNION operations, and nested selects

SELECT
    q.wrk_workflowdata_id,
    q.id,
    q.externalid,
    q.pipeline_name,
    q.data_type,
    q.comments,
    q.details,
    q.justification,
    q.launch_time,
    q.status,
    q.step_description,
    q.percentagecomplete,
    q.last_modified,
    q.create_user,
    q.label,
    q.shared_project
FROM (
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
    FROM (
        SELECT *
        FROM wrk_workflowdata w
        WHERE w.id = $1
           OR w.id IN (
                SELECT DISTINCT id
                FROM (
                    SELECT iad.id
                    FROM xnat_imageassessordata iad
                    WHERE iad.id IS NOT NULL
                      AND iad.imagesession_id = $2

                    UNION

                    SELECT iah.id
                    FROM xnat_imageassessordata_history iah
                    WHERE iah.id IS NOT NULL
                      AND iah.imagesession_id = $3
                ) AS idq
            )
    ) AS w
    INNER JOIN xnat_experimentdata e
        ON w.id = e.id
    LEFT JOIN xnat_experimentdata_share s
        ON e.id = s.sharing_share_xnat_experimentda_id
    LEFT JOIN wrk_workflowdata_meta_data m
        ON w.workflowdata_info = m.meta_data_id
    LEFT JOIN xdat_user u
        ON m.insert_user_xdat_user_id = u.xdat_user_id
) AS q
ORDER BY q.wrk_workflowdata_id DESC
LIMIT 50;
