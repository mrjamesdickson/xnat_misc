# XNAT DICOM Modality Ingestion - Recommended Recognition Order

**Document Version:** 1.0
**Date:** 2025-11-12
**Purpose:** Provide recommended ordering for DICOM modality recognition and mapping to XNAT imageSessionData types

---

## Executive Summary

XNAT maps DICOM studies to specific `xnat:*SessionData` types using **SOP Class UIDs** (not just the Modality tag) via the `DICOMSessionBuilder` class. This document provides a recommended priority order for modality recognition to ensure accurate classification during DICOM ingestion.

**Key Principle:** Recognition order should prioritize **specificity over generality** - more specific modalities/SOP classes should be checked before generic catch-all types.

---

## How XNAT Currently Maps Modalities

### Architecture

1. **Primary Mapping Key:** DICOM SOP Class UID `(0008,0016)` - NOT just Modality `(0008,0060)`
2. **Mapping Engine:** `DICOMSessionBuilder` (in `org.nrg:SessionBuilders` library)
3. **Factory Pattern:** `XnatImagesessiondataBeanFactory` implementations handle specific SOP classes
4. **Fallback:** `xnat:otherDicomSessionData` for unrecognized modalities

### Code Reference

**File:** `xnat-web/src/main/java/org/nrg/xnat/archive/XNATSessionBuilder.java`

```java
// Lines 169-186: Builder execution order
for (final BuilderConfig bc : BUILDER_CLASSES) {
    switch (bc.getCode()) {
        case DICOM:
            buildDicomSession();  // Calls DICOMSessionBuilder
            break;
        case ECAT:
            buildPetSession();    // Specialized PET format
            break;
        default:
            buildCustomSession(bc);
    }
    if (xml.exists() && xml.length() > 0) {
        break;  // Stop on first successful match
    }
}
```

**Key Behavior:** First successful match wins - order matters!

---

## Recommended Recognition Order

### Priority Levels

Recognition should follow this hierarchy to ensure accurate classification:

#### **Tier 1: High-Priority Clinical Imaging (Primary Modalities)**

These are the most common modalities in clinical practice and should be recognized first to optimize performance and accuracy.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 1 | MR | `xnat:mrSessionData` | MR | 1.2.840.10008.5.1.4.1.1.4 | Most common research modality |
| 2 | CT | `xnat:ctSessionData` | CT | 1.2.840.10008.5.1.4.1.1.2 | Second most common, clear distinction |
| 3 | PET | `xnat:petSessionData` | PT | 1.2.840.10008.5.1.4.1.1.128 | Distinct modality, check before PET/MR |
| 4 | PET/MR | `xnat:petmrSessionData` | PT+MR | Multiple SOP classes | Combined modality, check after individual PET/MR |
| 5 | US | `xnat:usSessionData` | US | 1.2.840.10008.5.1.4.1.1.6.1 | Common ultrasound studies |
| 6 | NM | `xnat:nmSessionData` | NM | 1.2.840.10008.5.1.4.1.1.20 | Nuclear medicine (distinct from PET) |

**Configuration Note:** XNAT has a `separatePETMR` preference to control whether PET/MR studies are split into separate PET and MR sessions.

**Code Reference:** `XNATSessionBuilder.java:243`
```java
final boolean createPetMrAsPet = HandlePetMr.get(params.get(SEPARATE_PET_MR)) == HandlePetMr.Pet;
```

---

#### **Tier 2: Specialized Imaging (Modality-Specific Subtypes)**

These are specialized versions of common modalities or domain-specific imaging types.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 7 | XA (3D) | `xnat:xa3DSessionData` | XA | 1.2.840.10008.5.1.4.1.1.12.2.1 | 3D angiography (check before standard XA) |
| 8 | XA | `xnat:xaSessionData` | XA | 1.2.840.10008.5.1.4.1.1.12.1 | X-ray angiography |
| 9 | RF | `xnat:rfSessionData` | RF | 1.2.840.10008.5.1.4.1.1.12.2 | Radio fluoroscopy |
| 10 | DX (3D Cranio) | `xnat:dx3DCraniofacialSessionData` | DX | 1.2.840.10008.5.1.4.1.1.1.1 | Specialized dental/cranial (check before DX) |
| 11 | DX | `xnat:dxSessionData` | DX | 1.2.840.10008.5.1.4.1.1.1.1 | Digital radiography |
| 12 | CR | `xnat:crSessionData` | CR | 1.2.840.10008.5.1.4.1.1.1 | Computed radiography |
| 13 | MG | `xnat:mgSessionData` | MG | 1.2.840.10008.5.1.4.1.1.1.2 | Mammography |

