-- ======================================================================================
-- STEP 2: SYNTHETIC DATA POPULATION & ANALYTICAL SQL VIEW COMPILATION
-- ======================================================================================

-- 1. POPULATE LIBRARY BRANCHES (Fixed UC Berkeley Campus Infrastructure)
INSERT INTO dim_branch (branch_id, branch_name, campus_zone, total_capacity, is_24_7_service) VALUES
('BR_DOE', 'Doe Memorial Library', 'Central Campus', 1200, FALSE),
('BR_MOFF', 'Moffitt Undergraduate Library', 'Central Campus', 1800, TRUE),
('BR_BANC', 'Bancroft Special Collections', 'Central Campus', 250, FALSE),
('BR_ENGR', 'Kresge Engineering Library', 'North Side', 600, FALSE),
('BR_HAAS', 'Long Business Library (Haas)', 'South Side', 450, FALSE)
ON CONFLICT (branch_id) DO NOTHING;


-- 2. POPULATE DIGITAL RESOURCES (Actual Academic Pricing & Licensing Models)
INSERT INTO dim_digital_resource (resource_id, resource_title, publisher, subject_domain, annual_subscription_cost, license_model) VALUES
('RES_SD_CORE', 'ScienceDirect Complete College Package', 'Elsevier', 'Multidisciplinary', 185000.00, 'Big Deal Bundle'),
('RES_IEEE_XPL', 'IEEE Xplore Digital Library', 'IEEE', 'Engineering', 95000.00, 'Core Direct'),
('RES_JSTOR_ARC', 'JSTOR Arts & Sciences Collection', 'ITHAKA / JSTOR', 'Humanities', 42000.00, 'Core Direct'),
('RES_SPR_NAT', 'SpringerLink Scientific Journals', 'Springer Nature', 'Sciences', 130000.00, 'Big Deal Bundle'),
('RES_WRDS_BUS', 'Wharton Research Data Services (WRDS)', 'Wharton / Multiple', 'Business', 75000.00, 'Core Direct'),
('RES_BIO_ONE', 'BioOne Complete Research Package', 'BioOne', 'Life Sciences', 28000.00, 'Core Direct'),
('RES_OLD_LEG', 'Historical Legal Treatises Micro-Archive', 'Gale / Cengage', 'Law', 34000.00, 'Big Deal Bundle')
ON CONFLICT (resource_id) DO NOTHING;


-- 3. POPULATE DATE DIMENSION (30 Days * 24 Hours = 720 Temporal Intervals)
INSERT INTO dim_date_time (date_key, full_date, hour_of_day, day_of_week, is_weekend, academic_term_phase)
SELECT 
    to_char(d, 'YYYYMMDD')::INT AS date_key,
    d::DATE AS full_date,
    h AS hour_of_day,
    TRIM(to_char(d, 'Day')) AS day_of_week,
    EXTRACT(ISODOW FROM d) IN (6, 7) AS is_weekend,
    CASE 
        WHEN d < '2026-09-10' THEN 'Regular Term'
        WHEN d BETWEEN '2026-09-10' AND '2026-09-20' THEN 'Midterm Rush'
        ELSE 'Finals Week'
    END AS academic_term_phase
FROM generate_series('2026-09-01'::DATE, '2026-09-30'::DATE, '1 day'::interval) d
CROSS JOIN generate_series(0, 23) h
ON CONFLICT (date_key) DO NOTHING;


-- 4. POPULATE PATRONS (500 Realistic Hashed UC Berkeley Affiliates)
INSERT INTO dim_patron (patron_id, patron_type, college_affiliation, academic_standing)
SELECT 
    'PATRON_' || (10000 + i) AS patron_id,
    (ARRAY['Undergraduate', 'Undergraduate', 'Undergraduate', 'Graduate', 'Graduate', 'Faculty', 'Postdoctoral'])[floor(random()*7 + 1)] AS patron_type,
    (ARRAY['Haas School of Business', 'College of Engineering', 'Letters & Science', 'School of Law', 'Computing & Data Science'])[floor(random()*5 + 1)] AS college_affiliation,
    (ARRAY['Freshman', 'Sophomore', 'Junior', 'Senior', 'Masters', 'Doctoral'])[floor(random()*6 + 1)] AS academic_standing
