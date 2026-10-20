-- ======================================================================================
-- DATABASE SCHEMA: UC BERKELEY UNIFIED HYBRID LIBRARY & DIGITAL ASSET MANAGEMENT SYSTEM
-- ARCHITECTURAL PATTERN: Medallion Star Schema (Dimensions & Facts)
-- TARGET ENGINE: PostgreSQL
-- ======================================================================================

-- Drop existing views and tables to allow clean re-runs
DROP VIEW IF EXISTS view_kpi_hourly_occupancy CASCADE;
DROP VIEW IF EXISTS view_kpi_college_usage_share CASCADE;
DROP VIEW IF EXISTS view_kpi_publisher_roi CASCADE;

DROP TABLE IF EXISTS fact_digital_access CASCADE;
DROP TABLE IF EXISTS fact_physical_circulation CASCADE;
DROP TABLE IF EXISTS fact_physical_turnstile CASCADE;

DROP TABLE IF EXISTS dim_date_time CASCADE;
DROP TABLE IF EXISTS dim_digital_resource CASCADE;
DROP TABLE IF EXISTS dim_branch CASCADE;
DROP TABLE IF EXISTS dim_patron CASCADE;

-- --------------------------------------------------------------------------------------
-- 1. PATRON DIMENSION (dim_patron)
-- SIGNIFICANCE: Stores anonymized demographic and academic profile data for university 
-- patrons while safeguarding student privacy under FERPA guidelines. It enables cross-college 
-- benchmarking to analyze how different schools (e.g., Haas vs. Engineering) utilize campus resources[cite: 7, 8].
-- --------------------------------------------------------------------------------------
CREATE TABLE dim_patron (
    patron_id VARCHAR(64) PRIMARY KEY,              -- SHA-256 Hashed Identifier (FERPA Compliant)
    patron_type VARCHAR(20) NOT NULL,               -- Undergraduate, Graduate, Faculty, Researcher
    college_affiliation VARCHAR(50) NOT NULL,       -- Haas Business, Engineering, Letters & Science, etc.
    academic_standing VARCHAR(20) NOT NULL,         -- Freshman, Senior, Masters, Doctoral
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- --------------------------------------------------------------------------------------
-- 2. LIBRARY BRANCH DIMENSION (dim_branch)
-- SIGNIFICANCE: Maintains physical facility attributes, geographic campus zones, and safe 
-- seating capacities across all brick-and-mortar library buildings[cite: 7]. It serves as the spatial master 
-- reference to assess facility crowding, branch-specific operating costs, and space utilization[cite: 7, 8].
-- --------------------------------------------------------------------------------------
CREATE TABLE dim_branch (
    branch_id VARCHAR(10) PRIMARY KEY,
    branch_name VARCHAR(100) NOT NULL,              -- Doe Memorial, Moffitt Undergraduate, Bancroft, etc.
    campus_zone VARCHAR(30) NOT NULL,               -- Central Campus, North Side, South Side
    total_capacity INT NOT NULL,                    -- Maximum physical building capacity
    is_24_7_service BOOLEAN DEFAULT FALSE           -- Service schedule indicator
);

-- --------------------------------------------------------------------------------------
-- 3. DIGITAL SCHOLARLY RESOURCE DIMENSION (dim_digital_resource)
-- SIGNIFICANCE: Catalogs licensed academic electronic resources, annual contract costs, 
-- and vendor subscription packaging models (e.g., Big Deal bundles)[cite: 7, 8]. It provides the financial 
-- expenditure baseline necessary to compute Cost-Per-Download (CPD) metrics and evaluate publisher contract ROI[cite: 7, 8].
-- --------------------------------------------------------------------------------------
CREATE TABLE dim_digital_resource (
    resource_id VARCHAR(20) PRIMARY KEY,
    resource_title VARCHAR(150) NOT NULL,           -- ScienceDirect, IEEE Xplore, JSTOR, WRDS
    publisher VARCHAR(100) NOT NULL,                -- Elsevier, IEEE, Springer Nature, Wiley
    subject_domain VARCHAR(50) NOT NULL,            -- Engineering, Business, Humanities, Sciences
    annual_subscription_cost NUMERIC(12, 2) NOT NULL,-- Direct contract expenditure in USD
    license_model VARCHAR(30) NOT NULL              -- Big Deal Bundle, Core Direct, Open Access
);

-- --------------------------------------------------------------------------------------
-- 4. DATE & ACADEMIC CALENDAR DIMENSION (dim_date_time)
-- SIGNIFICANCE: Establishes a synchronized temporal dimension capturing hourly intervals, 
-- day classifications, and academic lifecycle phases (e.g., Midterm Rush, Finals Week)[cite: 7]. It allows 
-- analysts to correlate surges in physical foot-traffic and digital research with the university's academic calendar[cite: 7].
-- --------------------------------------------------------------------------------------
CREATE TABLE dim_date_time (
    date_key INT PRIMARY KEY,                       -- Format: YYYYMMDD
    full_date DATE NOT NULL,
    hour_of_day INT NOT NULL CHECK (hour_of_day BETWEEN 0 AND 23),
    day_of_week VARCHAR(15) NOT NULL,
    is_weekend BOOLEAN NOT NULL,
    academic_term_phase VARCHAR(30) NOT NULL        -- Regular Term, Midterm Rush, Finals Week
);

-- --------------------------------------------------------------------------------------
-- 5. PHYSICAL TURNSTILE SENSOR FACT (fact_physical_turnstile)
-- SIGNIFICANCE: Ingests high-velocity streaming RFID gate telemetry tracking student 
-- and faculty entries and exits at physical building turnstiles[cite: 7]. It powers real-time in-building 
-- occupancy modeling, crowd safety monitoring, and dynamic HVAC/janitorial staffing optimization[cite: 7, 8].
-- --------------------------------------------------------------------------------------
CREATE TABLE fact_physical_turnstile (
    turnstile_event_id SERIAL PRIMARY KEY,
    patron_id VARCHAR(64) NOT NULL REFERENCES dim_patron(patron_id),
    branch_id VARCHAR(10) NOT NULL REFERENCES dim_branch(branch_id),
    date_key INT NOT NULL REFERENCES dim_date_time(date_key),
    event_timestamp TIMESTAMP NOT NULL,
    event_type VARCHAR(10) NOT NULL CHECK (event_type IN ('ENTRY', 'EXIT')),
    turnstile_gate_number INT NOT NULL
);

-- --------------------------------------------------------------------------------------
-- 6. PHYSICAL CIRCULATION FACT (fact_physical_circulation)
-- SIGNIFICANCE: Records traditional batch lending transactions, renewals, and returns 
-- for physical books, reserve texts, and audio-visual assets[cite: 7]. It helps library administrators 
-- measure the circulation velocity of physical collections and identify low-turnover stacks suitable for off-site archiving[cite: 7].
-- --------------------------------------------------------------------------------------
CREATE TABLE fact_physical_circulation (
    circulation_id SERIAL PRIMARY KEY,
    patron_id VARCHAR(64) NOT NULL REFERENCES dim_patron(patron_id),
    branch_id VARCHAR(10) NOT NULL REFERENCES dim_branch(branch_id),
    date_key INT NOT NULL REFERENCES dim_date_time(date_key),
    checkout_timestamp TIMESTAMP NOT NULL,
    return_timestamp TIMESTAMP,
    item_category VARCHAR(50) NOT NULL,             -- Course Reserve, General Stacks, AudioVisual
    loan_duration_days INT
);

-- --------------------------------------------------------------------------------------
-- 7. DIGITAL ACCESS TELEMETRY FACT (fact_digital_access)
-- SIGNIFICANCE: Records granular clickstream events from on-campus networks and remote 
-- EZproxy authentications, tracking user queries, abstract reads, and PDF downloads[cite: 7]. When paired 
-- with subscription cost data, it provides evidence-based usage statistics to identify underused journals for cancellation[cite: 7, 8].
-- --------------------------------------------------------------------------------------
CREATE TABLE fact_digital_access (
    access_event_id SERIAL PRIMARY KEY,
    patron_id VARCHAR(64) NOT NULL REFERENCES dim_patron(patron_id),
    resource_id VARCHAR(20) NOT NULL REFERENCES dim_digital_resource(resource_id),
    date_key INT NOT NULL REFERENCES dim_date_time(date_key),
    access_timestamp TIMESTAMP NOT NULL,
    access_action VARCHAR(30) NOT NULL CHECK (access_action IN ('SEARCH', 'ABSTRACT_VIEW', 'PDF_DOWNLOAD')),
    session_duration_sec INT,
    access_network VARCHAR(20) NOT NULL             -- AirBears_WiFi, OffCampus_EZproxy
);

-- --------------------------------------------------------------------------------------
-- PERFORMANCE INDEXES (FOR REAL-TIME POWER BI INGESTION & FAST JOINS)
-- --------------------------------------------------------------------------------------
CREATE INDEX idx_turnstile_branch ON fact_physical_turnstile(branch_id, date_key);
CREATE INDEX idx_digital_resource ON fact_digital_access(resource_id, access_action);
CREATE INDEX idx_patron_college ON dim_patron(college_affiliation);