**Rationale:** Specialized subtypes (3D, craniofacial) should be checked before their generic counterparts to prevent misclassification.

---

#### **Tier 3: Radiation Therapy and Treatment Planning**

Radiation therapy has multiple SOP classes (image, dose, structure set, plan). These should be grouped together.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 14 | RT | `xnat:rtSessionData` | RTIMAGE, RTDOSE, RTSTRUCT, RTPLAN | 1.2.840.10008.5.1.4.1.1.481.x | Multi-object radiation therapy session |

**Note:** RT sessions may contain multiple SOP classes:
- `1.2.840.10008.5.1.4.1.1.481.1` (RT Image Storage)
- `1.2.840.10008.5.1.4.1.1.481.2` (RT Dose Storage)
- `1.2.840.10008.5.1.4.1.1.481.3` (RT Structure Set Storage)
- `1.2.840.10008.5.1.4.1.1.481.5` (RT Plan Storage)

---

#### **Tier 4: Ophthalmic Imaging**

Ophthalmic modalities have overlapping characteristics and should be ordered carefully.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 15 | OPT | `xnat:optSessionData` | OPT | 1.2.840.10008.5.1.4.1.1.77.1.5.4 | Ophthalmic tomography (OCT) |
| 16 | OP | `xnat:opSessionData` | OP | 1.2.840.10008.5.1.4.1.1.77.1.5.1 | Ophthalmic photography |

**Rationale:** OPT (tomography) is more specific than OP (photography), check first.

---

#### **Tier 5: Pathology and Microscopy**

Pathology has video and static variants that need careful ordering.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 17 | SM | `xnat:smSessionData` | SM | 1.2.840.10008.5.1.4.1.1.77.1.6 | Whole slide microscopy (WSI) |
| 18 | GMV | `xnat:gmvSessionData` | GM (video) | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | Microscopy video (check before static) |
| 19 | GM | `xnat:gmSessionData` | GM | 1.2.840.10008.5.1.4.1.1.77.1.4 | General microscopy (static) |

**Note:** Distinguish video from static images via SOP class or multi-frame attributes.

---

#### **Tier 6: Endoscopy and Visible Light Photography**

These modalities share VL (Visible Light) SOP class prefixes and overlap significantly.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 20 | ESV | `xnat:esvSessionData` | ES (video) | 1.2.840.10008.5.1.4.1.1.77.1.1.1 | Endoscopy video (check before static) |
| 21 | ES | `xnat:esSessionData` | ES | 1.2.840.10008.5.1.4.1.1.77.1.1 | Endoscopy (static) |
| 22 | XCV | `xnat:xcvSessionData` | XC (video) | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | External camera video (check before static) |
| 23 | XC | `xnat:xcSessionData` | XC | 1.2.840.10008.5.1.4.1.1.77.1.4 | External camera photography |

**Rationale:** Video variants should be checked before static image variants to prevent video studies being classified as static.

---

#### **Tier 7: Specialized and Emerging Modalities**

Newer or less common modalities that don't fit standard categories.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 24 | IO | `xnat:ioSessionData` | IO | 1.2.840.10008.5.1.4.1.1.1.3 | Intra-oral radiography (dental) |
| 25 | IVUS | `xnat:ivusSessionData` | IVUS | 1.2.840.10008.5.1.4.1.1.6.2 | Intravascular ultrasound |
| 26 | PA | `xnat:paSessionData` | PA | 1.2.840.10008.5.1.4.1.1.68.1 | Photoacoustic imaging (emerging) |
| 27 | HD | `xnat:hdSessionData` | HD | 1.2.840.10008.5.1.4.1.1.9.1.x | Hemodynamic waveform |

