# Schema-Based Index Recommendations

**Date:** 2025-11-12
**Method:** Analyzed table schemas, column types, and data patterns
**Scope:** Top 30 tables by size with >1000 rows

---

## Methodology

For each table, we analyzed:
1. **Column types** - timestamp, varchar, integer (indexable types)
2. **Common query patterns** - WHERE clauses, JOINs, ORDER BY
3. **Cardinality** - High-selectivity columns are better index candidates
4. **Existing indexes** - Avoid duplicates
5. **Table size & row count** - Prioritize large tables

---

## Index Recommendations by Table

### 1. xdat_change_info (50 MB, 257K rows)
**Purpose:** Audit/change tracking table

**Schema-based recommendations:**
```sql
-- Date-based queries (common in audit logs)
CREATE INDEX idx_change_info_change_date
ON xdat_change_info(change_date DESC);

-- User-based audit queries
CREATE INDEX idx_change_info_change_user_date
ON xdat_change_info(change_user, change_date DESC);

-- Event lookup
CREATE INDEX idx_change_info_event_id
ON xdat_change_info(event_id)
WHERE event_id IS NOT NULL;
```

**Rationale:**
- Audit logs are typically queried by date range ("changes in last 7 days")
- User-specific audit trails need user+date composite
- Event_id for correlation with other systems

---

### 2. xhbm_container_entity_history (14 MB, 96K rows)
**Purpose:** Container execution history

**Schema-based recommendations:**
```sql
-- Already recommended: container_entity FK index

-- Status-based queries (failed containers, running containers)
CREATE INDEX idx_container_history_status_time
ON xhbm_container_entity_history(status, time_recorded DESC);

-- Entity lookup with time range
CREATE INDEX idx_container_history_entity_time
ON xhbm_container_entity_history(entity_id, time_recorded DESC);

-- Exit code analysis (failures)
CREATE INDEX idx_container_history_exit_code
ON xhbm_container_entity_history(exit_code)
WHERE exit_code != 0;  -- Partial index for failures only
```

**Rationale:**
- History tables are queried by status ("all failed runs")
- Time-series analysis needs time_recorded sorting
- Failure analysis needs exit_code filtering

---

### 3. wrk_workflowdata (13 MB, 34K rows)
**Purpose:** Workflow execution tracking

**Already well-indexed:** 15 indexes exist

**Additional schema-based recommendations:**
```sql
-- Pipeline + launch time (workflow history by pipeline)
CREATE INDEX idx_workflow_pipeline_launch
ON wrk_workflowdata(pipeline_name, launch_time DESC)
WHERE status != 'Complete';

-- Composite for active workflows
CREATE INDEX idx_workflow_active
ON wrk_workflowdata(status, current_step_launch_time DESC)
WHERE status IN ('Running', 'Queued', 'Pending');
```

**Rationale:**
- Workflow queries often filter by pipeline + time range
- Active workflow monitoring needs status + current step time
- Partial indexes reduce size for specific use cases

---

### 4. xdat_user_login (12 MB, 40K rows)
**Purpose:** User session tracking

**Schema-based recommendations:**
```sql
-- Already recommended: session_id index

-- Active sessions (not logged out)
CREATE INDEX idx_user_login_active_sessions
ON xdat_user_login(user_xdat_user_id, login_date DESC)
WHERE logout_date IS NULL;

-- IP-based analysis
CREATE INDEX idx_user_login_ip_date
ON xdat_user_login(ip_address, login_date DESC);

-- Session duration analysis
CREATE INDEX idx_user_login_user_dates
ON xdat_user_login(user_xdat_user_id, login_date, logout_date);
```

**Rationale:**
- Active session tracking needs WHERE logout_date IS NULL
- Security analysis needs IP + date filtering
- User activity reports need user + date range

---

### 5. xhbm_dicom_spatial_data (11 MB, 25K rows)
**Purpose:** DICOM spatial coordinates