FROM generate_series(1, 500) i
ON CONFLICT (patron_id) DO NOTHING;


-- 5. POPULATE PHYSICAL TURNSTILE SENSOR LOGS (4,000 Entries & Exits)
-- 1. Clear out low-volume turnstile data
TRUNCATE TABLE fact_physical_turnstile;

-- 2. Populate realistic campus traffic with diurnal flow and academic surges
INSERT INTO fact_physical_turnstile (patron_id, branch_id, date_key, event_timestamp, event_type, turnstile_gate_number)
WITH SurgeEvents AS (
    -- Regular Term: Base volume (~20,000 swipes across Sept 1 to 9)
    SELECT 
        (ARRAY['BR_MOFF', 'BR_MOFF', 'BR_DOE', 'BR_DOE', 'BR_ENGR', 'BR_HAAS', 'BR_BANC'])[floor(random()*7 + 1)] AS branch_id,
        '2026-09-01 07:30:00'::timestamp 
        + (floor(random() * 9) * interval '1 day') 
        + (floor(random() * 15) * interval '1 hour') 
        + (floor(random() * 60) * interval '1 minute') AS ts
    FROM generate_series(1, 20000)

    UNION ALL

    -- Midterm Rush: 2x surge (~40,000 swipes across Sept 10 to 19)
    SELECT 
        (ARRAY['BR_MOFF', 'BR_MOFF', 'BR_MOFF', 'BR_DOE', 'BR_DOE', 'BR_ENGR', 'BR_HAAS', 'BR_BANC'])[floor(random()*8 + 1)] AS branch_id,
        '2026-09-10 07:30:00'::timestamp 
        + (floor(random() * 10) * interval '1 day') 
        + (floor(random() * 15) * interval '1 hour') 
        + (floor(random() * 60) * interval '1 minute') AS ts
    FROM generate_series(1, 40000)

    UNION ALL

    -- Finals Week: Peak surge (~60,000 swipes across Sept 20 to 29)
    SELECT 
        (ARRAY['BR_MOFF', 'BR_MOFF', 'BR_MOFF', 'BR_DOE', 'BR_DOE', 'BR_ENGR', 'BR_HAAS', 'BR_BANC'])[floor(random()*8 + 1)] AS branch_id,
        '2026-09-20 07:30:00'::timestamp 
        + (floor(random() * 10) * interval '1 day') 
        + (floor(random() * 15) * interval '1 hour') 
        + (floor(random() * 60) * interval '1 minute') AS ts
    FROM generate_series(1, 60000)
)
SELECT 
    'PATRON_' || (10000 + floor(random()*500 + 1)) AS patron_id,
    s.branch_id,
    to_char(s.ts, 'YYYYMMDD')::INT AS date_key,
    s.ts AS event_timestamp,
    -- Realistic campus flow: High entries in morning/midday, high exits in evening
    CASE 
        WHEN EXTRACT(HOUR FROM s.ts) BETWEEN 7 AND 12 THEN 
            CASE WHEN random() < 0.90 THEN 'ENTRY' ELSE 'EXIT' END
        WHEN EXTRACT(HOUR FROM s.ts) BETWEEN 13 AND 16 THEN 
            CASE WHEN random() < 0.52 THEN 'ENTRY' ELSE 'EXIT' END
        WHEN EXTRACT(HOUR FROM s.ts) BETWEEN 17 AND 20 THEN 
            CASE WHEN random() < 0.22 THEN 'ENTRY' ELSE 'EXIT' END
        ELSE 
            CASE WHEN random() < 0.08 THEN 'ENTRY' ELSE 'EXIT' END
    END AS event_type,
    floor(random()*4 + 1)::INT AS turnstile_gate_number
FROM SurgeEvents s;


-- 6. POPULATE PHYSICAL CIRCULATION LOANS (1,000 Book Lending Records)
INSERT INTO fact_physical_circulation (patron_id, branch_id, date_key, checkout_timestamp, return_timestamp, item_category, loan_duration_days)
SELECT 
    'PATRON_' || (10000 + floor(random()*500 + 1)) AS patron_id,
    (ARRAY['BR_DOE', 'BR_MOFF', 'BR_ENGR', 'BR_HAAS', 'BR_BANC'])[floor(random()*5 + 1)] AS branch_id,
    to_char(ts, 'YYYYMMDD')::INT AS date_key,
    ts AS checkout_timestamp,
    ts + (floor(random()*14 + 1) * interval '1 day') AS return_timestamp,
    (ARRAY['Course Reserve', 'General Stacks', 'General Stacks', 'AudioVisual'])[floor(random()*4 + 1)] AS item_category,
    floor(random()*14 + 1)::INT AS loan_duration_days