**Note:** PA (Photoacoustic) is a relatively new DICOM modality - verify implementation in current DICOM standard.

---

#### **Tier 8: Waveforms and Electrophysiology**

Non-image data types (waveforms, measurements, signals).

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 28 | ECG | `xnat:ecgSessionData` | ECG | 1.2.840.10008.5.1.4.1.1.9.1.1 | 12-lead ECG waveform |
| 29 | EEG | `xnat:eegSessionData` | EEG | 1.2.840.10008.5.1.4.1.1.9.x.x | Electroencephalography |
| 30 | MEG | `xnat:megSessionData` | MEG | 1.2.840.10008.5.1.4.1.1.9.x.x | Magnetoencephalography |
| 31 | EPS | `xnat:epsSessionData` | EPS | 1.2.840.10008.5.1.4.1.1.9.x.x | Electrophysiology |

**Note:** Many waveform SOP class UIDs are placeholders (`9.x.x`) - verify exact UIDs from DICOM PS3.3 Annex A.34.

---

#### **Tier 9: Secondary Data (Derived, Reports, Annotations)**

Secondary data types that are derived from or supplement primary acquisitions.

| Priority | Modality | XNAT Session Type | DICOM Modality Code | Primary SOP Class UID | Rationale |
|----------|----------|-------------------|---------------------|----------------------|-----------|
| 32 | SR | `xnat:srSessionData` | SR | 1.2.840.10008.5.1.4.1.1.88.x | Structured reports (many subtypes) |
| 33 | SC | `xnat:otherDicomSessionData` | SC | 1.2.840.10008.5.1.4.1.1.7 | Secondary capture (generic) |
| 34 | OT | `xnat:otherDicomSessionData` | OT | Various | Other/unknown modalities |

**Rationale:**
- **SR** (Structured Reports) should be recognized as a distinct type
- **SC** (Secondary Capture) is a catch-all for screenshots, scanned documents, and derived images
- **OT** (Other) is the final fallback for truly unrecognized modalities

**Note:** Both SC and OT map to `xnat:otherDicomSessionData` - this is intentional as they represent non-standard or unclassifiable data.

---

## Special Cases and Configuration

### 1. PET/MR Handling

**Configuration:** `separatePETMR` site preference

**Options:**
- `SEPARATE_PET_MR` - Create separate PET and MR sessions
- `Pet` - Create single PET session (label modified to remove "PETMR" suffix)
- `PetMr` - Create single PET/MR combined session

**Code Reference:** `XNATSessionBuilder.java:243-246`

**Recommendation:** Default to `PetMr` (combined session) unless institution workflow requires separate sessions for billing/analysis.

---

### 2. Cross-Modality Merge Prevention

**Configuration:** `preventCrossModalityMerge` site property (default: `true`)

**Behavior:** Prevents merging scans of different modalities into the same session (e.g., prevents merging CT scans into an existing MR session).

**Code Reference:** `PrearcSessionValidator.java:86-89`

**Recommendation:** Keep enabled to prevent data corruption and maintain session integrity.

---

### 3. Video vs. Static Image Disambiguation

**Challenge:** Video variants (ESV, XCV, GMV) share SOP class prefixes with static variants.

**Disambiguation Strategy:**
1. Check for multi-frame attributes: `(0028,0008)` Number of Frames > 1
2. Inspect SOP Class UID suffix (`.1` often indicates video/multi-frame)
3. Check `(0008,0008)` Image Type for "VIDEO" or "DYNAMIC"

**Recommendation:** Implement SOP class-specific checks before falling back to modality-based classification.

---

### 4. Waveform Modality SOP Class Verification

**Issue:** Many waveform modalities (EEG, MEG, EPS, EMG, EOG) have placeholder SOP class UIDs in common references.

**Action Required:**
1. Verify exact SOP class UIDs from **DICOM PS3.3 Annex A.34** (Waveform IOD)
2. Test with actual waveform DICOM files from each modality
3. Update factory implementations with correct SOP class mappings

**Recommendation:** Consult DICOM PS3.3 2024d or later for authoritative SOP class definitions.

---

## Implementation Guidelines

