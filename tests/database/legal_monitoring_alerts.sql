BEGIN;

DO $$
DECLARE
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    product_id_value uuid;
    fresh_form_id uuid;
    frozen_form_id uuid;
    unit_id_value uuid;
    source_id_value uuid;
    document_id_value uuid;
    other_document_id uuid;
    version_one uuid;
    version_two uuid;
    other_version uuid;
    section_one uuid;
    section_two uuid;
    old_requirement uuid;
    new_requirement uuid;
    wildcard_requirement uuid;
    old_limit uuid;
    new_limit uuid;
    change_id_value uuid;
    empty_change_id uuid;
    limit_item_id uuid;
    wildcard_item_id uuid;
    manager_id uuid;
    compliance_id uuid;
    outsider_id uuid;
    org_a uuid;
    org_b uuid;
    member_manager uuid;
    member_compliance uuid;
    member_outsider uuid;
    batch_match uuid;
    batch_outside uuid;
    batch_before uuid;
    batch_missing_date uuid;
    batch_wildcard uuid;
    batch_other_tenant uuid;
    check_a uuid;
    check_b uuid;
    impact_match uuid;
    impact_outside uuid;
    impact_before uuid;
    impact_missing uuid;
    impact_wildcard uuid;
    alert_id_value uuid;
    created_count integer;
    check_count integer;