FROM (
    SELECT '2026-09-01 09:00:00'::timestamp + (random() * 29 * 86400 * interval '1 second') AS ts
    FROM generate_series(1, 1000)
) sub;


-- 7. POPULATE DIGITAL ACCESS & DOWNLOADS (6,000 Weighted Proxy Clickstreams)
-- Uses weighted probabilities to simulate low utilization for niche packages like RES_OLD_LEG
INSERT INTO fact_digital_access (patron_id, resource_id, date_key, access_timestamp, access_action, session_duration_sec, access_network)
SELECT 
    'PATRON_' || (10000 + floor(random()*500 + 1)) AS patron_id,
    CASE 
        WHEN r <= 0.35 THEN 'RES_SD_CORE'
        WHEN r <= 0.60 THEN 'RES_IEEE_XPL'
        WHEN r <= 0.75 THEN 'RES_JSTOR_ARC'
        WHEN r <= 0.87 THEN 'RES_SPR_NAT'
        WHEN r <= 0.95 THEN 'RES_WRDS_BUS'
        WHEN r <= 0.99 THEN 'RES_BIO_ONE'
        ELSE 'RES_OLD_LEG'
    END AS resource_id,
    to_char(ts, 'YYYYMMDD')::INT AS date_key,
    ts AS access_timestamp,
    (ARRAY['SEARCH', 'ABSTRACT_VIEW', 'PDF_DOWNLOAD', 'PDF_DOWNLOAD'])[floor(random()*4 + 1)] AS access_action,
    floor(random()*1500 + 30)::INT AS session_duration_sec,
    (ARRAY['AirBears_WiFi', 'OffCampus_EZproxy'])[floor(random()*2 + 1)] AS access_network
FROM (
    SELECT 
        random() AS r,
        '2026-09-01 00:00:00'::timestamp + (random() * 29 * 86400 * interval '1 second') AS ts
    FROM generate_series(1, 6000)
) sub;




-- ======================================================================================
-- 8. COMPILE THE THREE CORE ANALYTICAL VIEWS (FEEDS DIRECTLY INTO POWER BI)
-- ======================================================================================

-- VIEW 1: Publisher Contract ROI & Cost-Per-Download (CPD) Analytics
-- Evaluates academic journal and database subscriptions by calculating the exact
-- Cost-Per-Download (CPD) against annual contract costs. It categorizes digital assets into
-- strategic actions—such as renewing, renegotiating, or canceling underutilized packages—to
-- prevent university budget waste.
CREATE OR REPLACE VIEW view_kpi_publisher_roi AS
WITH ResourceMetrics AS (
    SELECT 
        r.resource_id,
        r.resource_title,
        r.publisher,
        r.subject_domain,
        r.annual_subscription_cost,
        r.license_model,
        COUNT(f.access_event_id) AS total_access_events,
        COUNT(CASE WHEN f.access_action = 'PDF_DOWNLOAD' THEN 1 END) AS total_pdf_downloads,
        COUNT(DISTINCT f.patron_id) AS unique_active_users
    FROM dim_digital_resource r
    LEFT JOIN fact_digital_access f ON r.resource_id = f.resource_id
    GROUP BY 
        r.resource_id, r.resource_title, r.publisher, 
        r.subject_domain, r.annual_subscription_cost, r.license_model
)
SELECT 
    resource_id,
    resource_title,
    publisher,
    subject_domain,
    annual_subscription_cost,
    license_model,
    total_access_events,
    total_pdf_downloads,
    unique_active_users,
    CASE 
        WHEN total_pdf_downloads > 0 
        THEN ROUND(annual_subscription_cost / total_pdf_downloads, 2)
        ELSE annual_subscription_cost 
    END AS cost_per_download_usd,
    CASE 
        WHEN total_pdf_downloads = 0 THEN 'CANCEL - Zero Usage'
        WHEN (annual_subscription_cost / NULLIF(total_pdf_downloads, 0)) > 80.00 THEN 'RENEGOTIATE - High Cost/Use'
        WHEN (annual_subscription_cost / NULLIF(total_pdf_downloads, 0)) BETWEEN 15.00 AND 80.00 THEN 'MONITOR - Moderate ROI'
        ELSE 'RENEW - High Value Portfolio'
    END AS strategic_contract_action