### 1. Factory Implementation Order

Factories should be registered in priority order. XNAT iterates through factories in sequence until one successfully creates a session.

**Current Pattern:** Spring-managed beans or list configuration

**File:** `DicomImportConfig.java`
```java
@Bean
public List<String> sessionDataFactoryClasses() {
    return Arrays.asList(
        "org.nrg.dcm.xnat.MRSessionDataFactory",      // Priority 1
        "org.nrg.dcm.xnat.CTSessionDataFactory",      // Priority 2
        "org.nrg.dcm.xnat.PETSessionDataFactory",     // Priority 3
        // ... continue in priority order
        "org.nrg.dcm.xnat.OtherDicomSessionDataFactory" // Last resort
    );
}
```

---

### 2. SOP Class Matching Strategy

**Recommended Approach:**
1. **Exact SOP Class Match** - Check full UID first
2. **SOP Class Family Match** - Use UID prefix for related types (e.g., RT family: `1.2.840.10008.5.1.4.1.1.481.*`)
3. **Modality Fallback** - Use `(0008,0060)` Modality tag only if SOP class is unrecognized

**Example Factory Pattern:**
```java
public class MRSessionDataFactory implements XnatImagesessiondataBeanFactory {

    @Override
    public boolean canHandleStudy(DicomObject dcm) {
        String sopClassUid = dcm.getString(Tag.SOPClassUID);

        // Exact match
        if ("1.2.840.10008.5.1.4.1.1.4".equals(sopClassUid)) {
            return true;  // MR Image Storage
        }

        // Enhanced MR Image Storage
        if ("1.2.840.10008.5.1.4.1.1.4.1".equals(sopClassUid)) {
            return true;
        }

        // Fallback to modality tag
        String modality = dcm.getString(Tag.Modality);
        return "MR".equals(modality);
    }

    @Override
    public String getSessionType() {
        return "xnat:mrSessionData";
    }
}
```

---

### 3. Testing Strategy

**Critical Test Cases:**

1. **Single Modality Studies** - Ensure correct session type for each modality
2. **Multi-Modality Studies** - Test PET/MR, PET/CT handling
3. **Ambiguous Cases** - Test OT, SC, and unrecognized SOP classes
4. **Video vs. Static** - Verify ESV/ES, XCV/XC, GMV/GM disambiguation
5. **Specialized Subtypes** - Confirm XA3D detected before XA, DX3D before DX
6. **Cross-Modality Prevention** - Verify reject when merging CT into MR session

**Test Data Location:** `/Users/james/projects/data/` (per CLAUDE.md)

**Example Test:**
```java
@Test
public void testMRSessionRecognition() {
    File dicomDir = new File("../data/sample_mr_study/");
    File outputXml = new File("target/test-mr-session.xml");

    XNATSessionBuilder builder = new XNATSessionBuilder(
        dicomDir, outputXml, "TestProject", true
    );

    assertTrue(builder.execute());

    XnatImagesessiondataBean session = PrearcTableBuilder.parseSession(outputXml);
    assertEquals("xnat:mrSessionData", session.getXSIType());
}
```

---

## Migration and Backward Compatibility

### Existing Data Considerations

**Issue:** Changing recognition order may affect how new data is classified, but should not affect existing archived sessions.

**Safe Migration Strategy:**
1. Deploy new recognition order to **prearchive only** initially
2. Monitor prearchive classifications for 1-2 weeks
3. Review any sessions that change classification compared to historical pattern
4. Adjust factory order if unexpected classifications occur
5. Deploy to production archive once validated

**Backward Compatibility:**
- Existing `xnat:*SessionData` types must remain unchanged
- Any new session types should extend `xnat:imageSessionData`
- Database schema changes require careful migration planning

---

## Configuration Files Reference

### Current XNAT Configuration

**Session Builder Configuration:**
- **File:** `session-builder.properties`
- **Location:** `$XNAT_HOME/config/` or `META-INF/xnat/**/*-session-builder.properties`
- **Format:**
  ```properties
  org.nrg.SessionBuilder.impl=DICOM
  org.nrg.SessionBuilder.impl.DICOM.className=org.nrg.dcm.xnat.DICOMSessionBuilder
  org.nrg.SessionBuilder.impl.DICOM.sequence=0

  org.nrg.SessionBuilder.impl=ECAT
  org.nrg.SessionBuilder.impl.ECAT.className=org.nrg.ecat.xnat.PETSessionBuilder
  org.nrg.SessionBuilder.impl.ECAT.sequence=1
  ```

