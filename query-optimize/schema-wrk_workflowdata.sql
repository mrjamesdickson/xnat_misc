-- Table schema for wrk_workflowdata
-- XNAT Workflow Data table structure
-- Generated: 2025-11-12

CREATE TABLE IF NOT EXISTS public.wrk_workflowdata (
    -- Execution Environment
    executionenvironment_wrk_abstractexecutionenvironment_id integer,

    -- Workflow Details
    comments text,
    details text,
    justification text,
    description character varying(255),
    src character varying(255),
    type character varying(255),
    category character varying(255),

    -- Core Identifiers
    data_type character varying(255) NOT NULL DEFAULT ''::character varying,
    id character varying(255) NOT NULL DEFAULT ''::character varying,
    externalid character varying(255),

    -- Step Information
    current_step_launch_time timestamp without time zone,
    current_step_id character varying(255),
    next_step_id character varying(255),
    step_description character varying(255),

    -- Status and Tracking
    status character varying(255) NOT NULL DEFAULT ''::character varying,
    create_user character varying(255),
    pipeline_name character varying(255) NOT NULL DEFAULT ''::character varying,
    launch_time timestamp without time zone NOT NULL DEFAULT now(),
    percentagecomplete character varying(255),
    jobid character varying(255),

    -- Metadata References
    workflowdata_info integer,
    wrk_workflowdata_id integer NOT NULL DEFAULT nextval('wrk_workflowdata_wrk_workflowdata_id_seq'::regclass),

    -- Scan Reference
    scan_id character varying(255),

    -- Primary Key
    CONSTRAINT wrk_workflowdata_pkey PRIMARY KEY (wrk_workflowdata_id),

    -- Unique Constraint
    CONSTRAINT wrk_workflowdata_u_true UNIQUE (id, scan_id, pipeline_name, launch_time),

    -- Foreign Keys
    CONSTRAINT wrk_workflowdata_executionenvironment_wrk_abstractexecutio_fkey
        FOREIGN KEY (executionenvironment_wrk_abstractexecutionenvironment_id)
        REFERENCES wrk_abstractexecutionenvironment(wrk_abstractexecutionenvironment_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL,

    CONSTRAINT wrk_workflowdata_workflowdata_info_fkey
        FOREIGN KEY (workflowdata_info)
        REFERENCES wrk_workflowdata_meta_data(meta_data_id)
        ON UPDATE CASCADE
        ON DELETE SET NULL
);

-- ============================================================================
-- EXISTING INDEXES (Already in XNAT)
-- ============================================================================

-- Primary Key Index (automatically created)
-- CREATE UNIQUE INDEX wrk_workflowdata_pkey ON wrk_workflowdata USING btree (wrk_workflowdata_id);

-- Category index
CREATE INDEX IF NOT EXISTS wrk_workflowdata_category_btree
ON wrk_workflowdata USING btree (category);

-- Current step launch time
CREATE INDEX IF NOT EXISTS wrk_workflowdata_current_step_launch_time_btree
ON wrk_workflowdata USING btree (current_step_launch_time);

-- Execution environment (btree)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_executionenvironment_wrk_abstractexecuti1
ON wrk_workflowdata USING btree (executionenvironment_wrk_abstractexecutionenvironment_id);

-- Execution environment (hash)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_executionenvironment_wrk_abstractexecuti1_hash
ON wrk_workflowdata USING hash (executionenvironment_wrk_abstractexecutionenvironment_id);

-- ID index (btree)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_id_btree
ON wrk_workflowdata USING btree (id);

-- Composite index: id, launch_time, pipeline_name (normalized)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_id_launchtime_replace_idx
ON wrk_workflowdata USING btree (
    id,
    launch_time,
    replace(replace(pipeline_name::text, '.'::text, '_'::text), ' '::text, '_'::text)
);

-- Launch time index
CREATE INDEX IF NOT EXISTS wrk_workflowdata_launch_time_btree
ON wrk_workflowdata USING btree (launch_time);

-- Pipeline name index
CREATE INDEX IF NOT EXISTS wrk_workflowdata_pipeline_name_btree
ON wrk_workflowdata USING btree (pipeline_name);

-- Composite index: pipeline_name (normalized), id, launch_time
CREATE INDEX IF NOT EXISTS wrk_workflowdata_replace_id_launchtime_idx
ON wrk_workflowdata USING btree (
    replace(replace(pipeline_name::text, '.'::text, '_'::text), ' '::text, '_'::text),
    id,
    launch_time
);

-- Status index
CREATE INDEX IF NOT EXISTS wrk_workflowdata_status_btree
ON wrk_workflowdata USING btree (status);

-- Workflow info index (btree)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_workflowdata_info1
ON wrk_workflowdata USING btree (workflowdata_info);

-- Workflow info index (hash)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_workflowdata_info1_hash
ON wrk_workflowdata USING hash (workflowdata_info);

-- Workflow ID index (hash)
CREATE INDEX IF NOT EXISTS wrk_workflowdata_wrk_workflowdata_id1_hash
ON wrk_workflowdata USING hash (wrk_workflowdata_id);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- Trigger for update/delete operations
CREATE TRIGGER a_u_wrk_workflowdata
    AFTER DELETE OR UPDATE ON wrk_workflowdata
    FOR EACH ROW
    EXECUTE FUNCTION after_update_wrk_workflowdata();

-- ============================================================================
-- TABLE COMMENTS
-- ============================================================================

COMMENT ON TABLE wrk_workflowdata IS 'XNAT workflow execution data and pipeline tracking';

COMMENT ON COLUMN wrk_workflowdata.wrk_workflowdata_id IS 'Primary key, auto-increment';
COMMENT ON COLUMN wrk_workflowdata.id IS 'Experiment or assessor ID this workflow is associated with';
COMMENT ON COLUMN wrk_workflowdata.pipeline_name IS 'Name of the pipeline being executed';
COMMENT ON COLUMN wrk_workflowdata.status IS 'Current workflow status (e.g., Running, Complete, Failed)';
COMMENT ON COLUMN wrk_workflowdata.launch_time IS 'Timestamp when workflow was launched';
COMMENT ON COLUMN wrk_workflowdata.data_type IS 'Type of data being processed';
COMMENT ON COLUMN wrk_workflowdata.percentagecomplete IS 'Current completion percentage';
COMMENT ON COLUMN wrk_workflowdata.step_description IS 'Description of current workflow step';
COMMENT ON COLUMN wrk_workflowdata.scan_id IS 'Optional scan ID if workflow is scan-specific';

-- ============================================================================
-- INDEX ANALYSIS
-- ============================================================================

/*
EXISTING INDEX COVERAGE:

✅ Excellent Coverage:
- wrk_workflowdata_id_btree (id lookup) - CRITICAL for our query
- wrk_workflowdata_status_btree (status filtering)
- wrk_workflowdata_launch_time_btree (ordering)
- wrk_workflowdata_workflowdata_info1 (metadata joins)

⚠️  Potentially Redundant:
- Hash indexes duplicate btree indexes (hash vs btree for same columns)
- Hash indexes are less versatile than btree (can't do range queries)
- Consider dropping hash indexes if not specifically needed

📊 Composite Indexes:
- wrk_workflowdata_id_launchtime_replace_idx - Good for specific pipeline queries
- wrk_workflowdata_replace_id_launchtime_idx - Optimized for pipeline-first lookups
- wrk_workflowdata_u_true - Ensures uniqueness of workflow executions

💡 Recommendation:
The existing indexes are well-optimized for the workflow query.
Our additional recommended indexes focus on JOIN optimization with other tables.
*/

-- ============================================================================
-- OPTIMIZATION NOTES
-- ============================================================================

/*
1. The wrk_workflowdata_id_btree index already handles our WHERE w.id = $1 clause efficiently
2. The status index helps with workflow filtering
3. Launch time index supports ORDER BY optimization
4. The composite indexes handle complex pipeline name queries

Our recommended-indexes.sql adds:
- Indexes on JOINED tables (xnat_imageassessordata, xnat_experimentdata, etc.)
- These complement the existing wrk_workflowdata indexes

Together, these provide comprehensive query optimization.
*/