FROM ResourceMetrics;





-- VIEW 2: Hourly Facility Occupancy via Window Functions
-- Uses SQL window functions on RFID turnstile telemetry to calculate cumulative hourly
-- foot-traffic and capacity utilization across physical library branches. This enables
-- facility directors to dynamically adjust desk staffing, security, and HVAC energy consumption
-- to match real-time crowding during midterm and finals rushes.
CREATE OR REPLACE VIEW view_kpi_hourly_occupancy AS
WITH HourlyFlow AS (
    SELECT 
        t.branch_id,
        b.branch_name,
        b.total_capacity,
        t.event_timestamp::DATE AS full_date,
        EXTRACT(HOUR FROM t.event_timestamp)::INT AS hour_of_day,  -- Extracts actual hour (0 to 23)
        d.academic_term_phase,
        SUM(CASE WHEN t.event_type = 'ENTRY' THEN 1 ELSE 0 END) AS total_entries,
        SUM(CASE WHEN t.event_type = 'EXIT' THEN 1 ELSE 0 END) AS total_exits
    FROM fact_physical_turnstile t
    JOIN dim_branch b ON t.branch_id = b.branch_id
    JOIN dim_date_time d ON t.date_key = d.date_key
    GROUP BY 
        t.branch_id, b.branch_name, b.total_capacity, 
        t.event_timestamp::DATE, EXTRACT(HOUR FROM t.event_timestamp)::INT, d.academic_term_phase
)
SELECT 
    branch_id,
    branch_name,
    total_capacity,
    full_date,
    hour_of_day,
    academic_term_phase,
    total_entries,
    total_exits,
    (total_entries - total_exits) AS net_flow,
    -- Window function: cumulative occupancy from 00:00 to 23:00 per branch and date
    SUM(total_entries - total_exits) OVER (
        PARTITION BY branch_id, full_date 
        ORDER BY hour_of_day 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS estimated_current_occupancy,
    ROUND(
        (GREATEST(0, SUM(total_entries - total_exits) OVER (
            PARTITION BY branch_id, full_date 
            ORDER BY hour_of_day 
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ))::NUMERIC / total_capacity) * 100, 2
    ) AS capacity_utilization_pct
FROM HourlyFlow;





-- VIEW 3: Cross-College Benchmarking Analytics
-- Aggregates physical visits, book loans, and digital article downloads across UC Berkeley’s
-- independent colleges (such as Haas, Engineering, and Letters & Science) and patron tiers.
-- It provides institutional leadership with cross-departmental benchmarks to understand how different
-- academic disciplines consume library resources and ensure fair cost-sharing across schools.
CREATE OR REPLACE VIEW view_kpi_college_usage_share AS
SELECT 
    p.college_affiliation,
    p.patron_type,
    COUNT(DISTINCT p.patron_id) AS total_registered_patrons,
    COUNT(DISTINCT t.turnstile_event_id) AS total_library_visits,
    COUNT(DISTINCT c.circulation_id) AS total_physical_books_borrowed,
    COUNT(DISTINCT d.access_event_id) AS total_digital_sessions,
    COUNT(CASE WHEN d.access_action = 'PDF_DOWNLOAD' THEN 1 END) AS total_research_downloads
FROM dim_patron p
LEFT JOIN fact_physical_turnstile t ON p.patron_id = t.patron_id
LEFT JOIN fact_physical_circulation c ON p.patron_id = c.patron_id
LEFT JOIN fact_digital_access d ON p.patron_id = d.patron_id
GROUP BY p.college_affiliation, p.patron_type;





-- Verifying query to check if tables and synthetic data input is working
SELECT resource_title, publisher, annual_subscription_cost, total_pdf_downloads, cost_per_download_usd, strategic_contract_action 
FROM view_kpi_publisher_roi 
ORDER BY cost_per_download_usd DESC;