**Modality Code Derivation:**
- **File:** `PrearcSessionArchiver.java:888-892`
- **Logic:** Extract first 2 characters after `xnat:` prefix
- **Special Case:** `PE` → `PT` correction for PET

---

## Appendix A: Complete Session Type Mapping Table

| Modality Code | DICOM Standard Name | XNAT Session Type | SOP Class UID | Priority | Notes |
|---------------|---------------------|-------------------|---------------|----------|-------|
| MR | Magnetic Resonance | `xnat:mrSessionData` | 1.2.840.10008.5.1.4.1.1.4 | 1 | Most common |
| CT | Computed Tomography | `xnat:ctSessionData` | 1.2.840.10008.5.1.4.1.1.2 | 2 | Second most common |
| PT | Positron Emission Tomography | `xnat:petSessionData` | 1.2.840.10008.5.1.4.1.1.128 | 3 | Check before PET/MR |
| PT+MR | PET/MR | `xnat:petmrSessionData` | Multiple | 4 | Combined modality |
| US | Ultrasound | `xnat:usSessionData` | 1.2.840.10008.5.1.4.1.1.6.1 | 5 | - |
| NM | Nuclear Medicine | `xnat:nmSessionData` | 1.2.840.10008.5.1.4.1.1.20 | 6 | Distinct from PET |
| XA | X-Ray Angiography (3D) | `xnat:xa3DSessionData` | 1.2.840.10008.5.1.4.1.1.12.2.1 | 7 | Check before 2D XA |
| XA | X-Ray Angiography | `xnat:xaSessionData` | 1.2.840.10008.5.1.4.1.1.12.1 | 8 | - |
| RF | Radio Fluoroscopy | `xnat:rfSessionData` | 1.2.840.10008.5.1.4.1.1.12.2 | 9 | - |
| DX | Digital Radiography (3D Cranio) | `xnat:dx3DCraniofacialSessionData` | 1.2.840.10008.5.1.4.1.1.1.1 | 10 | Specialized, check first |
| DX | Digital Radiography | `xnat:dxSessionData` | 1.2.840.10008.5.1.4.1.1.1.1 | 11 | - |
| CR | Computed Radiography | `xnat:crSessionData` | 1.2.840.10008.5.1.4.1.1.1 | 12 | - |
| MG | Mammography | `xnat:mgSessionData` | 1.2.840.10008.5.1.4.1.1.1.2 | 13 | - |
| RTIMAGE, RTDOSE, RTSTRUCT, RTPLAN | Radiation Therapy | `xnat:rtSessionData` | 1.2.840.10008.5.1.4.1.1.481.x | 14 | Multi-object session |
| OPT | Ophthalmic Tomography | `xnat:optSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.5.4 | 15 | OCT, check before OP |
| OP | Ophthalmic Photography | `xnat:opSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.5.1 | 16 | - |
| SM | Slide Microscopy | `xnat:smSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.6 | 17 | Whole slide imaging |
| GM | General Microscopy (Video) | `xnat:gmvSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | 18 | Video, check first |
| GM | General Microscopy | `xnat:gmSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.4 | 19 | Static images |
| ES | Endoscopy (Video) | `xnat:esvSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.1.1 | 20 | Video, check first |
| ES | Endoscopy | `xnat:esSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.1 | 21 | Static images |
| XC | External Camera (Video) | `xnat:xcvSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.4.1 | 22 | Video, check first |
| XC | External Camera Photography | `xnat:xcSessionData` | 1.2.840.10008.5.1.4.1.1.77.1.4 | 23 | Static images |
| IO | Intra-oral Radiography | `xnat:ioSessionData` | 1.2.840.10008.5.1.4.1.1.1.3 | 24 | Dental imaging |
| IVUS | Intravascular Ultrasound | `xnat:ivusSessionData` | 1.2.840.10008.5.1.4.1.1.6.2 | 25 | Specialized US |
| PA | Photoacoustic | `xnat:paSessionData` | 1.2.840.10008.5.1.4.1.1.68.1 | 26 | Emerging modality |
| HD | Hemodynamic Waveform | `xnat:hdSessionData` | 1.2.840.10008.5.1.4.1.1.9.1.x | 27 | - |
| ECG | Electrocardiography | `xnat:ecgSessionData` | 1.2.840.10008.5.1.4.1.1.9.1.1 | 28 | 12-lead ECG |
| EEG | Electroencephalography | `xnat:eegSessionData` | 1.2.840.10008.5.1.4.1.1.9.x.x | 29 | Verify SOP class |
| MEG | Magnetoencephalography | `xnat:megSessionData` | 1.2.840.10008.5.1.4.1.1.9.x.x | 30 | Verify SOP class |
| EPS | Electrophysiology | `xnat:epsSessionData` | 1.2.840.10008.5.1.4.1.1.9.x.x | 31 | Verify SOP class |
| SR | Structured Report | `xnat:srSessionData` | 1.2.840.10008.5.1.4.1.1.88.x | 32 | Many subtypes |
| SC | Secondary Capture | `xnat:otherDicomSessionData` | 1.2.840.10008.5.1.4.1.1.7 | 33 | Generic fallback |
| OT | Other | `xnat:otherDicomSessionData` | Various | 34 | Final fallback |

