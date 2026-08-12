BEGIN;

DO $$
DECLARE
    user_a uuid;
    user_b uuid;
    org_a uuid;
    org_b uuid;
    batch_a uuid;
    batch_b uuid;
    durian_id uuid;
    fresh_form_id uuid;
    other_product_id uuid;
    other_form_id uuid;
    other_variety_id uuid;
    vn_id uuid;
    cn_id uuid;
    market_id_value uuid;
    grower_entity_id uuid;
    packer_entity_id uuid;
BEGIN
    INSERT INTO users(email, full_name, status)
    VALUES ('batch-a@example.com', 'Batch User A', 'ACTIVE') RETURNING id INTO user_a;
    INSERT INTO users(email, full_name, status)
    VALUES ('batch-b@example.com', 'Batch User B', 'ACTIVE') RETURNING id INTO user_b;

    INSERT INTO organizations(name, created_by)
    VALUES ('Batch Org A', user_a) RETURNING id INTO org_a;
    INSERT INTO organizations(name, created_by)
    VALUES ('Batch Org B', user_b) RETURNING id INTO org_b;

    SELECT id INTO vn_id FROM countries WHERE iso2_code = 'VN';
    SELECT id INTO cn_id FROM countries WHERE iso2_code = 'CN';
    SELECT id INTO market_id_value FROM markets WHERE code = 'CN_GACC';
    SELECT id INTO durian_id FROM products WHERE code = 'DURIAN';
    SELECT id INTO fresh_form_id
    FROM product_forms WHERE product_id = durian_id AND code = 'FRESH';

    INSERT INTO products(code, name_vi, name_en, category)
    VALUES ('BATCH_OTHER', 'Sản phẩm khác', 'Other product', 'TEST')
    RETURNING id INTO other_product_id;
    INSERT INTO product_forms(product_id, code, name_vi, name_en)
    VALUES (other_product_id, 'OTHER_FORM', 'Dạng khác', 'Other form')
    RETURNING id INTO other_form_id;
    INSERT INTO product_varieties(product_id, code, name)
    VALUES (other_product_id, 'OTHER_VARIETY', 'Other variety')
    RETURNING id INTO other_variety_id;

    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_a, 'SHARED-001', vn_id, cn_id, market_id_value, user_a)
    RETURNING id INTO batch_a;

    INSERT INTO export_batches(
        organization_id, batch_code, origin_country_id,
        destination_country_id, market_id, created_by
    ) VALUES (org_b, 'SHARED-001', vn_id, cn_id, market_id_value, user_b)
    RETURNING id INTO batch_b;

    BEGIN
        INSERT INTO export_batches(
            organization_id, batch_code, origin_country_id,
            destination_country_id, market_id, created_by
        ) VALUES (org_a, 'SHARED-001', vn_id, cn_id, market_id_value, user_a);
        RAISE EXCEPTION 'Duplicate tenant batch code was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO export_batch_items(
        organization_id, batch_id, product_id, variety_id, product_form_id,
        quantity, quantity_unit, net_weight_kg
    ) VALUES (org_a, batch_a, durian_id, NULL, fresh_form_id, 10, 'BOX', 100);

    BEGIN
        INSERT INTO export_batch_items(
            organization_id, batch_id, product_id, product_form_id
        ) VALUES (org_b, batch_a, durian_id, fresh_form_id);
        RAISE EXCEPTION 'Cross-tenant batch item was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO export_batch_items(
            organization_id, batch_id, product_id, variety_id, product_form_id
        ) VALUES (org_a, batch_a, durian_id, other_variety_id, fresh_form_id);
        RAISE EXCEPTION 'Variety from another product was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO export_batch_items(
            organization_id, batch_id, product_id, product_form_id
        ) VALUES (org_a, batch_a, durian_id, other_form_id);
        RAISE EXCEPTION 'Form from another product was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    INSERT INTO registered_export_entities(
        entity_type, registry_namespace, registry_code, name, country_id
    ) VALUES ('GROWING_AREA', 'TEST_REGISTRY', 'PUC-001', 'Test growing area', vn_id)
    RETURNING id INTO grower_entity_id;

    INSERT INTO registered_export_entities(
        entity_type, registry_namespace, registry_code, name, country_id
    ) VALUES ('PACKING_FACILITY', 'TEST_REGISTRY', 'PHC-001', 'Test packing facility', vn_id)
    RETURNING id INTO packer_entity_id;

    BEGIN
        INSERT INTO registered_export_entities(
            entity_type, registry_namespace, registry_code, name, country_id
        ) VALUES ('GROWING_AREA', 'test_registry', 'puc-001', 'Duplicate', vn_id);
        RAISE EXCEPTION 'Duplicate registry namespace/code was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    INSERT INTO organization_registered_entities(
        organization_id, registered_entity_id, relationship_type, valid_from
    ) VALUES (org_a, grower_entity_id, 'SUPPLIER', DATE '2026-01-01');

    BEGIN
        INSERT INTO organization_registered_entities(
            organization_id, registered_entity_id, relationship_type, valid_from, valid_to
        ) VALUES (
            org_a, packer_entity_id, 'CONTRACTED',
            DATE '2026-12-31', DATE '2026-01-01'
        );
        RAISE EXCEPTION 'Invalid organization/entity validity range was accepted';
    EXCEPTION WHEN check_violation THEN
        NULL;
    END;

    INSERT INTO batch_registered_entities(
        organization_id, batch_id, registered_entity_id, entity_role
    ) VALUES (org_a, batch_a, grower_entity_id, 'GROWER');
    INSERT INTO batch_registered_entities(
        organization_id, batch_id, registered_entity_id, entity_role
    ) VALUES (org_a, batch_a, packer_entity_id, 'PACKER');

    BEGIN
        INSERT INTO batch_registered_entities(
            organization_id, batch_id, registered_entity_id, entity_role
        ) VALUES (org_a, batch_a, grower_entity_id, 'GROWER');
        RAISE EXCEPTION 'Duplicate batch/entity/role link was accepted';
    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;

    BEGIN
        INSERT INTO batch_registered_entities(
            organization_id, batch_id, registered_entity_id, entity_role
        ) VALUES (org_b, batch_a, grower_entity_id, 'GROWER');
        RAISE EXCEPTION 'Cross-tenant batch/entity link was accepted';
    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM export_batches
        WHERE id = batch_b AND organization_id = org_b AND batch_code = 'SHARED-001'
    ) THEN
        RAISE EXCEPTION 'Same batch code was not accepted for another organization';
    END IF;
END $$;

ROLLBACK;

SELECT 'phase 02 batch and registry assertions passed' AS result;