**Schema-based recommendations:**
```sql
-- Frame lookup (common in viewer applications)
CREATE INDEX idx_dicom_spatial_frame
ON xhbm_dicom_spatial_data(frame_number)
WHERE NOT disabled;

-- Series-based retrieval
CREATE INDEX idx_dicom_spatial_series
ON xhbm_dicom_spatial_data(series_uid, frame_number);

-- SOP instance lookup
CREATE INDEX idx_dicom_spatial_sop
ON xhbm_dicom_spatial_data(sop_instance_uid);

-- Frame of reference (spatial registration)
CREATE INDEX idx_dicom_spatial_frame_ref
ON xhbm_dicom_spatial_data(frame_of_reference_uid);
```

**Rationale:**
- DICOM viewers query by frame_number for navigation
- Series retrieval is fundamental DICOM operation
- SOP instance UID is unique identifier
- Frame of reference for 3D registration

---

### 6. xhbm_container_entity (6 MB, 15K rows)
**Purpose:** Container definitions and state

**Schema-based recommendations:**
```sql
-- Already recommended: parent_container_entity FK

-- Status monitoring
CREATE INDEX idx_container_entity_status_time
ON xhbm_container_entity(status, status_time DESC)
WHERE NOT disabled;

-- Project-based container queries
CREATE INDEX idx_container_entity_project_created
ON xhbm_container_entity(project, created DESC)
WHERE NOT disabled;

-- Workflow tracking
CREATE INDEX idx_container_entity_workflow
ON xhbm_container_entity(workflow_id)
WHERE workflow_id IS NOT NULL;

-- Service-based lookup
CREATE INDEX idx_container_entity_service
ON xhbm_container_entity(service_id)
WHERE service_id IS NOT NULL;

-- Docker image queries (which containers use this image?)
CREATE INDEX idx_container_entity_docker_image
ON xhbm_container_entity(docker_image);
```

**Rationale:**
- Container monitoring needs status + time filtering
- Project views need project-based queries
- Workflow integration needs workflow_id lookup
- Service orchestration needs service_id
- Image management needs docker_image index

---

### 7. xnat_resource (6 MB, 12K rows)
**Purpose:** Resource files (DICOM, NIFTI, etc.)

**Schema-based recommendations:**
```sql
-- Format-based queries (all DICOMs, all NIFTIs)
CREATE INDEX idx_resource_format
ON xnat_resource(format);

-- Content type queries
CREATE INDEX idx_resource_content
ON xnat_resource(content);

-- Provenance tracking
CREATE INDEX idx_resource_provenance
ON xnat_resource(provenance_prov_process_id)
WHERE provenance_prov_process_id IS NOT NULL;
```

**Rationale:**
- Users search resources by format ("all DICOM files")
- Content classification for resource management
- Provenance tracking for reproducibility

---

### 8. xhbm_container_entity_log_paths (2 MB, 18K rows)
**Purpose:** Container log file paths

**⚠️ NO INDEXES!**

**Schema-based recommendations:**
```sql
-- Container lookup (critical!)
CREATE INDEX idx_container_log_paths_container
ON xhbm_container_entity_log_paths(container_entity);
```

**Rationale:**
- This table has ZERO indexes despite 18K rows
- Every log lookup requires full table scan
- Critical for debugging and monitoring

---

### 9. xnat_imagescandata (2 MB, 5K rows)
**Purpose:** Image scan metadata

**Schema-based recommendations:**
```sql
-- Session-based queries (all scans in a session)
CREATE INDEX idx_imagescandata_session_series
ON xnat_imagescandata(image_session_id, series_description);

-- Modality-based queries (all CT scans, all MR scans)
CREATE INDEX idx_imagescandata_modality
ON xnat_imagescandata(modality);

-- Quality filtering
CREATE INDEX idx_imagescandata_quality
ON xnat_imagescandata(quality)
WHERE quality IS NOT NULL;

-- UID-based lookup (DICOM queries)
CREATE INDEX idx_imagescandata_uid
ON xnat_imagescandata(uid);

-- Project-based scan queries
CREATE INDEX idx_imagescandata_project_type
ON xnat_imagescandata(project, type);
```