---

## Appendix B: DICOM Standard References

### Primary References

1. **DICOM PS3.3** - Information Object Definitions
   https://dicom.nema.org/medical/dicom/current/output/chtml/part03/

2. **DICOM PS3.6** - Data Dictionary
   https://dicom.nema.org/medical/dicom/current/output/chtml/part06/

3. **DICOM PS3.4** - Service Class Specifications
   https://dicom.nema.org/medical/dicom/current/output/chtml/part04/

### SOP Class References by Modality

- **MR Image Storage:** Part 03, Annex A.4
- **CT Image Storage:** Part 03, Annex A.3
- **PET Image Storage:** Part 03, Annex A.38
- **Ultrasound Image Storage:** Part 03, Annex A.7
- **X-Ray Angiographic:** Part 03, Annex A.13
- **Radiation Therapy:** Part 03, Annex A.19
- **Ophthalmic:** Part 03, Annex A.39
- **Visible Light:** Part 03, Annex A.32
- **Waveform:** Part 03, Annex A.34
- **Structured Report:** Part 03, Annex A.35

---

## Appendix C: Code Locations Reference

| Component | File Path | Lines | Description |
|-----------|-----------|-------|-------------|
| Session Builder | `xnat-web/src/main/java/org/nrg/xnat/archive/XNATSessionBuilder.java` | 169-186 | Builder iteration logic |
| DICOM Session Build | `XNATSessionBuilder.java` | 240-271 | DICOMSessionBuilder instantiation |
| PET/MR Handling | `XNATSessionBuilder.java` | 243-246 | separatePETMR preference logic |
| Factory Configuration | `xnat-web/src/main/java/org/nrg/xnat/configuration/DicomImportConfig.java` | 30-50 | Spring bean configuration |
| Modality Code Extraction | `xnat-web/src/main/java/org/nrg/xnat/archive/PrearcSessionArchiver.java` | 888-892 | XSI type to modality code |
| Cross-Modality Check | `xnat-web/src/main/java/org/nrg/xnat/archive/PrearcSessionValidator.java` | 86-89 | Merge prevention validation |

---

## Document History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2025-11-12 | System | Initial document creation based on XNAT source code analysis and DICOM standard review |

---

## References

1. XNAT Documentation: How XNAT Translates DICOM Metadata
   https://wiki.xnat.org/documentation/how-xnat-translates-dicom-metadata

2. XNAT Source Code Repository
   `/Users/james/projects/xnat-web`

3. DICOM Modality Reference
   `/Users/james/projects/xnat_misc/dicom-modality-info/modalities.md`

4. NEMA DICOM Standard
   https://www.dicomstandard.org/

---

**End of Document**