BEGIN
    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';
    SELECT id INTO product_id_value FROM products WHERE code = 'DURIAN';
    SELECT id INTO fresh_form_id FROM product_forms
    WHERE product_id = product_id_value AND code = 'FRESH';
    SELECT id INTO frozen_form_id FROM product_forms
    WHERE product_id = product_id_value AND code = 'FROZEN_WHOLE';
    SELECT id INTO unit_id_value FROM measurement_units WHERE code = 'MG_PER_KG';

    INSERT INTO legal_sources(name, source_type, is_official, trust_level)
    VALUES ('TEST MONITORING SOURCE', 'OFFICIAL_PUBLICATION', true, 'PRIMARY')
    RETURNING id INTO source_id_value;
    INSERT INTO legal_documents(
        source_id, title, document_type, jurisdiction_type, language_code
    ) VALUES (
        source_id_value, 'TEST Monitoring Legal Document',
        'REGULATION', 'NATIONAL', 'en'
    ) RETURNING id INTO document_id_value;
    INSERT INTO legal_documents(
        source_id, title, document_type, jurisdiction_type, language_code
    ) VALUES (
        source_id_value, 'TEST Other Monitoring Document',
        'REGULATION', 'NATIONAL', 'en'
    ) RETURNING id INTO other_document_id;

    INSERT INTO legal_document_versions(
        legal_document_id, version_number, effective_from, status
    ) VALUES (document_id_value, 1, DATE '2026-01-01', 'UNDER_REVIEW')
    RETURNING id INTO version_one;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, previous_version_id,
        effective_from, status
    ) VALUES (
        document_id_value, 2, version_one, DATE '2027-01-01', 'UNDER_REVIEW'
    ) RETURNING id INTO version_two;
    INSERT INTO legal_document_versions(
        legal_document_id, version_number, effective_from, status
    ) VALUES (other_document_id, 1, DATE '2027-01-01', 'UNDER_REVIEW')
    RETURNING id INTO other_version;

    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (version_one, 'ARTICLE', 'TEST old monitoring section', 1)
    RETURNING id INTO section_one;
    INSERT INTO legal_sections(version_id, section_type, content, order_index)
    VALUES (version_two, 'ARTICLE', 'TEST new monitoring section', 1)
    RETURNING id INTO section_two;

    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, effective_from, status
    ) VALUES (
        section_one, 'TEST-MONITOR-OLD', 'TEST old limit', 'TEST old structured rule',
        'PESTICIDE_RESIDUE', 'MUST', 'NUMERIC_LIMIT',
        'HIGH', DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO old_requirement;
    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, effective_from, status
    ) VALUES (
        section_two, 'TEST-MONITOR-NEW', 'TEST new limit', 'TEST new structured rule',
        'PESTICIDE_RESIDUE', 'MUST', 'NUMERIC_LIMIT',
        'CRITICAL', DATE '2027-01-01', 'ACTIVE'
    ) RETURNING id INTO new_requirement;
    INSERT INTO legal_requirements(
        section_id, requirement_code, title, requirement_text,
        requirement_type, obligation_level, validation_type,
        severity_default, effective_from, status
    ) VALUES (
        section_two, 'TEST-MONITOR-WILDCARD', 'TEST wildcard scope',
        'TEST wildcard structured rule', 'PACKAGING', 'MUST', 'BOOLEAN',
        'MEDIUM', DATE '2027-01-01', 'ACTIVE'
    ) RETURNING id INTO wildcard_requirement;

    INSERT INTO requirement_scopes(
        requirement_id, product_id, product_form_id, market_id
    ) VALUES (new_requirement, product_id_value, fresh_form_id, market_id_value);
    INSERT INTO requirement_scopes(requirement_id, product_id, market_id)
    VALUES (wildcard_requirement, product_id_value, market_id_value);

    INSERT INTO legal_limits(
        requirement_id, product_id, product_form_id, market_id,
        limit_type, operator, limit_value, unit_id,
        normalized_limit_value, normalized_unit_id, effective_from, status
    ) VALUES (
        old_requirement, product_id_value, fresh_form_id, market_id_value,
        'MRL', 'LTE', 5, unit_id_value, 5, unit_id_value,
        DATE '2026-01-01', 'ACTIVE'
    ) RETURNING id INTO old_limit;
    INSERT INTO legal_limits(
        requirement_id, product_id, product_form_id, market_id,
        limit_type, operator, limit_value, unit_id,
        normalized_limit_value, normalized_unit_id, effective_from, status
    ) VALUES (
        new_requirement, product_id_value, fresh_form_id, market_id_value,
        'MRL', 'LTE', 3, unit_id_value, 3, unit_id_value,
        DATE '2027-01-01', 'ACTIVE'
    ) RETURNING id INTO new_limit;

    UPDATE legal_document_versions SET status = 'APPROVED'
    WHERE id IN (version_one, version_two, other_version);

    change_id_value := compare_legal_versions(version_one, version_two);
    IF NOT EXISTS (
        SELECT 1 FROM regulation_changes
        WHERE id = change_id_value AND legal_document_id = document_id_value
          AND status = 'ANALYZING' AND change_type = 'AMENDMENT'
    ) THEN
        RAISE EXCEPTION 'Valid same-document comparison was not created as analyzing';
    END IF;

    BEGIN
        PERFORM compare_legal_versions(version_one, other_version);
        RAISE EXCEPTION 'Cross-document comparison was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    empty_change_id := compare_legal_versions(NULL, other_version);
    IF NOT EXISTS (
        SELECT 1 FROM regulation_changes
        WHERE id = empty_change_id AND change_type = 'NEW' AND from_version_id IS NULL
    ) THEN
        RAISE EXCEPTION 'NEW change did not accept a null from version';
    END IF;

    BEGIN
        PERFORM compare_legal_versions(version_one, version_one);
        RAISE EXCEPTION 'Same from/to version comparison was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO regulation_change_items(
        regulation_change_id, change_category,
        old_legal_limit_id, new_legal_limit_id,
        severity, change_summary, requires_reassessment
    ) VALUES (
        change_id_value, 'LIMIT_DECREASED', old_limit, new_limit,
        'CRITICAL', 'TEST structured normalized limit decrease', true
    ) RETURNING id INTO limit_item_id;
    INSERT INTO regulation_change_items(
        regulation_change_id, change_category, new_requirement_id,
        severity, change_summary, requires_reassessment
    ) VALUES (
        change_id_value, 'REQUIREMENT_ADDED', wildcard_requirement,
        'MEDIUM', 'TEST wildcard requirement added', true
    ) RETURNING id INTO wildcard_item_id;
    IF NOT EXISTS (
        SELECT 1 FROM regulation_change_items
        WHERE id = limit_item_id AND old_legal_limit_id = old_limit
          AND new_legal_limit_id = new_limit
    ) THEN
        RAISE EXCEPTION 'Valid limit provenance was not retained';
    END IF;
    BEGIN
        INSERT INTO regulation_change_items(
            regulation_change_id, change_category, severity, change_summary
        ) VALUES (change_id_value, 'LIMIT_DECREASED', 'HIGH', 'TEST invalid shape');
        RAISE EXCEPTION 'Invalid change-item shape was accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    INSERT INTO users(email, full_name, status)
    VALUES ('monitor-manager@example.com', 'Monitoring Manager', 'ACTIVE')
    RETURNING id INTO manager_id;
    INSERT INTO users(email, full_name, status)
    VALUES ('monitor-compliance@example.com', 'Monitoring Compliance', 'ACTIVE')
    RETURNING id INTO compliance_id;
    INSERT INTO users(email, full_name, status)
    VALUES ('monitor-outsider@example.com', 'Monitoring Outsider', 'ACTIVE')
    RETURNING id INTO outsider_id;
    INSERT INTO organizations(name, created_by)
    VALUES ('TEST Monitoring Org A', manager_id) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('TEST Monitoring Org B', outsider_id) RETURNING id INTO org_b;
    INSERT INTO organization_members(
        organization_id, user_id, status, joined_at
    ) VALUES (org_a, manager_id, 'ACTIVE', now()) RETURNING id INTO member_manager;
    INSERT INTO organization_members(
        organization_id, user_id, status, joined_at
    ) VALUES (org_a, compliance_id, 'ACTIVE', now()) RETURNING id INTO member_compliance;
    INSERT INTO organization_members(
        organization_id, user_id, status, joined_at
    ) VALUES (org_b, outsider_id, 'ACTIVE', now()) RETURNING id INTO member_outsider;
    INSERT INTO organization_member_roles(organization_id, organization_member_id, role_id)
    SELECT org_a, member_manager, id FROM roles WHERE code = 'MANAGER';
    INSERT INTO organization_member_roles(organization_id, organization_member_id, role_id)
    SELECT org_a, member_compliance, id FROM roles WHERE code = 'COMPLIANCE';
    INSERT INTO organization_member_roles(organization_id, organization_member_id, role_id)
    SELECT org_b, member_outsider, id FROM roles WHERE code = 'MANAGER';

    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, planned_export_date, created_by
    ) VALUES
        (org_a, 'MON-MATCH', vn_id, cn_id, market_id_value, DATE '2027-02-01', manager_id),
        (org_a, 'MON-OUTSIDE', vn_id, cn_id, market_id_value, DATE '2027-02-01', manager_id),
        (org_a, 'MON-BEFORE', vn_id, cn_id, market_id_value, DATE '2026-12-01', manager_id),
        (org_a, 'MON-MISSING', vn_id, cn_id, market_id_value, NULL, manager_id),
        (org_a, 'MON-WILDCARD', vn_id, cn_id, market_id_value, DATE '2027-02-01', manager_id);
    SELECT id INTO batch_match FROM export_batches WHERE organization_id = org_a AND batch_code = 'MON-MATCH';
    SELECT id INTO batch_outside FROM export_batches WHERE organization_id = org_a AND batch_code = 'MON-OUTSIDE';
    SELECT id INTO batch_before FROM export_batches WHERE organization_id = org_a AND batch_code = 'MON-BEFORE';
    SELECT id INTO batch_missing_date FROM export_batches WHERE organization_id = org_a AND batch_code = 'MON-MISSING';
    SELECT id INTO batch_wildcard FROM export_batches WHERE organization_id = org_a AND batch_code = 'MON-WILDCARD';
    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id, destination_country_id,
        market_id, planned_export_date, created_by
    ) VALUES (
        org_b, 'MON-OTHER-TENANT', vn_id, cn_id, market_id_value,
        DATE '2027-02-01', outsider_id
    ) RETURNING id INTO batch_other_tenant;

    INSERT INTO export_batch_items(organization_id, batch_id, product_id, product_form_id)
    VALUES
        (org_a, batch_match, product_id_value, fresh_form_id),
        (org_a, batch_outside, product_id_value, frozen_form_id),
        (org_a, batch_before, product_id_value, fresh_form_id),
        (org_a, batch_missing_date, product_id_value, fresh_form_id),
        (org_a, batch_wildcard, product_id_value, frozen_form_id),
        (org_b, batch_other_tenant, product_id_value, fresh_form_id);

    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number
    ) VALUES (org_a, batch_match, market_id_value, manager_id, 1)
    RETURNING id INTO check_a;
    INSERT INTO compliance_checks(
        organization_id, batch_id, market_id, created_by, check_number
    ) VALUES (org_b, batch_other_tenant, market_id_value, outsider_id, 1)
    RETURNING id INTO check_b;
    SELECT count(*) INTO check_count FROM compliance_checks WHERE organization_id = org_a;

    PERFORM confirm_regulation_change(change_id_value, manager_id, 'TEST manually confirmed structured diff');
    PERFORM confirm_regulation_change(empty_change_id, manager_id, 'TEST confirmed empty change');

    impact_match := assess_batch_legal_impact(org_a, batch_match, limit_item_id, check_a);
    impact_outside := assess_batch_legal_impact(org_a, batch_outside, limit_item_id, NULL);
    impact_before := assess_batch_legal_impact(org_a, batch_before, limit_item_id, NULL);
    impact_missing := assess_batch_legal_impact(org_a, batch_missing_date, limit_item_id, NULL);
    impact_wildcard := assess_batch_legal_impact(org_a, batch_wildcard, wildcard_item_id, NULL);

    IF (SELECT impact_status FROM batch_legal_impacts WHERE id = impact_match) <> 'AFFECTED'
       OR (SELECT impact_status FROM batch_legal_impacts WHERE id = impact_outside) <> 'NOT_AFFECTED'
       OR (SELECT impact_status FROM batch_legal_impacts WHERE id = impact_before) <> 'NOT_AFFECTED'
       OR (SELECT impact_status FROM batch_legal_impacts WHERE id = impact_missing) <> 'REVIEW_REQUIRED'
       OR (SELECT impact_status FROM batch_legal_impacts WHERE id = impact_wildcard) <> 'AFFECTED' THEN
        RAISE EXCEPTION 'Deterministic scope/effective-date impact resolution failed';
    END IF;

    BEGIN
        PERFORM assess_batch_legal_impact(org_a, batch_match, limit_item_id, check_b);
        RAISE EXCEPTION 'Cross-tenant previous check linkage was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO batch_legal_impacts(
            organization_id, batch_id, change_item_id, impact_status
        ) VALUES (org_a, batch_match, limit_item_id, 'AFFECTED');
        RAISE EXCEPTION 'Duplicate batch/change impact was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    IF assess_batch_legal_impact(org_a, batch_match, limit_item_id, check_a) <> impact_match
       OR (SELECT count(*) FROM batch_legal_impacts
           WHERE organization_id = org_a AND batch_id = batch_match
             AND change_item_id = limit_item_id) <> 1 THEN
        RAISE EXCEPTION 'Impact worker was not idempotent';
    END IF;

    IF (SELECT overall_result FROM compliance_checks WHERE id = check_a) IS NOT NULL
       OR (SELECT status FROM export_batches WHERE id = batch_match) <> 'DRAFT'
       OR (SELECT count(*) FROM compliance_checks WHERE organization_id = org_a) <> check_count THEN
        RAISE EXCEPTION 'Monitoring changed formal compliance or batch state';
    END IF;

    created_count := create_batch_risk_alerts(change_id_value);
    IF created_count < 1 OR NOT EXISTS (
        SELECT 1 FROM alerts WHERE impact_id = impact_match AND alert_type = 'BATCH_AT_RISK'
    ) THEN
        RAISE EXCEPTION 'Affected impact did not create a risk alert';
    END IF;
    IF create_batch_risk_alerts(change_id_value) <> 0 THEN
        RAISE EXCEPTION 'Duplicate alert worker run created alerts';
    END IF;
    IF create_batch_risk_alerts(empty_change_id) <> 0 THEN
        RAISE EXCEPTION 'Change without affected batches created a risk alert';
    END IF;
    SELECT id INTO alert_id_value FROM alerts WHERE impact_id = impact_match;

    BEGIN
        INSERT INTO alerts(
            organization_id, batch_id, regulation_change_id, change_item_id,
            impact_id, alert_type, severity, title, message
        ) VALUES (
            org_b, batch_other_tenant, change_id_value, limit_item_id,
            impact_match, 'BATCH_AT_RISK', 'HIGH', 'TEST bad tenant', 'TEST bad tenant'
        );
        RAISE EXCEPTION 'Cross-tenant alert linkage was accepted';
    EXCEPTION WHEN integrity_constraint_violation THEN NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM alert_recipients
        WHERE organization_id = org_a AND alert_id = alert_id_value AND user_id = manager_id
    ) OR NOT EXISTS (
        SELECT 1 FROM alert_recipients
        WHERE organization_id = org_a AND alert_id = alert_id_value AND user_id = compliance_id
    ) THEN
        RAISE EXCEPTION 'Permission-based organization recipients were not attached';
    END IF;
    BEGIN
        INSERT INTO alert_recipients(organization_id, alert_id, user_id)
        VALUES (org_a, alert_id_value, outsider_id);
        RAISE EXCEPTION 'Outside-organization recipient was accepted';
    EXCEPTION WHEN integrity_constraint_violation OR insufficient_privilege THEN NULL;
    END;
    BEGIN
        INSERT INTO alert_recipients(organization_id, alert_id, user_id)
        VALUES (org_a, alert_id_value, manager_id);
        RAISE EXCEPTION 'Duplicate recipient was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    created_count := create_in_app_notifications_for_alert(alert_id_value);
    IF created_count <> 2 OR create_in_app_notifications_for_alert(alert_id_value) <> 0 THEN
        RAISE EXCEPTION 'In-app notification creation or idempotency failed';
    END IF;
    BEGIN
        INSERT INTO notifications(
            organization_id, user_id, alert_id, channel, title, message,
            idempotency_key
        ) VALUES (
            org_a, manager_id, alert_id_value, 'IN_APP', 'TEST duplicate', 'TEST duplicate',
            'IN_APP:' || alert_id_value::text || ':' || manager_id::text
        );
        RAISE EXCEPTION 'Duplicate notification idempotency key was accepted';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO notifications(
            organization_id, user_id, alert_id, channel, title, message,
            attempt_number, max_attempts
        ) VALUES (org_a, manager_id, alert_id_value, 'IN_APP', 'TEST retry', 'TEST retry', 2, 1);
        RAISE EXCEPTION 'Invalid notification retry counters were accepted';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
    BEGIN
        INSERT INTO notifications(
            organization_id, user_id, alert_id, channel, title, message
        ) VALUES (org_b, outsider_id, alert_id_value, 'IN_APP', 'TEST tenant', 'TEST tenant');
        RAISE EXCEPTION 'Cross-tenant notification linkage was accepted';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;
    INSERT INTO notifications(
        organization_id, user_id, alert_id, channel, title, message,
        idempotency_key
    ) VALUES (
        org_a, manager_id, alert_id_value, 'EMAIL',
        'TEST queued email', 'TEST no provider required', 'TEST-EMAIL-NO-CREDENTIAL'
    );
    IF NOT EXISTS (
        SELECT 1 FROM notifications
        WHERE organization_id = org_a AND idempotency_key = 'TEST-EMAIL-NO-CREDENTIAL'
          AND status = 'PENDING'
    ) THEN
        RAISE EXCEPTION 'Email delivery record required external credentials';
    END IF;

    PERFORM acknowledge_alert(org_a, alert_id_value, manager_id);
    IF (SELECT status FROM alerts WHERE id = alert_id_value) <> 'ACKNOWLEDGED' THEN
        RAISE EXCEPTION 'Permitted alert acknowledgement failed';
    END IF;
END $$;

ROLLBACK;

SELECT 'phase 09 legal monitoring and alert assertions passed' AS result;