**Rationale:**
- Session views need all scans for a session
- Modality filtering is common in search
- Quality control workflows need quality filtering
- DICOM integration needs UID lookup
- Project dashboards need project-based filtering

---

### 10. xnat_experimentdata (1.4 MB, 3K rows)
**Purpose:** Experiment metadata

**Schema-based recommendations:**
```sql
-- Already recommended: visit FK

-- Project-based queries
CREATE INDEX idx_experimentdata_project_label
ON xnat_experimentdata(project, label);

-- Investigator-based queries
CREATE INDEX idx_experimentdata_investigator
ON xnat_experimentdata(investigator_xnat_investigatordata_id)
WHERE investigator_xnat_investigatordata_id IS NOT NULL;

-- Version tracking
CREATE INDEX idx_experimentdata_version
ON xnat_experimentdata(original, version)
WHERE original IS NOT NULL;
```

**Rationale:**
- Project searches need project + label
- Investigator reports need investigator filtering
- Version control needs original + version composite

---

## Summary by Category

### Temporal Indexes (Date/Time-based queries)
```sql
-- Audit logs
CREATE INDEX idx_change_info_change_date ON xdat_change_info(change_date DESC);
CREATE INDEX idx_change_info_change_user_date ON xdat_change_info(change_user, change_date DESC);

-- Container history
CREATE INDEX idx_container_history_status_time ON xhbm_container_entity_history(status, time_recorded DESC);
CREATE INDEX idx_container_history_entity_time ON xhbm_container_entity_history(entity_id, time_recorded DESC);

-- Container status
CREATE INDEX idx_container_entity_status_time ON xhbm_container_entity(status, status_time DESC) WHERE NOT disabled;
CREATE INDEX idx_container_entity_project_created ON xhbm_container_entity(project, created DESC) WHERE NOT disabled;

-- User sessions
CREATE INDEX idx_user_login_active_sessions ON xdat_user_login(user_xdat_user_id, login_date DESC) WHERE logout_date IS NULL;
CREATE INDEX idx_user_login_ip_date ON xdat_user_login(ip_address, login_date DESC);

-- Workflow tracking
CREATE INDEX idx_workflow_pipeline_launch ON wrk_workflowdata(pipeline_name, launch_time DESC) WHERE status != 'Complete';
```

### Lookup Indexes (ID/UID-based queries)
```sql
-- DICOM identifiers
CREATE INDEX idx_dicom_spatial_sop ON xhbm_dicom_spatial_data(sop_instance_uid);
CREATE INDEX idx_dicom_spatial_series ON xhbm_dicom_spatial_data(series_uid, frame_number);
CREATE INDEX idx_dicom_spatial_frame_ref ON xhbm_dicom_spatial_data(frame_of_reference_uid);
CREATE INDEX idx_imagescandata_uid ON xnat_imagescandata(uid);

-- Container tracking
CREATE INDEX idx_container_entity_workflow ON xhbm_container_entity(workflow_id) WHERE workflow_id IS NOT NULL;
CREATE INDEX idx_container_entity_service ON xhbm_container_entity(service_id) WHERE service_id IS NOT NULL;
CREATE INDEX idx_container_log_paths_container ON xhbm_container_entity_log_paths(container_entity);

-- Event tracking
CREATE INDEX idx_change_info_event_id ON xdat_change_info(event_id) WHERE event_id IS NOT NULL;

-- Provenance
CREATE INDEX idx_resource_provenance ON xnat_resource(provenance_prov_process_id) WHERE provenance_prov_process_id IS NOT NULL;
```

### Classification Indexes (Type/Status/Category queries)
```sql
-- Resource classification
CREATE INDEX idx_resource_format ON xnat_resource(format);
CREATE INDEX idx_resource_content ON xnat_resource(content);

-- Scan classification
CREATE INDEX idx_imagescandata_modality ON xnat_imagescandata(modality);
CREATE INDEX idx_imagescandata_quality ON xnat_imagescandata(quality) WHERE quality IS NOT NULL;

-- Container classification
CREATE INDEX idx_container_entity_docker_image ON xhbm_container_entity(docker_image);

-- Workflow status
CREATE INDEX idx_workflow_active ON wrk_workflowdata(status, current_step_launch_time DESC) WHERE status IN ('Running', 'Queued', 'Pending');
CREATE INDEX idx_container_history_status_time ON xhbm_container_entity_history(status, time_recorded DESC);
```

### Project/Subject Context Indexes
```sql
-- Project-based queries
CREATE INDEX idx_container_entity_project_created ON xhbm_container_entity(project, created DESC) WHERE NOT disabled;
CREATE INDEX idx_experimentdata_project_label ON xnat_experimentdata(project, label);
CREATE INDEX idx_imagescandata_project_type ON xnat_imagescandata(project, type);
```

### Partial Indexes (Filtered for specific use cases)
```sql
-- Active only
CREATE INDEX idx_container_entity_status_time ON xhbm_container_entity(status, status_time DESC) WHERE NOT disabled;
CREATE INDEX idx_dicom_spatial_frame ON xhbm_dicom_spatial_data(frame_number) WHERE NOT disabled;
CREATE INDEX idx_user_login_active_sessions ON xdat_user_login(user_xdat_user_id, login_date DESC) WHERE logout_date IS NULL;

-- Non-null only
CREATE INDEX idx_container_entity_workflow ON xhbm_container_entity(workflow_id) WHERE workflow_id IS NOT NULL;
CREATE INDEX idx_resource_provenance ON xnat_resource(provenance_prov_process_id) WHERE provenance_prov_process_id IS NOT NULL;
CREATE INDEX idx_change_info_event_id ON xdat_change_info(event_id) WHERE event_id IS NOT NULL;

-- Failures only
CREATE INDEX idx_container_history_exit_code ON xhbm_container_entity_history(exit_code) WHERE exit_code != 0;
```

---

## Total Recommendations

| Category | Count | Priority |
|----------|-------|----------|
| Temporal (date/time) | 8 | High |
| Lookup (ID/UID) | 10 | High |
| Classification (type/status) | 7 | Medium |
| Project/Context | 3 | Medium |
| Partial indexes | 8 | Medium |
| **TOTAL** | **36 new indexes** | - |

**Combined with previous testing:**
- Previously tested: 24 indexes (20 FK + 4 non-FK)
- New schema-based: 36 indexes
- **Grand total: 60 indexes recommended**

---

## Next Steps

1. **Priority 1: Critical Missing Indexes**
   - xhbm_container_entity_log_paths (NO INDEXES!)
   - xdat_change_info temporal indexes (audit queries)
   - DICOM spatial data lookups

2. **Priority 2: High-Volume Tables**
   - Container history status/time indexes
   - User login session indexes
   - Workflow monitoring indexes

3. **Priority 3: Performance Optimization**
   - Partial indexes for common filters
   - Composite indexes for multi-column queries
   - Project/context-based indexes

4. **Testing Strategy**
   - Create automated test script for all 36 indexes
   - Run A/B tests with 5 iterations each
   - Keep if >5% improvement, rollback otherwise
   - Generate production SQL for proven indexes

---

## Estimated Impact

**Conservative estimate:**
- 20-30 indexes will show >10% improvement
- 10-15 indexes will show 5-10% improvement
- 0-5 indexes will show <5% improvement (rollback)

**Expected results:**
- 50-80% of schema-based indexes will be kept
- 25-30 proven indexes from this analysis
- Combined with previous 24 = **50-55 total production indexes**
- Average improvement: 40-60% for affected queries

**Disk space:**
- ~30-50 MB for all 36 indexes
- Partial indexes reduce space (only index subset of rows)
- Composite indexes provide multi-query optimization

---

**Generated:** 2025-11-12
**Status:** Ready for automated testing
**Method:** Schema analysis + query pattern inference
